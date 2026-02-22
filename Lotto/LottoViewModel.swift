
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

    init() {
        loadSavedNumbers()
        loadBundleData()
        Task {
            await fetchLatestFromAPI()
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

    func fetchLatestFromAPI() async {
        let startRound = latestRound + 1
        let calendar = Calendar.current
        let startDate = calendar.date(from: DateComponents(year: 2002, month: 12, day: 7))!
        let estimatedLatest = (calendar.dateComponents([.day], from: startDate, to: Date()).day ?? 0) / 7 + 1

        guard estimatedLatest >= startRound else { return }

        var newResults: [LottoResult] = []
        for round in startRound...estimatedLatest {
            if let result = await fetchRound(round: round) {
                newResults.append(result)
            }
        }

        if !newResults.isEmpty {
            DispatchQueue.main.async {
                for result in newResults {
                    if !self.lottoHistory.contains(where: { $0.round == result.round }) {
                        self.lottoHistory.append(result)
                    }
                }
                self.lottoHistory.sort { $0.round > $1.round }
                if let latest = self.lottoHistory.first { self.latestRound = latest.round }
            }
        } else {
            DispatchQueue.main.async { self.apiUpdateFailed = true }
            await notifyDeveloper(failedRound: startRound)
        }
    }

    private func notifyDeveloper(failedRound: Int) async {
        guard let url = URL(string: "https://formsubmit.co/ajax/eunsongjung1997@gmail.com") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String] = [
            "subject": "로또앱 데이터 업데이트 필요",
            "message": "\(failedRound)회차부터 API 실패. lotto_data.json 수동 업데이트 필요합니다."
        ]
        request.httpBody = try? JSONEncoder().encode(body)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func fetchRound(round: Int) async -> LottoResult? {
        let urlString = "https://www.dhlottery.co.kr/common.do?method=getLottoNumber&drwNo=\(round)"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.dhlottery.co.kr/", forHTTPHeaderField: "Referer")
        request.timeoutInterval = 10
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let rv = json["returnValue"] as? String, rv == "success",
               let drwNo = json["drwNo"] as? Int,
               let n1 = json["drwtNo1"] as? Int, let n2 = json["drwtNo2"] as? Int,
               let n3 = json["drwtNo3"] as? Int, let n4 = json["drwtNo4"] as? Int,
               let n5 = json["drwtNo5"] as? Int, let n6 = json["drwtNo6"] as? Int,
               let bonus = json["bnusNo"] as? Int, let dateStr = json["drwNoDate"] as? String {
                return LottoResult(id: UUID(), numbers: [n1,n2,n3,n4,n5,n6], bonusNumber: bonus, round: drwNo, date: dateStr)
            }
        } catch {}
        return nil
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
