import SwiftUI

struct ContentView: View {
    @StateObject private var vm = LottoViewModel()
    @State private var showSaved = false
    @State private var showCopyToast = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    numberBallsSection
                    actionButtons
                    historySection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: SavedNumbersView(vm: vm)) {
                        Image(systemName: "bookmark.fill")
                            .foregroundColor(.blue)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if showCopyToast {
                    toastView
                }
            }
        }
    }

    // MARK: - Header
    var headerSection: some View {
        VStack(spacing: 8) {
            Text("오늘의 행운을")
                .font(.system(size: 28, weight: .bold))
            Text("확인해보세요")
                .font(.system(size: 28, weight: .bold))

            if vm.latestRound > 0 {
                Text("\(vm.latestRound)회까지 학습된 데이터로\nAI가 로또 번호를 생성해드립니다")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
                    .multilineTextAlignment(.center)
            } else {
                Text("AI가 로또 번호를 생성해드립니다")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Number Balls
    var numberBallsSection: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                ForEach(0..<3) { i in
                    LottoBall(
                        number: vm.generatedNumbers.count > i ? vm.generatedNumbers[i] : nil,
                        isGenerating: vm.isGenerating
                    )
                }
            }
            HStack(spacing: 12) {
                ForEach(3..<6) { i in
                    LottoBall(
                        number: vm.generatedNumbers.count > i ? vm.generatedNumbers[i] : nil,
                        isGenerating: vm.isGenerating
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Buttons
    var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: {
                vm.generateNumbers()
            }) {
                HStack {
                    if vm.isGenerating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("AI가 새로운 로또 번호\n생성중입니다...")
                            .font(.system(size: 16, weight: .semibold))
                            .multilineTextAlignment(.center)
                    } else {
                        Text("번호 생성하기")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.blue)
                .cornerRadius(14)
            }
            .disabled(vm.isGenerating)

            Button(action: {
                guard !vm.generatedNumbers.isEmpty else { return }
                vm.saveCurrentNumbers()
                withAnimation {
                    showCopyToast = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { showCopyToast = false }
                }
            }) {
                HStack {
                    Image(systemName: "arrow.down.circle")
                    Text("생성된 번호 저장하기")
                        .font(.system(size: 17, weight: .medium))
                }
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(vm.generatedNumbers.isEmpty || vm.isGenerating)
        }
    }

    // MARK: - History
    var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("역대 회차별 당첨 번호")
                .font(.system(size: 17, weight: .bold))

            if vm.isLoadingHistory {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(vm.lottoHistory) { result in
                        HistoryRow(result: result)
                        if result.id != vm.lottoHistory.last?.id {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Toast
    var toastView: some View {
        Text("번호가 저장되었습니다 ✓")
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.75))
            .cornerRadius(20)
            .padding(.bottom, 30)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - LottoBall
struct LottoBall: View {
    let number: Int?
    let isGenerating: Bool

    var ballColor: Color {
        guard let number = number else { return Color(.systemGray5) }
        switch number {
        case 1...10: return Color(red: 1.0, green: 0.75, blue: 0.1)
        case 11...20: return Color(red: 0.35, green: 0.6, blue: 1.0)
        case 21...30: return Color(red: 1.0, green: 0.4, blue: 0.35)
        case 31...40: return Color(red: 0.6, green: 0.6, blue: 0.6)
        default: return Color(red: 0.4, green: 0.8, blue: 0.45)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(number != nil ? ballColor : Color(.systemGray5))
                .frame(width: 88, height: 88)

            if isGenerating && number == nil {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .gray))
                    .scaleEffect(0.7)
            } else if let number = number {
                Text("\(number)")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundColor(Color(.systemGray3))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: number)
    }
}

// MARK: - HistoryRow
struct HistoryRow: View {
    let result: LottoResult

    var body: some View {
        HStack(spacing: 0) {
            Text("\(result.round)회")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 52, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(result.numbers, id: \.self) { num in
                    SmallBall(number: num, isBonus: false)
                }
                Text("+")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                SmallBall(number: result.bonusNumber, isBonus: true)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - SmallBall
struct SmallBall: View {
    let number: Int
    let isBonus: Bool

    var ballColor: Color {
        if isBonus { return Color.orange }
        switch number {
        case 1...10: return Color(red: 1.0, green: 0.75, blue: 0.1)
        case 11...20: return Color(red: 0.35, green: 0.6, blue: 1.0)
        case 21...30: return Color(red: 1.0, green: 0.4, blue: 0.35)
        case 31...40: return Color(red: 0.6, green: 0.6, blue: 0.6)
        default: return Color(red: 0.4, green: 0.8, blue: 0.45)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(ballColor)
                .frame(width: 26, height: 26)
            Text("\(number)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
}
