import SwiftUI

struct HomeView: View {

    @State private var selected: Category = Site.quickCategories[0]
    @State private var showCategoryPicker = false
    @State private var randomItem: VideoItem?
    @State private var showRandomPlayer = false
    @State private var isRandomizing = false

    var body: some View {
        VStack(spacing: 0) {
            header
            categoryBar
            CategoryFeed(category: selected)
                .id(selected.id)
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationBarHidden(true)
        .sheet(isPresented: $showCategoryPicker) {
            CategoryPicker(selected: $selected, isPresented: $showCategoryPicker)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("博客")
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundColor(Color.kanTextPrimary)
                    .tracking(0.4)
                Text("40,179 部影片 · 每日更新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.kanTextSecondary)
            }

            Spacer(minLength: 0)

            headerButton("shuffle") {
                playRandom()
            }

            NavigationLink(destination: ModelsView()) {
                headerIcon("person.2.fill")
            }
            .buttonStyle(.plain)

            NavigationLink(destination: SearchView()) {
                headerIcon("magnifyingglass")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            NavigationLink(
                isActive: $showRandomPlayer,
                destination: {
                    if let item = randomItem {
                        PlayerScreen(item: item)
                    } else {
                        EmptyView()
                    }
                },
                label: { EmptyView() }
            )
            .hidden()
        )
    }

    private func headerIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(Color.kanTextPrimary)
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.kanSurface))
    }

    private func headerButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            headerIcon(name)
        }
        .buttonStyle(.plain)
    }

    /// 从最新列表里随机挑一部
    private func playRandom() {
        guard !isRandomizing else { return }
        isRandomizing = true
        Task {
            let page = Int.random(in: 1...120)
            let path = page == 1 ? "/latest-updates/" : "/latest-updates/\(page)/"
            let html = try? await Net.html(path: path, allowManualCheck: false)
            let item = html.flatMap { Parser.videos(in: $0).randomElement() }
            await MainActor.run {
                isRandomizing = false
                guard let item = item else { return }
                randomItem = item
                showRandomPlayer = true
            }
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
                    HStack(spacing: 5) {
                        Text("全部")
                        Image(systemName: "square.grid.2x2.fill").font(.system(size: 10))
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color.kanTextSecondary)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.kanSurface))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    private func categoryChip(_ category: Category) -> some View {
        let active = selected.id == category.id
        return Button {
            guard !active else { return }
            selected = category
        } label: {
            Text(category.name)
                .font(.system(size: 13, weight: active ? .bold : .medium))
                .foregroundColor(active ? Color.kanTextPrimary : Color.kanTextSecondary)
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(active ? Color.kanAccent : Color.kanSurface)
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
                                        .foregroundColor(Color.kanTextPrimary)
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
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    init(category: Category) {
        self.category = category
        _model = StateObject(wrappedValue: FeedViewModel(category: category))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(model.items) { item in
                    NavigationLink(destination: PlayerScreen(item: item)) {
                        VideoCard(item: item)
                    }
                    .buttonStyle(CardButtonStyle())
                    .onAppear {
                        if item.id == model.items.last?.id {
                            Task { await model.loadNextPage() }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

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
                .foregroundColor(Color.kanTextPrimary)
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
