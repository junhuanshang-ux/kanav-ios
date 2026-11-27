import SwiftUI
import UIKit

/// 把 SwiftUI 视图渲染成图片（iOS 15 没有 ImageRenderer，走 UIHostingController 截图）
enum ImageSnapshot {

    @MainActor
    static func render<V: View>(_ view: V, size: CGSize, scale: CGFloat = 2.0) -> UIImage? {
        let controller = UIHostingController(rootView: view)
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = controller
        window.isHidden = false

        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()

        let renderer = UIGraphicsImageRenderer(size: size, format: {
            let format = UIGraphicsImageRendererFormat()
            format.scale = scale
            format.opaque = true
            return format
        }())

        let image = renderer.image { context in
            controller.view.layer.render(in: context.cgContext)
        }

        window.isHidden = true
        return image
    }
}

/// 分享卡片：封面 + 番号 + 标题，用于导出成图片
struct ShareCard: View {

    let item: VideoItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
            RemoteImage(url: item.coverURL)

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.35), Color.black.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                if let code = item.code {
                    Text(code)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(red: 1.0, green: 0.23, blue: 0.36)))
                }

                Text(item.cleanTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 6) {
                    Text(item.duration)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.66))
                    Spacer(minLength: 0)
                    Text("博客 · jable.tv")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            .padding(18)
        }
        .frame(width: 480, height: 270)
    }
}
