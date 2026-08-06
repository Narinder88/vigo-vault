import SwiftUI
import WatchConnectivity

class WatchViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var isSpinning = false

    override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    func sendToggleLock() {
        guard WCSession.default.isReachable else {
            print("Watch: iPhone is unreachable")
            return
        }

        isSpinning = true
        WCSession.default.sendMessage(
            ["action": "toggleLock"],
            replyHandler: { reply in
                DispatchQueue.main.async {
                    self.isSpinning = false
                    if let status = reply["status"] as? String {
                        print("Watch unlock reply: \(status)")
                    }
                }
            },
            errorHandler: { error in
                print("Watch sendMessage error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.isSpinning = false
                }
            }
        )
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
    }
}
