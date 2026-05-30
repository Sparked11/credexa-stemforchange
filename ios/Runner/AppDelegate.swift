import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let shareChannel = FlutterMethodChannel(
      name: "credexa/share",
      binaryMessenger: controller.binaryMessenger
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
