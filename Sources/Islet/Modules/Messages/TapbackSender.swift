import AppKit
import ApplicationServices

/// A tapback (DESIGN.md "Messages", RESEARCH.md Q57-Q60).
enum Tapback: Int, CaseIterable, Identifiable {
    case love = 2000, like, dislike, laugh, emphasize, question

    var id: Int { rawValue }
    var emoji: String { ["❤️", "👍", "👎", "😂", "‼️", "❓"][rawValue - 2000] }
    var name: String { ["Heart", "Thumbs Up", "Thumbs Down", "Ha Ha", "Exclamation Mark", "Question Mark"][rawValue - 2000] }
    /// The identifier of its button in the row at the top of a message's menu in Messages.
    var axIdentifier: String { ["heart", "thumbs_up", "thumbs_down", "ha_ha!", "exclamation_mark", "question_mark"][rawValue - 2000] }
}

/// Sends tapbacks by pressing Messages' own buttons (Accessibility): Messages has no Apple Events command for them.
/// Messages comes forward for a moment with the conversation open, the message's menu opens, the tapback is pressed,
/// and the app that was in front comes back. Islet itself never goes on the network.
@MainActor
enum TapbackSender {
    static let bundleID = "com.apple.MobileSMS"

    /// Nil when it was sent (or, with `tapback` nil, the message's menu is open in Messages for any emoji); else why not.
    /// `occurrence` counts newer messages with the same text from the same side, to pick the right one of several.
    static func react(_ tapback: Tapback?, to message: MessagesStore.Message, in chat: MessagesStore.Conversation,
                      occurrence: Int) async -> String? {
        guard AXIsProcessTrusted() else { return "Allow Dynamic Peninsula in Accessibility to react" }
        let previous = NSWorkspace.shared.frontmostApplication
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let wasHidden = running == nil || running!.isHidden || !hasWindow(running!)

        // Show the conversation in Messages: a one-to-one chat by its address; a group has to be open there already.
        let handle = chat.guid.components(separatedBy: ";").last ?? ""
        if !chat.isGroup, !handle.isEmpty,
           let url = URL(string: "sms:\(handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle)") {
            NSWorkspace.shared.open(url)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }

        func restore() {
            if let previous, previous.bundleIdentifier != bundleID { previous.activate() }
            if wasHidden { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.hide() }
            NSApp.windows.first { $0 is NotchPanel }?.makeKey()
        }

        // Find the bubble (Messages may still be opening): its description is "Your iMessage, <text>, <time>" for
        // yours and "<Name>, <text>, <time>" for theirs.
        var bubble: AXUIElement?
        for _ in 0..<30 {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                if !hasWindow(app) { openMainWindow(app) }
                bubble = find(message, in: app, occurrence: occurrence)
                if bubble != nil { break }
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let bubble, let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            restore()
            return chat.isGroup ? "Open this group in Messages to react" : "Messages couldn't find that message"
        }
        if !app.isActive { app.activate(); try? await Task.sleep(for: .milliseconds(150)) }
        AXUIElementPerformAction(bubble, "AXScrollToVisible" as CFString)
        guard AXUIElementPerformAction(bubble, kAXShowMenuAction as CFString) == .success else {
            restore()
            return "Messages couldn't react"
        }
        guard let tapback else { return nil } // any emoji: the menu stays open in Messages to pick from

        var button: AXUIElement?
        for _ in 0..<15 {
            button = menuItem(tapback.axIdentifier, in: app)
            if button != nil { break }
            try? await Task.sleep(for: .milliseconds(70))
        }
        guard let button, AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
            pressEscape()
            restore()
            return "Messages couldn't react"
        }
        try? await Task.sleep(for: .milliseconds(150))
        restore()
        return nil
    }

    /// Shows a one-to-one conversation in Messages for a moment so Messages marks it read (its red badge clears):
    /// replying through Apple Events sends but never marks read. Groups can't be opened by address, so they're left.
    static func markRead(_ chat: MessagesStore.Conversation) async {
        let handle = chat.guid.components(separatedBy: ";").last ?? ""
        guard !chat.isGroup, !handle.isEmpty,
              let url = URL(string: "sms:\(handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle)") else { return }
        let previous = NSWorkspace.shared.frontmostApplication
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
        let wasHidden = running == nil || running!.isHidden || !hasWindow(running!)
        NSWorkspace.shared.open(url)
        // Give Messages time to come forward with the conversation open and mark it read.
        try? await Task.sleep(for: .milliseconds(900))
        if let previous, previous.bundleIdentifier != bundleID { previous.activate() }
        if wasHidden { NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.hide() }
        NSApp.windows.first { $0 is NotchPanel }?.makeKey()
    }

    // MARK: Accessibility

    private static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }

    private static func element(_ app: NSRunningApplication) -> AXUIElement {
        let ax = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(ax, 1)
        return ax
    }

    private static func windows(_ app: NSRunningApplication) -> [AXUIElement] {
        attr(element(app), kAXWindowsAttribute) as? [AXUIElement] ?? []
    }

    private static func hasWindow(_ app: NSRunningApplication) -> Bool {
        windows(app).contains { (attr($0, kAXSubroleAttribute) as? String) == "AXStandardWindow" }
    }

    /// Window > Messages, for when Messages runs with its window closed.
    private static func openMainWindow(_ app: NSRunningApplication) {
        guard let barValue = attr(element(app), kAXMenuBarAttribute) else { return }
        let bar = barValue as! AXUIElement
        guard let window = children(bar).first(where: { (attr($0, kAXTitleAttribute) as? String) == "Window" }),
              let menu = children(window).first,
              let item = children(menu).last(where: { (attr($0, kAXTitleAttribute) as? String) == "Messages" }) else { return }
        AXUIElementPerformAction(item, kAXPressAction as CFString)
    }

    private static func normal(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The message's bubble: the one with its own actions (Reply…, Copy…), counting `occurrence` back from the newest.
    private static func find(_ message: MessagesStore.Message, in app: NSRunningApplication, occurrence: Int) -> AXUIElement? {
        let text = normal(message.text)
        guard !text.isEmpty else { return nil }
        var found: [AXUIElement] = []
        func walk(_ e: AXUIElement, _ depth: Int) {
            if let d = attr(e, kAXDescriptionAttribute) as? String, d.count > text.count {
                let desc = normal(d)
                if desc.hasPrefix("Your ") == message.mine, desc.contains(", \(text),") || desc.hasSuffix(", \(text)") {
                    var names: CFArray?
                    AXUIElementCopyActionNames(e, &names)
                    if ((names as? [String]) ?? []).contains(where: { $0.contains("Reply") }) { found.append(e) }
                }
            }
            guard depth < 40 else { return }
            for k in children(e) { walk(k, depth + 1) }
        }
        for w in windows(app) where (attr(w, kAXSubroleAttribute) as? String) == "AXStandardWindow" { walk(w, 0) }
        return found.count > occurrence ? found[found.count - 1 - occurrence] : nil
    }

    private static func menuItem(_ identifier: String, in app: NSRunningApplication) -> AXUIElement? {
        func walk(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            let role = attr(e, kAXRoleAttribute) as? String
            // On screen only (a closed menu could linger in the tree with no size).
            if role == "AXMenuItem", (attr(e, kAXIdentifierAttribute) as? String) == identifier, onScreen(e) { return e }
            guard depth < 40, role != "AXMenuBar" else { return nil }
            for k in children(e) { if let hit = walk(k, depth + 1) { return hit } }
            return nil
        }
        return windows(app).lazy.compactMap { walk($0, 0) }.first
    }

    private static func onScreen(_ e: AXUIElement) -> Bool {
        guard let v = attr(e, kAXSizeAttribute) else { return true }
        var size = CGSize.zero
        AXValueGetValue(v as! AXValue, .cgSize, &size)
        return size.width > 0 && size.height > 0
    }

    private static func pressEscape() {
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: down)?.post(tap: .cghidEventTap) }
    }
}
