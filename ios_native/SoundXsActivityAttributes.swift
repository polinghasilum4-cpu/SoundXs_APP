// Tambahkan file ini ke DUA target: Runner  +  SoundXsIsland (widget extension).
import ActivityKit
import Foundation

struct SoundXsActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var title: String
        var artist: String
        var isPlaying: Bool
        var startDate: Date        // = sekarang - posisi lagu  (untuk timer progress otomatis)
        var endDate: Date          // = startDate + durasi
        var pausedProgress: Double // 0...1, dipakai saat pause
        var artworkFile: String?   // nama file di App Group container
    }
    var name: String = "SoundXs"
}
