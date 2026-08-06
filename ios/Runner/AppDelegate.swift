import Flutter
import UIKit
import WatchConnectivity

@main
@objc class AppDelegate: FlutterAppDelegate, WCSessionDelegate {
  private let pairedLocksChannelName = "com.singh.fitnessssnacklock/paired_locks"
  private var watchChannel: FlutterMethodChannel?

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
      setupWatchChannel(controller: controller)
    }

    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }

    return result
  }

  private func setupWatchChannel(controller: FlutterViewController) {
    watchChannel = FlutterMethodChannel(
      name: "com.singh.vigovault/watch",
      binaryMessenger: controller.binaryMessenger
    )

    watchChannel?.setMethodCallHandler { call, result in
      switch call.method {
      case "sendToWatch":
        let message = call.arguments as? [String: Any] ?? [:]
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
  }

  func sessionDidBecomeInactive(_ session: WCSession) {
  }

  func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    DispatchQueue.main.async {
      self.watchChannel?.invokeMethod("fromWatch", arguments: message)
    }
  }

  func session(
    _ session: WCSession,
    didReceiveMessage message: [String: Any],
    replyHandler: @escaping ([String: Any]) -> Void
  ) {
    DispatchQueue.main.async {
      guard let channel = self.watchChannel else {
        replyHandler(["status": "failed", "error": "channel_unavailable"])
        return
      }

      channel.invokeMethod("fromWatch", arguments: message) { result in
        if let response = result as? [String: Any] {
          replyHandler(response)
        } else if let error = result as? FlutterError {
          replyHandler([
            "status": "failed",
            "error": error.message ?? "unknown",
          ])
        } else {
          replyHandler(["status": "failed"])
        }
      }
    }
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
