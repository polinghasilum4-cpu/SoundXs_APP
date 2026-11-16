// Tambahkan ke target Runner saja.
import ActivityKit
import Flutter
import UIKit

@available(iOS 16.2, *)
final class LiveActivityBridge {
    /// HARUS sama dengan App Group yang dibuat di Xcode (Runner + SoundXsIsland).
    static let appGroup = SxCommandBus.appGroup

    /// Singleton supaya callback notifikasi Darwin (fungsi C, tanpa capture) bisa menemukan instance.
    static var shared: LiveActivityBridge?

    private let channel: FlutterMethodChannel
    private var current: Activity<SoundXsActivityAttributes>?
    private var lastArtSource = ""
    private var artSeq = 0
    private var lastArtFile: String?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "soundxs/live_activity", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self = self else { result(false); return }
            switch call.method {
            case "update":
                guard let args = call.arguments as? [String: Any] else { result(false); return }
                Task { await self.upsert(args); result(true) }
            case "end":
                Task { await self.end(); result(true) }
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        LiveActivityBridge.shared = self
        // Tombol Live Activity -> SxCommandBus.post -> notifikasi ini -> kirim ke Dart.
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                DispatchQueue.main.async { LiveActivityBridge.shared?.flushCommand() }
            },
            SxCommandBus.darwinName,
            nil,
            .deliverImmediately
        )
    }

    private func flushCommand() {
        let d = UserDefaults(suiteName: SxCommandBus.appGroup)
        guard let cmd = d?.string(forKey: SxCommandBus.key) else { return }
        d?.removeObject(forKey: SxCommandBus.key)
        channel.invokeMethod("command", arguments: ["c": cmd])
    }

    private func num(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    private func upsert(_ a: [String: Any]) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let posMs = num(a["positionMs"])
        let durMs = num(a["durationMs"])
        let now = Date()
        let start = now.addingTimeInterval(-posMs / 1000.0)
        let end = start.addingTimeInterval(max(durMs / 1000.0, 1))
        let progress = durMs > 0 ? min(max(posMs / durMs, 0), 1) : 0

        var artFile = lastArtFile
        if let path = a["artworkPath"] as? String, !path.isEmpty, path != lastArtSource {
            lastArtSource = path
            artFile = copyArtwork(from: path)
        }

        let state = SoundXsActivityAttributes.ContentState(
            title: a["title"] as? String ?? "",
            artist: a["artist"] as? String ?? "",
            isPlaying: a["playing"] as? Bool ?? false,
            startDate: start,
            endDate: end,
            pausedProgress: progress,
            artworkFile: artFile
        )
        let content = ActivityContent(state: state, staleDate: nil)

        if current == nil {
            current = Activity<SoundXsActivityAttributes>.activities.first
        }
        if let act = current, act.activityState == .active {
            await act.update(content)
        } else {
            // Activity.request hanya boleh saat app di foreground atau sedang memutar audio.
            do {
                current = try Activity.request(
                    attributes: SoundXsActivityAttributes(),
                    content: content,
                    pushType: nil
                )
            } catch {
                NSLog("SoundXs LiveActivity gagal: \(error)")
            }
        }
    }

    private func end() async {
        for act in Activity<SoundXsActivityAttributes>.activities {
            await act.end(nil, dismissalPolicy: .immediate)
        }
        current = nil
    }

    /// Salin sampul (diperkecil) ke App Group supaya bisa dibaca widget extension.
    private func copyArtwork(from path: String) -> String? {
        guard let img = UIImage(contentsOfFile: path),
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroup)
        else { return lastArtFile }

        let size = CGSize(width: 120, height: 120)
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = small.jpegData(compressionQuality: 0.8) else { return lastArtFile }

        artSeq += 1
        let name = "art_\(artSeq).jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name))
            if let old = lastArtFile { try? FileManager.default.removeItem(at: dir.appendingPathComponent(old)) }
            lastArtFile = name
            return name
        } catch {
            return lastArtFile
        }
    }
}
