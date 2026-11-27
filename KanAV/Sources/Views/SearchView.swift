import SwiftUI

struct SearchView: View {

    @State private var keyword = ""
    @State private var results: [VideoItem] = []
    @State private var isLoading = false
    @State private var message: String?
    @State private var hasSearched = false

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            content
        }
        .background(Color.kanBackground.ignoresSafeArea())
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("番号 / 关键词", text: $keyword)
                .textFieldStyle(.plain)
                .foregroundColor(.white)
                .submitLabel(.search)
                .disableAutocorrection(true)
                .autocapitalization(.none)
                .onSubmit {
                    Task { await performSearch() }
                }

            if !keyword.isEmpty {
                Button {
                    keyword = ""
                    results = []
                    message = nil
                    hasSearched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(.plain)
            }

            Button("搜索") {
                Task { await performSearch() }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color.kanAccent))
        }
        .padding(10)
        .background(Color.kanCard)
        .cornerRadius(10)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder private var content: some View {
        if isLoading {
            VStack {
                Spacer()
                ProgressView().tint(.white)
                Spacer()
            }
        } else if let text = message {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: hasSearched ? "magnifyingglass" : "text.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                Spacer()
            }
        } else if results.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
                Text("搜番号、片名或演员")
                    .font(.system(size: 13))
                    .foregroundColor(.gray)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(results) { item in
                        NavigationLink(destination: PlayerScreen(item: item)) {
                            VideoCard(item: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
            }
        }
    }

    private func performSearch() async {
        let query = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        isLoading = true
        message = nil
        hasSearched = true

        do {
            let html = try await Net.html(path: Site.searchPath(query))
            let parsed = Parser.videos(in: html)
            results = parsed
            if parsed.isEmpty {
                message = "没有找到「\(query)」"
            }
        } catch let error {
            results = []
            message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
