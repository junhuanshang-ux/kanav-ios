import SwiftUI

struct LibraryView: View {

    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        Group {
            if store.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 32))
                        .foregroundColor(.gray)
                    Text("还没有观看记录")
                        .font(.system(size: 13))
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.items) { item in
                            NavigationLink(destination: PlayerScreen(item: item)) {
                                VideoRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button(role: .destructive) {
                                    store.remove(item)
                                } label: {
                                    Label("从记录中移除", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(12)
                }
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("最近观看")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.items.isEmpty {
                    Button("清空") {
                        store.clear()
                    }
                    .foregroundColor(Color.kanAccent)
                }
            }
        }
    }
}
