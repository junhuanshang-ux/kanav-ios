import SwiftUI

/// 演员列表（`/models/`，分页 `/models/2/`）
struct ModelsView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var performers: [Performer] = []
    @State private var page = 0
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var errorText: String?

    private var columns: [GridItem] {
        let count = sizeClass == .regular ? 4 : 3
        return Array(repeating: GridItem(.flexible(), spacing: 12), count: count)
    }

    var body: some View {
        ScrollView {
            if let errorText = errorText, performers.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "person.crop.circle.badge.exclamationmark")
                        .font(.system(size: 30))
                        .foregroundColor(Color.kanTextSecondary)
                    Text(errorText)
                        .font(.system(size: 12))
                        .foregroundColor(Color.kanTextSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("重试") { reload() }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.kanAccent))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(performers) { performer in
                        NavigationLink {
                            PerformerView(performer: performer)
                        } label: {
                            cell(performer)
                        }
                        .buttonStyle(CardButtonStyle())
                        .onAppear {
                            if performer.id == performers.last?.id {
                                loadNextPage()
                            }
                        }
                    }
                }
                .padding(16)

                if isLoading {
                    ProgressView()
                        .tint(Color.kanTextSecondary)
                        .padding(.bottom, 20)
                }
            }
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("演员")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if performers.isEmpty { loadNextPage() }
        }
    }

    private func cell(_ performer: Performer) -> some View {
        VStack(spacing: 7) {
            ZStack {
                Circle().fill(Color.kanCard)
                RemoteImage(url: performer.coverURL)
            }
            .frame(width: 84, height: 84)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.kanSurface, lineWidth: 1))

            Text(performer.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.kanTextPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)

            Text("\(performer.videoCount) 部")
                .font(.system(size: 10))
                .foregroundColor(Color.kanTextSecondary)
        }
    }

    private func reload() {
        performers = []
        page = 0
        hasMore = true
        errorText = nil
        loadNextPage()
    }

    private func loadNextPage() {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let next = page + 1

        Task {
            do {
                let path = next == 1 ? "/models/" : "/models/\(next)/"
                let html = try await Net.html(path: path, allowManualCheck: false)
                let parsed = Parser.models(in: html)

                await MainActor.run {
                    let known = Set(performers.map { $0.id })
                    let added = parsed.filter { !known.contains($0.id) }
                    performers.append(contentsOf: added)
                    page = next
                    hasMore = !added.isEmpty
                    isLoading = false
                    if performers.isEmpty { errorText = "没有解析到演员，稍后重试" }
                }
            } catch let error {
                await MainActor.run {
                    isLoading = false
                    hasMore = false
                    errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
        }
    }
}

/// 单个演员的作品列表，直接复用分类流
struct PerformerView: View {

    let performer: Performer

    var body: some View {
        CategoryFeed(category: performer.asCategory)
            .background(Color.kanBackground.ignoresSafeArea())
            .navigationTitle(performer.name)
            .navigationBarTitleDisplayMode(.inline)
    }
}
