import SwiftUI

// MARK: - 设计系统

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
}

enum Radius {
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let pill: CGFloat = 999
}

// MARK: - 骨架屏

/// 加载占位：内容区域铺一层流动高光。
struct ShimmerModifier: ViewModifier {

    @State private var phase: CGFloat = -1.2

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.10),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                    phase = 1.6
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// 卡片骨架
struct CardSkeleton: View {
    var height: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color.kanCard)
                .frame(height: height > 0 ? height : nil)
                .aspectRatio(height > 0 ? nil : 16.0 / 9.0, contentMode: .fit)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kanCard)
                .frame(width: 52, height: 9)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.kanCard)
                .frame(height: 9)
        }
        .shimmer()
    }
}

// MARK: - 区块标题

struct SectionHeader: View {

    let title: String
    var subtitle: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Color.kanTextPrimary)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color.kanTextSecondary)
                }
            }

            Spacer(minLength: 0)

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.kanTextSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - 大卡（今日更新横滑）

struct HeroCard: View {

    let item: VideoItem
    var width: CGFloat = 236

    @ObservedObject private var translator = TitleTranslator.shared

    private var translated: String? { translator.translated(item.title) }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.kanCard
            RemoteImage(url: item.coverURL)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28), Color.black.opacity(0.86)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                if let code = item.code {
                    Text(code)
                        .font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            Capsule().fill(Color.kanAccent.opacity(0.92))
                        )
                }

                Text(translated ?? item.cleanTitle)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !item.duration.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "clock")
                            .font(.system(size: 9, weight: .semibold))
                        Text(item.duration)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white.opacity(0.72))
                }
            }
            .padding(Spacing.md)
        }
        .frame(width: width, height: width * 9.0 / 16.0 + 14)
        .clipShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .onAppear { translator.request(item.title) }
    }
}

// MARK: - 空状态

struct EmptyStateView: View {

    let icon: String
    let title: String
    var message: String?
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.md) {
            ZStack {
                Circle()
                    .fill(Color.kanSurface)
                    .frame(width: 68, height: 68)
                Image(systemName: icon)
                    .font(.system(size: 26, weight: .light))
                    .foregroundColor(Color.kanTextSecondary)
            }

            VStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color.kanTextPrimary)
                if let message = message {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(Color.kanTextSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let actionTitle = actionTitle, let action = action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, Spacing.xl)
                        .padding(.vertical, Spacing.sm)
                        .background(Capsule().fill(Color.kanAccent))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.xxl)
        .frame(maxWidth: .infinity)
    }
}
