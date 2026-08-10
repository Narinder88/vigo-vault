import SwiftUI
import WatchConnectivity

final class WatchViewModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published private(set) var isSpinning = false
    @Published private(set) var isPhoneReachable = false

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }

        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    var canUnlock: Bool {
        isPhoneReachable && !isSpinning
    }

    func sendToggleLock() {
        guard canUnlock else { return }

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
        DispatchQueue.main.async {
            self.refreshReachability(from: session)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.refreshReachability(from: session)
        }
    }

    private func refreshReachability(from session: WCSession) {
        isPhoneReachable = session.activationState == .activated && session.isReachable
    }
}
