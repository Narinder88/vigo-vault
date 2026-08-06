import SwiftUI

struct ContentView: View {
    @StateObject var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 16) {
            Button(action: {
                viewModel.sendToggleLock()
            }) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 120, height: 120)
                    .background(
                        Circle()
                            .fill(Color.green.gradient)
                    )
            }
            .buttonStyle(.plain)

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
