import SwiftUI

/// Whether this Mac has a notch, and what Islet does without one. In setup and in Settings > General.
/// Starts on what macOS reports; "No notch" on a notched Mac uses the no-notch style there too.
struct NotchChoice: View {
    @AppStorage(NotchGeometry.hasNotchKey) private var hasNotch = NotchGeometry.detectedNotch
    @AppStorage(NotchlessStyle.key) private var style = NotchlessStyle.bezel.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("This Mac", selection: $hasNotch) {
                Text("Has a notch").tag(true)
                Text("No notch").tag(false)
            }
            .pickerStyle(.segmented)
            Text(hasNotch
                 ? "The island lives in the notch. With the lid closed on an external display, Dynamic Peninsula uses the no-notch style below."
                 : "There's no notch to live in, so Dynamic Peninsula uses the style below.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("Without a notch", selection: $style) {
                Text("Bubble from the top edge").tag(NotchlessStyle.bezel.rawValue)
                Text("Drop down from the menu bar icon").tag(NotchlessStyle.menuBar.rawValue)
                Text("Off").tag(NotchlessStyle.off.rawValue)
            }
            Text(Self.caption(style)).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func caption(_ style: String) -> String {
        switch NotchlessStyle(rawValue: style) ?? .bezel {
        case .bezel: "Notices bubble out of the top edge under the camera and float just below the menu bar. Hover the middle of the menu bar and swipe down with two fingers to open the panel. Music doesn't stay on screen while it plays."
        case .menuBar: "The island drops down from Dynamic Peninsula's menu bar icon: click it to open the panel, right-click for the menu."
        case .off: "No island. Face unlock and the rest keep working; Settings is in the menu bar icon."
        }
    }
}
