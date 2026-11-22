import SwiftUI

struct HomeView: View {

    @State private var selected: Category = Site.categories[0]

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            CategoryFeed(category: selected)
                .id(selected.id)
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("KanAV")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Site.categories) { category in
                    Button {
                        guard selected.id != category.id else { return }
                        selected = category
                    } label: {
                        Text(category.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selected.id == category.id ? .white : Color.white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                Capsule().fill(selected.id == category.id ? Color.kanAccent : Color.kanCard)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - 列表流

struct CategoryFeed: View {

    let category: Category

    @StateObject private var model: FeedViewModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 10), count: count)
    }

    private var coverHeight: CGFloat {
        sizeClass == .regular ? 160 : 112
    }

    init(category: Category) {
        self.category = category
        _model = StateObject(wrappedValue: FeedViewModel(category: category))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.items) { item in
                    NavigationLink(destination: PlayerScreen(item: item)) {
                        VideoCard(item: item, coverHeight: coverHeight)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if item.id == model.items.last?.id {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 4)

            footer
        }
        .background(Color.kanBackground)
        .task {
            if model.items.isEmpty {
                await model.loadFirstPage()
            }
        }
    }

    @ViewBuilder private var footer: some View {
        if model.isLoading && !model.items.isEmpty {
            HStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
            .padding(.vertical, 20)
        } else if let message = model.errorText, model.items.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 26))
                    .foregroundColor(.gray)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await model.loadFirstPage() }
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.kanAccent))
            }
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        } else if !model.items.isEmpty && !model.hasMore {
            Text("已经到底了")
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .padding(.vertical, 18)
        }
    }
}

// MARK: - ViewModel

final class FeedViewModel: ObservableObject {

    @Published private(set) var items: [VideoItem] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var errorText: String?

    private let category: Category
    private var page = 0

    init(category: Category) {
        self.category = category
    }

    func loadFirstPage() async {
        await MainActor.run {
            self.page = 0
            self.items = []
            self.hasMore = true
            self.errorText = nil
        }
        await loadNextPage()
    }

    func loadNextPage() async {
        let busy = await MainActor.run { self.isLoading || !self.hasMore }
        if busy { return }

        await MainActor.run {
            self.isLoading = true
            self.errorText = nil
        }

        let nextPage = await MainActor.run { self.page + 1 }
        do {
            let html = try await Net.html(path: category.path(page: nextPage))
            let parsed = Parser.videos(in: html)
            await MainActor.run {
                if parsed.isEmpty {
                    self.hasMore = false
                } else {
                    let known = Set(self.items.map { $0.id })
                    self.items.append(contentsOf: parsed.filter { !known.contains($0.id) })
                    self.page = nextPage
                }
                self.isLoading = false
            }
        } catch let error {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await MainActor.run {
                self.errorText = message
                self.isLoading = false
            }
        }
    }
}
