import SwiftUI
import WatchConnectivity

class WatchViewModel: NSObject, ObservableObject, WCSessionDelegate {
    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendToggleLock() {
        WCSession.default.sendMessage(
            ["action": "toggleLock"],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }
}
