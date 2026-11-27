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
                        ProgressView().tint(Color.kanTextSecondary).scaleEffect(0.8)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 20))
                            .foregroundColor(Color.white.opacity(0.18))
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

/// 封面卡片：固定封面高 + 番号 + 标题（译文浅青色）。
struct VideoCard: View {

    let item: VideoItem
    var coverHeight: CGFloat = 116

    @ObservedObject private var translator = TitleTranslator.shared
    @State private var pressed = false

    private var translated: String? { translator.translated(item.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            coverFrame

            VStack(alignment: .leading, spacing: 3) {
                if let code = item.code {
                    Text(code)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.kanAccent)
                        .lineLimit(1)
                }

                Text(translated ?? item.cleanTitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(translated == nil ? .white : Color.kanTranslated)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .topLeading)
            }
        }
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.easeOut(duration: 0.12), value: pressed)
        .onLongPressGesture(minimumDuration: .infinity, pressing: { pressing in
            pressed = pressing
        }, perform: {})
        .onAppear {
            translator.request(item.title)
        }
    }

    private var coverFrame: some View {
        ZStack(alignment: .bottom) {
            Color.kanCard
            RemoteImage(url: item.coverURL)
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 44)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: coverHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)
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
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Color.black.opacity(0.62)))
                .padding(7)
        }
    }
}

/// 列表行（最近观看）。
struct VideoRow: View {
    let item: VideoItem

    @ObservedObject private var translator = TitleTranslator.shared

    private var translated: String? { translator.translated(item.title) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Color.kanCard
                RemoteImage(url: item.coverURL)
            }
            .frame(width: 104, height: 58)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
            )

            VStack(alignment: .leading, spacing: 4) {
                if let code = item.code {
                    Text(code)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Color.kanAccent)
                }
                Text(translated ?? item.cleanTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(translated == nil ? .white : Color.kanTranslated)
                    .lineLimit(2)
                Text(item.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color.kanTextSecondary)
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
