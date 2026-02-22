import SwiftUI

struct SavedNumbersView: View {
    @ObservedObject var vm: LottoViewModel

    var body: some View {
        Group {
            if vm.savedNumbersList.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bookmark.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("저장된 번호가 없습니다")
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                    Text("번호를 생성하고 저장해보세요")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary.opacity(0.7))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(vm.savedNumbersList) { saved in
                        SavedRow(saved: saved)
                    }
                    .onDelete(perform: vm.deleteSavedNumbers)
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("저장된 번호")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            EditButton()
        }
    }
}

struct SavedRow: View {
    let saved: SavedNumbers

    var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter.string(from: saved.savedAt)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dateString)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                ForEach(saved.numbers, id: \.self) { num in
                    SmallBall(number: num, isBonus: false)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        SavedNumbersView(vm: LottoViewModel())
    }
}
