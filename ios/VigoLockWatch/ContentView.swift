import SwiftUI

private enum VigoWatchTheme {
    static let accentGreen = Color(red: 0, green: 0.902, blue: 0.463)
    static let disabledGray = Color(red: 0.23, green: 0.24, blue: 0.25)
    static let statusMuted = Color(red: 0.62, green: 0.64, blue: 0.67)
}

struct ContentView: View {
    @StateObject private var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 14) {
            if !viewModel.isPhoneReachable {
                ReachabilityStatusBadge()
            }

            Button(action: viewModel.sendToggleLock) {
                ZStack {
                    Circle()
                        .fill(unlockButtonFill)
                        .frame(width: 120, height: 120)
                        .shadow(
                            color: viewModel.isPhoneReachable
                                ? VigoWatchTheme.accentGreen.opacity(0.35)
                                : .clear,
                            radius: 10,
                            y: 4
                        )

                    if viewModel.isSpinning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white.opacity(viewModel.isPhoneReachable ? 1 : 0.55))
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canUnlock)
            .animation(.easeInOut(duration: 0.2), value: viewModel.isPhoneReachable)

            Text(viewModel.isPhoneReachable ? "Tap to toggle lock" : "Open Vigo Vault on iPhone")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(viewModel.isPhoneReachable ? .secondary : VigoWatchTheme.statusMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var unlockButtonFill: AnyShapeStyle {
        viewModel.isPhoneReachable
            ? AnyShapeStyle(VigoWatchTheme.accentGreen.gradient)
            : AnyShapeStyle(VigoWatchTheme.disabledGray.gradient)
    }
}

private struct ReachabilityStatusBadge: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone.slash")
                .font(.caption2.weight(.bold))

            Text("iPhone Not in Range")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(VigoWatchTheme.statusMuted)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("iPhone not in range")
    }
}

#Preview("Connected") {
    ContentView()
}
