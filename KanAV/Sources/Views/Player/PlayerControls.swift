import AVFoundation
import SwiftUI

/// 自绘播放控件。整层透明，只靠按钮自带的黑底和文字阴影保证可读性，
/// 不遮挡画面。
struct PlayerControls: View {

    @ObservedObject var engine: PlayerEngine

    let title: String
    let isFullscreen: Bool

    let onBack: () -> Void
    let onToggleFullscreen: () -> Void

    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0

    private let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Spacer(minLength: 0)
            centerBar
            Spacer(minLength: 0)
            bottomBar
        }
    }

    // MARK: 顶部

    private var topBar: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: isFullscreen ? "chevron.down" : "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.black.opacity(0.38)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)

            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .shadow(color: .black.opacity(0.75), radius: 3, x: 0, y: 1)

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
    }

    // MARK: 中部

    private var centerBar: some View {
        HStack(spacing: 44) {
            Button {
                engine.skip(-15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                engine.togglePlay()
            } label: {
                Image(systemName: engine.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 38, weight: .regular))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .shadow(color: .black.opacity(0.7), radius: 5)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                engine.skip(15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 25, weight: .regular))
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.7), radius: 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 底部

    private var bottomBar: some View {
        VStack(spacing: 4) {
            progressBar

            HStack(spacing: 10) {
                Text(PlayerHUDView.timeText(isScrubbing ? scrubTime : engine.currentTime))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(color: .black.opacity(0.75), radius: 2)

                Text("/")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.4))
                    .shadow(color: .black.opacity(0.75), radius: 2)

                Text(PlayerHUDView.timeText(engine.duration))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundColor(.white.opacity(0.6))
                    .shadow(color: .black.opacity(0.75), radius: 2)

                Spacer(minLength: 2)

                speedMenu
                gravityButton
                loopButton
                trackMenu
                iconButton(
                    isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    action: onToggleFullscreen
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // 底部菜单不做全透明，加一层半透明深色底，亮画面下时间和按钮才看得清
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.45))
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let displayTime = isScrubbing ? scrubTime : engine.currentTime
            let ratio = engine.duration > 0 ? min(max(displayTime / engine.duration, 0), 1) : 0
            let bufferRatio = engine.duration > 0 ? min(max(engine.bufferedTime / engine.duration, 0), 1) : 0

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: width, height: 3)

                Capsule()
                    .fill(Color.white.opacity(0.42))
                    .frame(width: width * bufferRatio, height: 3)

                Capsule()
                    .fill(Color.kanAccent)
                    .frame(width: width * ratio, height: 3)

                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: max(0, min(width * ratio - 5, width - 10)))
            }
            .frame(height: 22)
            .background(Color.black.opacity(0.001))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard engine.duration > 0 else { return }
                        isScrubbing = true
                        let p = min(max(value.location.x / width, 0), 1)
                        scrubTime = p * engine.duration
                    }
                    .onEnded { value in
                        defer { isScrubbing = false }
                        guard engine.duration > 0 else { return }
                        let p = min(max(value.location.x / width, 0), 1)
                        engine.seek(to: p * engine.duration)
                    }
            )
        }
        .frame(height: 22)
        .shadow(color: .black.opacity(0.4), radius: 2)
    }

    // MARK: 控件

    private var speedMenu: some View {
        Menu {
            ForEach(speeds, id: \.self) { value in
                Button {
                    engine.setSpeed(value)
                } label: {
                    if abs(engine.speed - value) < 0.01 {
                        Label(speedText(value), systemImage: "checkmark")
                    } else {
                        Text(speedText(value))
                    }
                }
            }
        } label: {
            Text(speedText(engine.speed))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white)
                .shadow(color: .black.opacity(0.7), radius: 2)
                .frame(minWidth: 32, minHeight: 26)
        }
    }

    private var gravityButton: some View {
        Button {
            engine.cycleGravity()
        } label: {
            Text(engine.gravityTitle())
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 2)
                .frame(minWidth: 32, minHeight: 26)
        }
        .buttonStyle(.plain)
    }

    private var loopButton: some View {
        iconButton(engine.isLooping ? "repeat.1" : "repeat", active: engine.isLooping) {
            engine.toggleLoop()
        }
    }

    private var trackMenu: some View {
        Menu {
            if !engine.audioOptions.isEmpty {
                Section("音轨") {
                    ForEach(engine.audioOptions) { option in
                        Button {
                            engine.selectAudio(option)
                        } label: {
                            if engine.selectedAudioID == option.id {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                }
            }

            if !engine.subtitleOptions.isEmpty {
                Section("内嵌字幕") {
                    Button {
                        engine.selectSubtitle(nil)
                    } label: {
                        Text("关闭")
                    }
                    ForEach(engine.subtitleOptions) { option in
                        Button {
                            engine.selectSubtitle(option)
                        } label: {
                            if engine.selectedSubtitleID == option.id {
                                Label(option.title, systemImage: "checkmark")
                            } else {
                                Text(option.title)
                            }
                        }
                    }
                }
            }

            if engine.audioOptions.isEmpty && engine.subtitleOptions.isEmpty {
                Text("该片源没有可选音轨 / 字幕")
            }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 2)
                .frame(width: 28, height: 26)
        }
    }

    private func iconButton(_ systemName: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(active ? Color.kanAccent : Color.white.opacity(0.95))
                .shadow(color: .black.opacity(0.7), radius: 2)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func speedText(_ value: Double) -> String {
        if abs(value - 1.0) < 0.01 { return "1×" }
        return String(format: "%g×", value)
    }
}
