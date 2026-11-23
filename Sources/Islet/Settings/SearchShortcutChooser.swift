import AppKit
import SwiftUI

/// Which shortcut opens search (DESIGN.md "Search", "Opening"): ⌘Space stays Spotlight's and Islet takes another
/// (the default, ⌥Space), or ⌘Space for Islet (Spotlight moves). Below it, what's true right now, ticking itself off once Spotlight has moved.
/// Used by Settings > Search and by setup. Put it in a Form section.
struct SearchShortcutChooser: View {
    @Binding var shortcut: String
    @State private var spotlight = SearchShortcut.spotlightShortcut()
    @State private var conflict = SearchShortcut.spotlightConflict

    private static let others: [SearchShortcutChoice] = [.optionSpace, .controlSpace, .commandShiftSpace]

    var body: some View {
        Group {
            Picker(selection: mode) {
                // Spotlight keeps ⌘Space by default (owner, 2026-11-23); taking it over is opt-in.
                SettingsLabel("Keep ⌘Space for Spotlight", "Nothing changes in System Settings. Islet uses another shortcut, ⌥Space unless you pick one.")
                    .tag(false)
                SettingsLabel("Use ⌘Space for Islet", "Islet's search takes Spotlight's place. Spotlight, and Siri in it, move to another shortcut.")
                    .tag(true)
            } label: { EmptyView() }
            .pickerStyle(.radioGroup)
            if !mode.wrappedValue {
                Picker("Islet's shortcut", selection: $shortcut) {
                    ForEach(Self.others) { Text($0.title).tag($0.rawValue) }
                }
            }
            status
        }
        .onChange(of: shortcut) { SearchShortcut.shared.apply(); check() }
        .onAppear(perform: check)
        // Spotlight's shortcut is changed in System Settings: notice it while this is showing.
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in check() }
    }

    private func check() {
        spotlight = SearchShortcut.spotlightShortcut()
        conflict = SearchShortcut.spotlightConflict
    }

    /// True: ⌘Space opens Islet. False: Spotlight keeps it.
    private var mode: Binding<Bool> {
        Binding(get: { shortcut == SearchShortcutChoice.commandSpace.rawValue }, set: { islet in
            if islet {
                shortcut = SearchShortcutChoice.commandSpace.rawValue
            } else if shortcut == SearchShortcutChoice.commandSpace.rawValue {
                // Not where Spotlight is now (it may have been moved to ⌥Space already).
                shortcut = (Self.others.first { !Self.spotlightUses($0, spotlight) } ?? .optionSpace).rawValue
            }
        })
    }

    static func spotlightUses(_ c: SearchShortcutChoice, _ s: SearchShortcut.SpotlightShortcut) -> Bool {
        let relevant: UInt64 = CGEventFlags.maskCommand.rawValue | CGEventFlags.maskAlternate.rawValue
            | CGEventFlags.maskControl.rawValue | CGEventFlags.maskShift.rawValue
        return s.enabled && s.keyCode == 49 && (s.flags & relevant) == c.eventFlags
    }

    /// Where Spotlight is now: "⌥Space", "⌘Space", another shortcut, or nil when its shortcut is off.
    private var spotlightKey: String? {
        guard spotlight.enabled else { return nil }
        return SearchShortcutChoice.allCases.first { $0 != .off && Self.spotlightUses($0, spotlight) }?.title ?? "its own shortcut"
    }

    @ViewBuilder private var status: some View {
        let mine = SearchShortcutChoice(rawValue: shortcut)?.title ?? ""
        if conflict {
            LabeledContent {
                Button("Open Keyboard Shortcuts…") { NSWorkspace.shared.open(SearchShortcut.keyboardShortcutsURL) }
            } label: {
                SettingsLabel("Move Spotlight off \(mine)",
                              "In Keyboard Shortcuts > Spotlight, double-click “Show Spotlight search” and press another shortcut, like \(mine == "⌥Space" ? "⌃Space" : "⌥Space").")
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Waiting for Spotlight to let go of \(mine). This updates by itself.").foregroundStyle(.secondary)
            }
        } else {
            let place = spotlightKey.map { "Spotlight and Siri are on \($0)." } ?? "Spotlight's shortcut is off."
            Label("\(mine) opens Islet. " + place, systemImage: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor).foregroundStyle(.secondary)
        }
    }
}
