
import Foundation
import SwiftUI
import Combine

struct LottoResult: Identifiable, Codable {
    let id: UUID
    let numbers: [Int]
    let bonusNumber: Int
    let round: Int
    let date: String
}

struct SavedNumbers: Identifiable, Codable {
    let id: UUID
    let numbers: [Int]
    let savedAt: Date
}

private struct LottoDataFile: Codable {
    let latestRound: Int
    let history: [LottoEntry]
}

private struct LottoEntry: Codable {
    let round: Int
    let numbers: [Int]
    let bonus: Int
    let date: String
}

class LottoViewModel: ObservableObject {
    @Published var generatedNumbers: [Int] = []
    @Published var isGenerating: Bool = false
    @Published var lottoHistory: [LottoResult] = []
    @Published var isLoadingHistory: Bool = false
    @Published var savedNumbersList: [SavedNumbers] = []
    @Published var latestRound: Int = 0
    @Published var apiUpdateFailed: Bool = false

    // 원격 데이터 주소: 앱을 재업로드하지 않아도 이 파일만 갱신되면 앱에 즉시 반영됩니다.
    // GitHub Actions가 매주 토요일 추첨 후 이 파일을 자동으로 최신화합니다.
    private static let remoteDataURL = "https://raw.githubusercontent.com/Eunsong-Jung119/Lotto/main/Lotto/lotto_data.json"

    init() {
        loadSavedNumbers()
        loadBundleData()          // 오프라인/최초 실행용: 번들에 포함된 데이터를 즉시 표시
        Task {
            await fetchRemoteData() // 온라인이면 GitHub의 최신 데이터로 갱신
        }
    }

    private func loadBundleData() {
        guard let url = Bundle.main.url(forResource: "lotto_data", withExtension: "json") else {
            print("❌ JSON 파일을 번들에서 찾을 수 없음")
            return
        }
        print("✅ JSON URL: \(url)")

        guard let data = try? Data(contentsOf: url) else {
            print("❌ 데이터 로드 실패")
            return
        }
        print("✅ 데이터 로드 성공: \(data.count) bytes")

        guard let file = try? JSONDecoder().decode(LottoDataFile.self, from: data) else {
            print("❌ JSON 디코딩 실패")
            return
        }
        print("✅ 디코딩 성공: \(file.history.count)개 회차")

        let results = file.history.map { entry in
            LottoResult(id: UUID(), numbers: entry.numbers, bonusNumber: entry.bonus, round: entry.round, date: entry.date)
        }.sorted { $0.round > $1.round }

        DispatchQueue.main.async {
            self.latestRound = file.latestRound
            self.lottoHistory = results
        }
    }

    // GitHub raw에서 최신 lotto_data.json을 받아와 갱신합니다.
    // 실패하면 번들 데이터를 그대로 사용하므로 앱은 항상 동작합니다.
    @MainActor
    func fetchRemoteData() async {
        guard let url = URL(string: Self.remoteDataURL) else { return }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let file = try JSONDecoder().decode(LottoDataFile.self, from: data)

            // 원격이 번들보다 최신일 때만 반영 (오래된 캐시로 되돌아가는 것 방지)
            guard file.latestRound >= self.latestRound else {
                self.apiUpdateFailed = false
                return
            }

            let results = file.history.map { entry in
                LottoResult(id: UUID(), numbers: entry.numbers, bonusNumber: entry.bonus, round: entry.round, date: entry.date)
            }.sorted { $0.round > $1.round }

            self.latestRound = file.latestRound
            self.lottoHistory = results
            self.apiUpdateFailed = false
        } catch {
            // 네트워크 실패 시 번들 데이터 유지
            self.apiUpdateFailed = true
        }
    }

    func generateNumbers() {
        isGenerating = true
        generatedNumbers = []
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            self.generatedNumbers = self.aiGenerateNumbers()
            self.isGenerating = false
        }
    }

    private func aiGenerateNumbers() -> [Int] {
        var frequency: [Int: Double] = [:]
        for i in 1...45 { frequency[i] = 1.0 }
        for result in lottoHistory {
            for num in result.numbers { frequency[num, default: 1.0] += 1.5 }
            frequency[result.bonusNumber, default: 1.0] += 0.5
        }
        if lottoHistory.count >= 10 {
            let recentNumbers = Set(lottoHistory.prefix(10).flatMap { $0.numbers })
            for i in 1...45 { if !recentNumbers.contains(i) { frequency[i, default: 1.0] += 2.0 } }
        }
        var selected: [Int] = []
        var attempts = 0
        while selected.count < 6 && attempts < 1000 {
            attempts += 1
            let candidate = weightedRandom(frequency: frequency, exclude: selected)
            let oddCount = selected.filter { $0 % 2 != 0 }.count
            let evenCount = selected.filter { $0 % 2 == 0 }.count
            if selected.count == 5 {
                if oddCount < 2 && candidate % 2 == 0 { continue }
                if evenCount < 2 && candidate % 2 != 0 { continue }
            }
            selected.append(candidate)
        }
        return selected.sorted()
    }

    private func weightedRandom(frequency: [Int: Double], exclude: [Int]) -> Int {
        let available = frequency.filter { !exclude.contains($0.key) }
        let totalWeight = available.values.reduce(0, +)
        var random = Double.random(in: 0..<totalWeight)
        for (num, weight) in available.sorted(by: { $0.key < $1.key }) {
            random -= weight
            if random <= 0 { return num }
        }
        return available.keys.first ?? 1
    }

    func saveCurrentNumbers() {
        guard !generatedNumbers.isEmpty else { return }
        let saved = SavedNumbers(id: UUID(), numbers: generatedNumbers, savedAt: Date())
        savedNumbersList.insert(saved, at: 0)
        persistSavedNumbers()
    }

    private func persistSavedNumbers() {
        if let data = try? JSONEncoder().encode(savedNumbersList) {
            UserDefaults.standard.set(data, forKey: "savedNumbers")
        }
    }

    private func loadSavedNumbers() {
        if let data = UserDefaults.standard.data(forKey: "savedNumbers"),
           let decoded = try? JSONDecoder().decode([SavedNumbers].self, from: data) {
            savedNumbersList = decoded
        }
    }

    func deleteSavedNumbers(at offsets: IndexSet) {
        savedNumbersList.remove(atOffsets: offsets)
        persistSavedNumbers()
    }
}
