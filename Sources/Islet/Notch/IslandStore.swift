import AppKit

/// Single source of truth for what the island shows (ARCHITECTURE.md layer 5).
/// Feature modules set `base`; hover, click and gestures drive the rest.
@MainActor @Observable
final class IslandStore {
    private(set) var geometry: NotchGeometry?
    /// What a feature is showing right now (media, charging, ...). nil when nothing is.
    private(set) var base: Presentation?
    private(set) var expanded = false
    private(set) var pointerInside = false
    private(set) var paused = false
    /// Set while face enrolment is running; the enrol presentation draws from it.
    var enrolment: EnrolmentModel?

    let animator = IslandAnimator()
    /// Called when `expanded` changes, so the panel can take or give up key status (for Esc).
    @ObservationIgnored var onExpandedChange: ((Bool) -> Void)?
    @ObservationIgnored private var leaveTask: Task<Void, Never>?

    var presentation: Presentation {
        if base == .enrol { return .enrol } // enrolment can't be interrupted by hover or clicks
        if expanded { return .expanded }
        if let base { return base }
        return pointerInside ? .peek : .closed
    }

    // MARK: Geometry

    func setGeometry(_ g: NotchGeometry?) {
        geometry = g
        if let m = targetMetrics() { animator.snap(to: m) }
    }

    private func targetMetrics() -> IslandMetrics? {
        guard let g = geometry else { return nil }
        return presentation.metrics(notchWidth: g.width, notchHeight: g.height)
    }

    private func refresh() {
        if let m = targetMetrics() { animator.go(to: m) }
    }

    // MARK: Pointer and hit testing

    /// True when a global pointer position is over the island's current shape.
    func isOverIsland(globalPoint: CGPoint) -> Bool {
        guard let g = geometry, !paused else { return false }
        let p = g.panelPoint(fromGlobal: globalPoint)
        let m = animator.metrics
        let slop = 2.0
        let rect = CGRect(x: NotchGeometry.panelWidth / 2 - m.width / 2 - slop, y: -slop,
                          width: m.width + 2 * slop, height: m.height + slop)
        return rect.contains(p)
    }

    func pointerMoved(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        if inside {
            leaveTask?.cancel()
        } else if expanded {
            // Close 1 s after the pointer leaves.
            leaveTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self?.collapse()
            }
        }
        refresh()
    }

    // MARK: Actions

    func click() { expand() }

    func expand() {
        guard !expanded, base != .enrol else { return }
        setExpanded(true)
    }

    func collapse() {
        guard expanded else { return }
        setExpanded(false)
    }

    private func setExpanded(_ value: Bool) {
        expanded = value
        leaveTask?.cancel()
        onExpandedChange?(value)
        refresh()
    }

    func swipeUp() {
        if expanded { collapse() }
        // M6: hides media when it is showing.
    }

    func swipeDown() {
        // M6: brings hidden media back first. With nothing hidden, open the panel.
        expand()
    }

    /// Clear everything transient (click outside, Esc).
    func dismiss() { collapse() }

    func setBase(_ p: Presentation?) {
        base = p
        refresh()
    }

    func setPaused(_ value: Bool) {
        paused = value
        if value { expanded = false; pointerInside = false; base = nil; onExpandedChange?(false) }
        refresh()
    }
}
