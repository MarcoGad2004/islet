import AppKit
import ApplicationServices

/// Small helpers for reading and pressing other apps' Accessibility elements (Notification Center, FaceTime).
enum AX {
    static func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
    }

    static func string(_ e: AXUIElement, _ a: String) -> String? {
        guard let s = attr(e, a) as? String, !s.isEmpty else { return nil }
        return s
    }

    static func number(_ e: AXUIElement, _ a: String) -> Int? { (attr(e, a) as? NSNumber)?.intValue }

    static func role(_ e: AXUIElement) -> String? { string(e, kAXRoleAttribute) }
    static func subrole(_ e: AXUIElement) -> String? { string(e, kAXSubroleAttribute) }
    static func identifier(_ e: AXUIElement) -> String? { string(e, kAXIdentifierAttribute) }
    static func description(_ e: AXUIElement) -> String? { string(e, kAXDescriptionAttribute) }

    static func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }

    static func windows(ofApp pid: pid_t) -> [AXUIElement] {
        (attr(AXUIElementCreateApplication(pid), kAXWindowsAttribute) as? [AXUIElement]) ?? []
    }

    /// Action names; named ones come as "Name:Close\nTarget:…", so only their first line is kept.
    static func actions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        return ((names as? [String]) ?? []).map { String($0.split(separator: "\n").first ?? Substring($0)) }
    }

    private static func rawActions(_ e: AXUIElement) -> [String] {
        var names: CFArray?
        AXUIElementCopyActionNames(e, &names)
        return (names as? [String]) ?? []
    }

    /// Depth-first search, at most `depth` levels down.
    static func first(in e: AXUIElement, depth: Int = 12, where match: (AXUIElement) -> Bool) -> AXUIElement? {
        if match(e) { return e }
        guard depth > 0 else { return nil }
        for c in children(e) { if let hit = first(in: c, depth: depth - 1, where: match) { return hit } }
        return nil
    }

    static func first(in e: AXUIElement, id: String) -> AXUIElement? { first(in: e) { identifier($0) == id } }

    /// Presses a named action ("Show", "Close"), or AXPress when `name` is nil.
    @discardableResult
    static func press(_ e: AXUIElement, named name: String? = nil) -> Bool {
        guard let name else { return AXUIElementPerformAction(e, kAXPressAction as CFString) == .success }
        guard let raw = rawActions(e).first(where: { $0 == "Name:\(name)" || $0.hasPrefix("Name:\(name)\n") }) else { return false }
        return AXUIElementPerformAction(e, raw as CFString) == .success
    }

    static func position(_ e: AXUIElement) -> CGPoint? {
        guard let v = attr(e, kAXPositionAttribute) else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    @discardableResult
    static func setPosition(_ e: AXUIElement, _ p: CGPoint) -> Bool {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return false }
        return AXUIElementSetAttributeValue(e, kAXPositionAttribute as CFString, v) == .success
    }

    /// The element still exists (a destroyed one answers `invalidUIElement`).
    static func alive(_ e: AXUIElement) -> Bool {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &v) != .invalidUIElement
    }
}
