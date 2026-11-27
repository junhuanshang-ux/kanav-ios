import AVFoundation
import MediaPlayer
import SwiftUI
import UIKit

// MARK: - HUD 状态

enum PlayerHUDKind: Equatable {
    case volume(Float)
    case brightness(CGFloat)
    case seek(from: Double, to: Double)
}

// MARK: - 系统亮度 / 音量

enum SystemBrightness {

    static var screen: UIScreen? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .compactMap { $0.keyWindow }
            .first?.screen
    }

    static var current: CGFloat {
        screen?.brightness ?? 0.5
    }

    static func set(_ value: CGFloat) {
        screen?.brightness = max(0.02, min(1.0, value))
    }
}

final class VolumeControl {

    static let shared = VolumeControl()

    let view: MPVolumeView

    private init() {
        view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 2, height: 2))
        view.showsRouteButton = false
        view.alpha = 0.01
    }

    var current: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    func set(_ value: Float) {
        let clamped = max(0, min(1, value))
        DispatchQueue.main.async {
            for subview in self.view.subviews {
                if let slider = subview as? UISlider {
                    slider.value = clamped
                    return
                }
            }
        }
    }
}

/// 把 MPVolumeView 挂进层级，软件调音量才会生效。
struct VolumeHostView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        VolumeControl.shared.view
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

// MARK: - 手势层

struct PlayerGestureLayer: View {

    @ObservedObject var engine: PlayerEngine
    @Binding var hud: PlayerHUDKind?
    let onSingleTap: () -> Void

    private enum DragMode { case none, seek, brightness, volume }

    @State private var dragMode: DragMode = .none
    @State private var baseTime: Double = 0
    @State private var previewTime: Double = 0
    @State private var baseBrightness: CGFloat = 0.5
    @State private var baseVolume: Float = 0.5

    /// 长按快进
    @State private var isBoosting = false
    @State private var savedSpeed: Double = 1.0
    @AppStorage("gesture.mirror") private var mirrorGesture = false
    @AppStorage("gesture.boostSpeed") private var boostSpeed = 2.0
    @State private var isHolding = false
    @State private var holdWork: DispatchWorkItem?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(dragGesture(size: geo.size))
                    .onTapGesture { onSingleTap() }
                    .simultaneousGesture(holdGesture(width: geo.size.width))

                VolumeHostView()
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }
        }
    }

    /// 右半屏「按住 → 2 倍速」。用 simultaneousGesture + 计时，
    /// 不做覆盖层，否则会把右半屏的点击和音量滑动一起吞掉。
    private func holdGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isHolding {
                    isHolding = true
                    let startX = value.startLocation.x
                    let work = DispatchWorkItem {
                        guard isHolding, startX > width / 2 else { return }
                        startBoost()
                    }
                    holdWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
                }
                if abs(value.translation.width) > 15 || abs(value.translation.height) > 15 {
                    holdWork?.cancel()
                }
            }
            .onEnded { _ in
                isHolding = false
                holdWork?.cancel()
                endBoost()
            }
    }

    private func startBoost() {
        guard !isBoosting else { return }
        savedSpeed = engine.speed
        isBoosting = true
        engine.setSpeed(boostSpeed)

        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
    }

    private func endBoost() {
        guard isBoosting else { return }
        isBoosting = false
        engine.setSpeed(savedSpeed)
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if dragMode == .none {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    if horizontal {
                        dragMode = .seek
                        baseTime = engine.currentTime
                        previewTime = engine.currentTime
                    } else {
                        let onLeft = value.startLocation.x < size.width / 2
                        let wantsBrightness = mirrorGesture ? !onLeft : onLeft
                        if wantsBrightness {
                            dragMode = .brightness
                            baseBrightness = SystemBrightness.current
                        } else {
                            dragMode = .volume
                            baseVolume = VolumeControl.shared.current
                        }
                    }
                }

                switch dragMode {
                case .seek:
                    let span = max(size.width, 1)
                    let delta = Double(value.translation.width / span) * 120.0
                    let upper = engine.duration > 0 ? engine.duration : baseTime + 120
                    previewTime = max(0, min(upper, baseTime + delta))
                    hud = .seek(from: baseTime, to: previewTime)

                case .brightness:
                    let delta = -value.translation.height / max(size.height, 1)
                    let next = max(0, min(1, baseBrightness + delta))
                    SystemBrightness.set(next)
                    hud = .brightness(next)

                case .volume:
                    let delta = -value.translation.height / max(size.height, 1)
                    let next = max(0, min(1, baseVolume + Float(delta)))
                    VolumeControl.shared.set(next)
                    hud = .volume(next)

                case .none:
                    break
                }
            }
            .onEnded { _ in
                if dragMode == .seek {
                    engine.seek(to: previewTime)
                }
                dragMode = .none
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    hud = nil
                }
            }
    }
}

// MARK: - HUD 视图

struct PlayerHUDView: View {

    let hud: PlayerHUDKind

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            switch hud {
            case .volume(let value):
                gauge(icon: volumeIcon(value), title: "音量", value: CGFloat(value))
            case .brightness(let value):
                gauge(icon: "sun.max.fill", title: "亮度", value: value)
            case .seek(let from, let to):
                VStack(spacing: 6) {
                    Text(Self.timeText(to))
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    Text("\(Self.timeText(from)) → \(Self.timeText(to))")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 14)
                .background(Color.black.opacity(0.6))
                .cornerRadius(12)

            }
        }
        .allowsHitTesting(false)
    }

    private func gauge(icon: String, title: String, value: CGFloat) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.7))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 110, height: 3)
                Capsule().fill(Color.white).frame(width: 110 * max(0, min(1, value)), height: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.6))
        .cornerRadius(12)
    }

    private func volumeIcon(_ value: Float) -> String {
        if value <= 0.01 { return "speaker.slash.fill" }
        if value < 0.34 { return "speaker.fill" }
        if value < 0.67 { return "speaker.wave.1.fill" }
        return "speaker.wave.3.fill"
    }

    static func timeText(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%02d:%02d", minutes, secs)
    }
}
