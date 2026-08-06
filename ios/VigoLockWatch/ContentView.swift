import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                viewModel.sendToggleLock()
            }) {
                ZStack {
                    Circle()
                        .fill(Color.green.gradient)
                        .frame(width: 120, height: 120)

                    if viewModel.isSpinning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 52, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSpinning)

            Text("Tap to toggle lock")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
