import SwiftUI

/// 封面卡片。封面高度固定，避免不同比例的海报把网格撑得参差不齐。
struct VideoCard: View {

    let item: VideoItem
    var coverHeight: CGFloat = 112

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            coverFrame
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .topLeading)
        }
    }

    private var coverFrame: some View {
        ZStack {
            Color.kanCard
            cover
        }
        .frame(maxWidth: .infinity)
        .frame(height: coverHeight)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .overlay(alignment: .bottomTrailing) {
            durationBadge
        }
    }

    @ViewBuilder private var cover: some View {
        if let url = item.coverURL {
            AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                case .failure:
                    placeholder
                case .empty:
                    ProgressView().tint(.gray)
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(.system(size: 20))
            .foregroundColor(Color.white.opacity(0.25))
    }

    @ViewBuilder private var durationBadge: some View {
        if !item.duration.isEmpty {
            Text(item.duration)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .padding(6)
        }
    }
}

/// 列表行（最近观看）。
struct VideoRow: View {
    let item: VideoItem

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Color.kanCard
                if let url = item.coverURL {
                    AsyncImage(url: url, transaction: Transaction(animation: nil)) { phase in
                        if case .success(let image) = phase {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: 96, height: 54)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
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
    }
}
