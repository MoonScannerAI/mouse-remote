import SwiftUI

@MainActor
struct StatusBarView: View {
    @EnvironmentObject private var ble: BLEManager
    @Binding var showSettings: Bool

    private var dotColor: Color {
        switch ble.state {
        case .connected: return .green
        case .pairingNeeded: return .orange
        case .scanning, .connecting: return .yellow
        case .off: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(ble.state.title)
                    .font(.headline)
                    .foregroundStyle(Color.white)
                Text(ble.detail)
                    .font(.caption)
                    .foregroundStyle(Color.gray)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.white)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Settings")
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .contain)
    }
}
