import SwiftUI
import UIKit

/// 替代 AsyncImage：带 Referer 拉图，失败/加载中走占位。
struct RemoteImage: View {

    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var isLoading = false

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ZStack {
                    Color.kanCard
                    if isLoading {
                        ProgressView().tint(.gray).scaleEffect(0.8)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.25))
                    }
                }
            }
        }
        .task(id: url) {
            guard let url = url else {
                image = nil
                return
            }
            isLoading = true
            let loaded = await ImageLoader.shared.image(for: url)
            await MainActor.run {
                self.image = loaded
                self.isLoading = false
            }
        }
    }
}

/// 封面卡片：封面固定高度 + 番号 + 中文标题（自动翻译）。
struct VideoCard: View {

    let item: VideoItem
    var coverHeight: CGFloat = 112

    @ObservedObject private var translator = TitleTranslator.shared

    private var displayTitle: String {
        translator.translated(item.title) ?? item.cleanTitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverFrame

            VStack(alignment: .leading, spacing: 2) {
                if let code = item.code {
                    Text(code)
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundColor(Color.kanAccent)
                        .lineLimit(1)
                }
                Text(displayTitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 30, maxHeight: 30, alignment: .topLeading)
            }
        }
        .onAppear {
            translator.request(item.title)
        }
    }

    private var coverFrame: some View {
        ZStack {
            Color.kanCard
            RemoteImage(url: item.coverURL)
        }
        .frame(maxWidth: .infinity)
        .frame(height: coverHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            durationBadge
        }
    }

    @ViewBuilder private var durationBadge: some View {
        if !item.duration.isEmpty {
            Text(item.duration)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.72))
                .cornerRadius(4)
                .padding(6)
        }
    }
}

/// 列表行（最近观看）。
struct VideoRow: View {
    let item: VideoItem

    @ObservedObject private var translator = TitleTranslator.shared

    private var displayTitle: String {
        translator.translated(item.title) ?? item.cleanTitle
    }

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.kanCard
                RemoteImage(url: item.coverURL)
            }
            .frame(width: 96, height: 54)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                if let code = item.code {
                    Text(code)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(Color.kanAccent)
                }
                Text(displayTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onAppear {
            translator.request(item.title)
        }
    }
}
