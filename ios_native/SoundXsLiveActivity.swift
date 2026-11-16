// File utama widget extension "SoundXsIsland" (Xcode: File > New > Target > Widget Extension,
// centang "Include Live Activity"). Tambahkan juga SoundXsActivityAttributes.swift dan SoundXsIntents.swift.
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

private let appGroup = "group.com.soundxs.app"   // samakan dengan SxCommandBus.appGroup
private let mint = Color(red: 1.0, green: 0.702, blue: 0.690)   // C.mint di Flutter (#FFB3B0)

@main
struct SoundXsIslandBundle: WidgetBundle {
    var body: some Widget { SoundXsLiveActivity() }
}

struct SoundXsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SoundXsActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ArtworkView(file: context.state.artworkFile, size: 52)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                        .foregroundColor(mint)
                        .font(.title3)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title).font(.headline).lineLimit(1)
                        Text(context.state.artist).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressBar(state: context.state)
                        ControlsRow(state: context.state)
                    }
                }
            } compactLeading: {
                ArtworkView(file: context.state.artworkFile, size: 22, circle: true)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .foregroundColor(mint)
            } minimal: {
                Image(systemName: "music.note").foregroundColor(mint)
            }
        }
    }
}

struct LockScreenView: View {
    let state: SoundXsActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(file: state.artworkFile, size: 56)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.title).font(.headline).lineLimit(1)
                Text(state.artist).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                ProgressBar(state: state)
                ControlsRow(state: state)
            }
        }
        .padding(14)
    }
}

/// Tombol prev / play-pause / next. Butuh iOS 17 (LiveActivityIntent). Di iOS 16.2 hanya tampil info.
struct ControlsRow: View {
    let state: SoundXsActivityAttributes.ContentState
    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 30) {
                Button(intent: SxPrevIntent()) {
                    Image(systemName: "backward.fill")
                }
                Button(intent: SxPlayPauseIntent()) {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                Button(intent: SxNextIntent()) {
                    Image(systemName: "forward.fill")
                }
            }
            .buttonStyle(.plain)
            .font(.title3)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
        } else {
            EmptyView()
        }
    }
}

struct ProgressBar: View {
    let state: SoundXsActivityAttributes.ContentState
    var body: some View {
        if state.isPlaying && state.endDate > state.startDate {
            // timer otomatis: jalan sendiri tanpa update dari app
            ProgressView(timerInterval: state.startDate...state.endDate, countsDown: false) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(mint)
        } else {
            ProgressView(value: state.pausedProgress).tint(mint)
        }
    }
}

struct ArtworkView: View {
    let file: String?
    let size: CGFloat
    var circle: Bool = false

    private func load() -> UIImage? {
        guard let f = file,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
        else { return nil }
        return UIImage(contentsOfFile: dir.appendingPathComponent(f).path)
    }

    var body: some View {
        Group {
            if let img = load() {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note").foregroundColor(.white.opacity(0.6))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: circle ? size / 2 : size * 0.22))
    }
}
