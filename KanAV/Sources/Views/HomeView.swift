import SwiftUI

struct HomeView: View {

    @State private var selected: Category = Site.quickCategories[0]
    @State private var showCategoryPicker = false

    var body: some View {
        VStack(spacing: 0) {
            categoryBar
            CategoryFeed(category: selected)
                .id(selected.id)
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("博客")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPicker(selected: $selected, isPresented: $showCategoryPicker)
        }
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Site.quickCategories) { category in
                    categoryChip(category)
                }

                Button {
                    showCategoryPicker = true
                } label: {
                    HStack(spacing: 4) {
                        Text("更多")
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.7))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(Color.kanCard))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func categoryChip(_ category: Category) -> some View {
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

// MARK: - 全部分类

struct CategoryPicker: View {

    @Binding var selected: Category
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            List {
                ForEach(Site.categoryGroups) { group in
                    Section {
                        ForEach(group.items) { item in
                            Button {
                                selected = item
                                isPresented = false
                            } label: {
                                HStack {
                                    Text(item.name)
                                        .font(.system(size: 14))
                                        .foregroundColor(.white)
                                    Spacer()
                                    if item.id == selected.id {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(Color.kanAccent)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(group.group)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.5))
                    }
                }
            }
            .listStyle(.plain)
            .background(Color.kanBackground.ignoresSafeArea())
            .navigationTitle("全部分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        isPresented = false
                    }
                    .foregroundColor(Color.kanAccent)
                }
            }
        }
        .preferredColorScheme(.dark)
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
            let html = try await Net.html(path: category.pagePath(nextPage))
            var parsed = Parser.videos(in: html)

            // 分类路径失效（站点返回 404）时回退到「最新」，别让用户看到空列表
            if parsed.isEmpty, nextPage == 1, Parser.isNotFound(html),
               category.basePath != "/latest-updates/" {
                if let fallback = try? await Net.html(path: "/latest-updates/") {
                    parsed = Parser.videos(in: fallback)
                }
            }

            let nextAvailable = Parser.hasNextPage(in: html, currentPage: nextPage)
            await MainActor.run {
                if parsed.isEmpty {
                    self.hasMore = false
                } else {
                    let known = Set(self.items.map { $0.id })
                    let added = parsed.filter { !known.contains($0.id) }
                    self.items.append(contentsOf: added)
                    self.page = nextPage
                    // 有分页链接就继续；没有分页链接但仍有新内容（无限滚动式接口）也继续；
                    // 本页全是重复内容才停，避免死循环
                    self.hasMore = nextAvailable || !added.isEmpty
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
