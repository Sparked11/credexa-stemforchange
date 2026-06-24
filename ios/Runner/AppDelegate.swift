import Flutter
import UIKit
import ARKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // ── Trust Lens AR platform view ──────────────────────────────────────────
    // Register unconditionally so the factory exists on simulators too.
    // The Swift view guards ARSession.run() with isSupported at runtime.
    if let arRegistrar = self.registrar(forPlugin: "TrustLensARPlugin") {
      arRegistrar.register(
        TrustLensARViewFactory(messenger: arRegistrar.messenger()),
        withId: "credexa/trust_lens_ar"
      )
    }

    // ── Share channel ────────────────────────────────────────────────────────
    // After the UIScene migration the FlutterViewController / window is no longer
    // available in didFinishLaunching, so use a plugin registrar's messenger
    // instead of `window.rootViewController` (which would now be nil).
    let shareMessenger = self.registrar(forPlugin: "CredexaSharePlugin")!.messenger()
    let shareChannel = FlutterMethodChannel(
      name: "credexa/share",
      binaryMessenger: shareMessenger
    )

    shareChannel.setMethodCallHandler { (call, result) in
      let defaults = UserDefaults(suiteName: "group.com.credexa.shared")
      switch call.method {
      case "getSharedContent":
        guard let type = defaults?.string(forKey: "sharedType") else {
          result(nil)
          return
        }
        var data: [String: Any] = ["type": type]
        switch type {
        case "image":
          data["imageBase64"] = defaults?.string(forKey: "sharedImageBase64") ?? ""
          data["mimeType"]    = defaults?.string(forKey: "sharedMimeType") ?? "image/jpeg"
        default:
          data["text"] = defaults?.string(forKey: "sharedText") ?? ""
        }
        result(data)
      case "clearSharedContent":
        defaults?.removeObject(forKey: "sharedType")
        defaults?.removeObject(forKey: "sharedText")
        defaults?.removeObject(forKey: "sharedImageBase64")
        defaults?.removeObject(forKey: "sharedMimeType")
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Called when the app is opened via credexa:// URL scheme (from Share Extension)
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    return super.application(app, open: url, options: options)
  }
}
