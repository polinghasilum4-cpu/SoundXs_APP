// Ganti isi ios/Runner/AppDelegate.swift dengan ini
// (kalau template Flutter-mu memakai SceneDelegate, panggil blok "island" di tempat yang setara).
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    private var island: Any?   // menyimpan LiveActivityBridge (iOS 16.2+)

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        GeneratedPluginRegistrant.register(with: self)

        if let controller = window?.rootViewController as? FlutterViewController,
           #available(iOS 16.2, *) {
            island = LiveActivityBridge(messenger: controller.binaryMessenger)
        }
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
