import SwiftUI

/// 组合筛选：勾选最多 3 个标签，依次抓取后取交集。
/// jable 不支持多标签 URL，只能在客户端做。
struct ComboFilterView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selected: Set<String> = []
    @State private var results: [VideoItem] = []
    @State private var isLoading = false
    @State private var hasRun = false
    @State private var message: String?

    private let maxSelection = 3

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: count)
    }

    private var tagGroups: [CategoryGroup] {
        Site.categoryGroups.filter { $0.group != "排序" }
    }

    var body: some View {
        VStack(spacing: 0) {
            selector
            Divider().background(Color.kanSurface)
            content
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("组合筛选")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: 标签选择

    private var selector: some View {
        VStack(spacing: Spacing.sm) {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    ForEach(tagGroups) { group in
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(group.group)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color.kanTextSecondary)

                            FlowChips(
                                items: group.items,
                                selected: selected
                            ) { category in
                                toggle(category)
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
            .frame(maxHeight: 260)

            HStack(spacing: Spacing.md) {
                Text(selected.isEmpty ? "选择最多 3 个标签" : "已选 \(selected.count) 个")
                    .font(.system(size: 12))
                    .foregroundColor(Color.kanTextSecondary)

                Spacer(minLength: 0)

                if !selected.isEmpty {
                    Button("清空") {
                        selected.removeAll()
                        results = []
                        hasRun = false
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color.kanTextSecondary)
                }

                Button {
                    Task { await run() }
                } label: {
                    Text(isLoading ? "筛选中…" : "筛选")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(selected.isEmpty
                                           ? Color.kanSurface
                                           : Color.kanAccent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(selected.isEmpty || isLoading)
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.sm)
        }
    }

    // MARK: 结果

    @ViewBuilder private var content: some View {
        if isLoading && results.isEmpty {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(0..<4, id: \.self) { _ in
                        CardSkeleton()
                    }
                }
                .padding(Spacing.lg)
            }
        } else if let message = message {
            EmptyStateView(icon: "line.3.horizontal.decrease.circle", title: "没有结果", message: message)
                .padding(.top, 60)
            Spacer()
        } else if results.isEmpty {
            EmptyStateView(
                icon: "line.3.horizontal.decrease.circle",
                title: hasRun ? "这些标签没有交集" : "选几个标签试试",
                message: hasRun ? "换一个标签组合，或者少选一个" : "比如「中文字幕」+「巨乳」"
            )
            .padding(.top, 60)
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: Spacing.xl) {
                    ForEach(results) { item in
                        NavigationLink(destination: PlayerScreen(item: item)) {
                            VideoCard(item: item)
                        }
                        .buttonStyle(CardButtonStyle())
                    }
                }
                .padding(Spacing.lg)
            }
        }
    }

    // MARK: 逻辑

    private func toggle(_ category: Category) {
        if selected.contains(category.basePath) {
            selected.remove(category.basePath)
        } else {
            guard selected.count < maxSelection else { return }
            selected.insert(category.basePath)
        }
    }

    private func run() async {
        await MainActor.run {
            isLoading = true
            message = nil
            hasRun = true
        }

        var sets: [Set<String>] = []
        var pool: [String: VideoItem] = [:]

        for path in selected {
            guard let html = try? await Net.html(path: path, allowManualCheck: false) else { continue }
            let items = Parser.videos(in: html)
            guard !items.isEmpty else { continue }
            sets.append(Set(items.map { $0.id }))
            for item in items { pool[item.id] = item }
        }

        await MainActor.run {
            isLoading = false

            guard let first = sets.first else {
                message = "这几个标签都没取到内容，换一个试试"
                results = []
                return
            }

            let intersection = sets.dropFirst().reduce(first) { $0.intersection($1) }
            // 交集为空就退回并集，至少给点结果
            let finalSet = intersection.isEmpty ? Set(pool.keys) : intersection
            results = finalSet.compactMap { pool[$0] }

            if results.isEmpty {
                message = "这几个标签都没有内容"
            }
        }
    }
}

/// 自动换行的标签组
struct FlowChips: View {

    let items: [Category]
    let selected: Set<String>
    let onTap: (Category) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 76), spacing: Spacing.xs)],
            alignment: .leading,
            spacing: Spacing.xs
        ) {
            ForEach(items) { item in
                let active = selected.contains(item.basePath)
                Button {
                    onTap(item)
                } label: {
                    Text(item.name)
                        .font(.system(size: 11, weight: active ? .bold : .medium))
                        .foregroundColor(active ? .white : Color.kanTextSecondary)
                        .lineLimit(1)
                        .padding(.horizontal, Spacing.sm)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            Capsule().fill(active ? Color.kanAccent : Color.kanSurface)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
