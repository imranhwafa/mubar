import SwiftUI
import CoreBluetooth

/// First-launch welcome. Explains the menu bar nature of the app, points the
/// user at Settings, and previews what to expect from the Bluetooth permission
/// prompt.
struct WelcomeSheet: View {
    @Binding var isPresented: Bool
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome to MUBAR").font(.system(size: 16, weight: .semibold))
                    Text("Live system stats in your menu bar.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            Divider()

            VStack(alignment: .leading, spacing: 14) {
                row(icon: "menubar.dock.rectangle",
                    title: "Lives in the menu bar",
                    body: "MUBAR has no Dock icon. Find it next to the system clock — click to open the popover, or right-click for a quick menu.")

                row(icon: "switch.2",
                    title: "Pick what you see",
                    body: "Open Settings to choose which stats appear in the menu bar (compact) and which appear in the popover (detailed).")

                row(icon: "dot.radiowaves.left.and.right",
                    title: "Bluetooth permission",
                    body: "MUBAR reads battery levels for Bluetooth devices that publish them — including AirPods (via Apple Continuity) and devices with the standard BLE Battery Service. macOS will ask permission the first time. Allow it for battery numbers; deny and the rest still works.")
            }
            .padding(16)

            Divider()
            HStack {
                Spacer()
                Button("Open Settings") {
                    isPresented = false
                    openSettings()
                }
                .keyboardShortcut(",")
                Button("Get Started") { isPresented = false }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 460)
    }

    @ViewBuilder
    private func row(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(body).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }
}
