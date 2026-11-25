import AppKit
import ApplicationServices

/// The website a browser is playing from. The system's now-playing info has no address, but a tab's window title usually
/// ends in the site ("Video title - YouTube — Zen Browser"), and Islet already has Accessibility. Only a tab that is
/// showing in a window can be found, so the answer is remembered for the track and may be nil.
enum BrowserSite {
    /// Reads the browser's window titles and returns the site for the one that holds `mediaTitle`.
    static func find(bundleID: String, mediaTitle: String) -> String? {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        let name = app.localizedName ?? ""
        for window in AX.windows(ofApp: app.processIdentifier) {
            if let title = AX.string(window, kAXTitleAttribute),
               let site = site(windowTitle: title, mediaTitle: mediaTitle, appName: name) { return site }
        }
        return nil
    }

    private static let separators = [" — ", " – ", " - ", " | ", " · ", " • ", " :: "]
    private static let browserNames: Set<String> = [
        "zen", "zen browser", "safari", "google chrome", "chrome", "firefox", "mozilla firefox", "brave", "brave browser",
        "microsoft edge", "edge", "arc", "opera", "vivaldi", "orion", "chromium", "librewolf", "duckduckgo", "waterfox",
    ]

    /// "Title - YouTube — Zen Browser" with the media title "Title" is "YouTube". The words around the media title are
    /// split at dashes and bars, the browser's own name and "Private Browsing" are dropped, and the first one left wins
    /// (those after the title first, then those before it, for a site that puts its name first).
    static func site(windowTitle: String, mediaTitle: String, appName: String) -> String? {
        guard !mediaTitle.isEmpty,
              let r = windowTitle.range(of: mediaTitle, options: [.caseInsensitive, .diacriticInsensitive]) else { return nil }
        let after = String(windowTitle[r.upperBound...]), before = String(windowTitle[..<r.lowerBound])
        for side in [after, before.split(separator: ")", maxSplits: 1, omittingEmptySubsequences: false).last.map(String.init) ?? before] {
            var parts = [side]
            for s in separators { parts = parts.flatMap { $0.components(separatedBy: s) } }
            let name = appName.lowercased()
            let found = parts
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
                .first { p in
                    let l = p.lowercased()
                    return !l.isEmpty && !browserNames.contains(l) && !(name.count > 2 && l.contains(name))
                        && !l.contains("private browsing") && !l.contains("incognito")
                }
            if let found { return found }
        }
        return nil
    }
}
