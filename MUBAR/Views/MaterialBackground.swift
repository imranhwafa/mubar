import SwiftUI
import AppKit

/// Renders the popover background using the user's chosen material.
/// For `.solid` we render an opaque NSColor so the underlying NSPopover
/// vibrancy is masked.
struct MaterialBackground: View {
    let mode: MaterialMode

    var body: some View {
        Group {
            if mode == .solid {
                Color(nsColor: .windowBackgroundColor)
            } else {
                VisualEffectView(material: mode.nsMaterial, blendingMode: mode.blendingMode)
            }
        }
        .ignoresSafeArea()
    }
}

private struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
