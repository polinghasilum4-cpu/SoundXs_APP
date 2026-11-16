// Tambahkan file ini ke DUA target: Runner  +  SoundXsIsland (widget extension).
// Tombol di Dynamic Island / Lock Screen memanggil intent ini. Intent menulis perintah ke App Group,
// lalu memberi tahu aplikasi lewat notifikasi Darwin. LiveActivityBridge meneruskannya ke Flutter.
import AppIntents
import Foundation

enum SxCommandBus {
    static let appGroup = "group.com.soundxs.app"
    static let key = "sx_pending_cmd"
    static let darwinName: CFString = "com.soundxs.app.command" as CFString

    static func post(_ cmd: String) {
        UserDefaults(suiteName: appGroup)?.set(cmd, forKey: key)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: darwinName),
            nil,
            nil,
            true
        )
    }
}

@available(iOS 17.0, *)
struct SxPlayPauseIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Putar atau jeda"
    init() {}
    func perform() async throws -> some IntentResult {
        SxCommandBus.post("toggle")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SxNextIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lagu berikutnya"
    init() {}
    func perform() async throws -> some IntentResult {
        SxCommandBus.post("next")
        return .result()
    }
}

@available(iOS 17.0, *)
struct SxPrevIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Lagu sebelumnya"
    init() {}
    func perform() async throws -> some IntentResult {
        SxCommandBus.post("prev")
        return .result()
    }
}
