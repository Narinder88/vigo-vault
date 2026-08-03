import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let pairedLocksChannelName = "com.singh.fitnessssnacklock/paired_locks"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let controller = window?.rootViewController as? FlutterViewController {
      setupPairedLocksChannel(controller: controller)
    }

    return result
  }

  private func setupPairedLocksChannel(controller: FlutterViewController) {
    let storage = PairedLockSecureStorage()
    let channel = FlutterMethodChannel(
      name: pairedLocksChannelName,
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isPaired":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        result(storage.isPaired(deviceId: deviceId))

      case "pair":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        storage.pair(deviceId: deviceId)
        result(nil)

      case "unpair":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        storage.unpair(deviceId: deviceId)
        result(nil)

      case "getPairedIds":
        result(Array(storage.getPairedIds()))

      case "getSecretKey":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        result(storage.getSecretKey(deviceId: deviceId))

      case "saveSecretKey":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              let secretKey = args["secretKey"] as? String,
              !deviceId.isEmpty,
              !secretKey.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId and secretKey are required", details: nil))
          return
        }
        storage.saveSecretKey(deviceId: deviceId, secretKey: secretKey)
        result(nil)

      case "removeSecretKey":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        storage.removeSecretKey(deviceId: deviceId)
        result(nil)

      case "hasSecretKey":
        guard let args = call.arguments as? [String: Any],
              let deviceId = args["deviceId"] as? String,
              !deviceId.isEmpty else {
          result(FlutterError(code: "invalid_argument", message: "deviceId is required", details: nil))
          return
        }
        result(storage.hasSecretKey(deviceId: deviceId))

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
