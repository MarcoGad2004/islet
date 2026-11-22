import AppKit
import SwiftUI

/// Search in the notch (DESIGN.md "Search"): the field (it follows the body's edges, so letters show while it is still
/// narrow), the results at the panel's full width, and the footer on the glass strip.
struct SearchView: View {
    let store: IslandStore
    @Bindable var model: SearchModel
    /// The body's width right now, mid-bubble included.
    var bodyWidth: CGFloat
    @Environment(\.isletGlass) private var glass
    @State private var fieldShown = false
    @State private var restShown = false

    private typealias M = SearchModel.Metrics
    static let width: CGFloat = 500

    var body: some View {
        VStack(spacing: 0) {
            field
                .frame(width: max(bodyWidth, 0), height: M.field)
                .opacity(fieldShown ? 1 : 0)
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.08))
                    .frame(height: M.hairline).padding(.horizontal, 20)
                    .frame(height: model.isEmpty ? 0 : M.hairline).opacity(model.isEmpty ? 0 : 1)
                results.frame(height: model.visibleListHeight, alignment: .top).clipped()
                footer.frame(height: M.footer)
            }
            .frame(width: Self.width)
            .opacity(restShown ? 1 : 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            // Typing straight after the shortcut shows at once; the results join as the shape settles
            // (DESIGN.md "Typing while it opens"). Opened from the panel, the shape is already there.
            let opening = !store.searchFromPanel
            withAnimation(.easeOut(duration: 0.16).delay(opening ? 0.12 : 0)) { fieldShown = true }
            withAnimation(.easeOut(duration: 0.24).delay(opening ? 0.36 : 0.1)) { restShown = true }
        }
    }

    // MARK: Field

    private var field: some View {
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium)).foregroundStyle(Color.isletTertiary)
            SearchTextField(model: model)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Results

    private var results: some View {
        PanelScrollView(indicators: false, follow: model.selected?.id) {
            VStack(spacing: 0) {
                ForEach(model.sections) { section in
                    switch section.style {
                    case .recents:
                        recents(section.items)
                    case .none:
                        Text("No results for “\(model.text.trimmingCharacters(in: .whitespaces))”")
                            .font(.system(size: 13)).foregroundStyle(Color.isletSecondary).lineLimit(1)
                            .padding(.horizontal, 20).frame(maxWidth: .infinity, alignment: .leading).frame(height: M.none)
                    default:
                        if let title = section.title {
                            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.6)
                                .foregroundStyle(Color.isletTertiary)
                                .padding(.horizontal, 20).padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .bottomLeading).frame(height: M.label)
                        }
                        ForEach(section.items) { item in
                            SearchRow(item: item, style: section.style, selected: model.selected?.id == item.id, glass: glass,
                                      index: model.index, model: model) { model.activate(item) }
                                .id(item.id)
                        }
                    }
                }
            }
            .padding(.top, model.isEmpty ? 0 : 4)
            .padding(.bottom, model.isEmpty ? 0 : 6)
        }
    }

    private func recents(_ items: [SearchItem]) -> some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let selected = model.selected?.id == item.id
                VStack(spacing: 5) {
                    SearchIcon(item: item, size: 40, index: model.index)
                    Text(item.name).font(.system(size: 10)).foregroundStyle(Color.isletSecondary).lineLimit(1).frame(maxWidth: 58)
                }
                .padding(.vertical, 7)
                .frame(width: 62)
                .background(SelectionPill(selected: selected, glass: glass, radius: 12))
                .contentShape(Rectangle())
                .onTapGesture { model.activate(item) }
                .frame(maxWidth: .infinity)
                .id(item.id)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: M.recents)
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            ForEach(Array(hints.enumerated()), id: \.offset) { _, h in hint(h.0, h.1) }
            Spacer(minLength: 8)
            if model.isEmpty {
                Text(SiriQuestion.offered ? "Type to search, or start with “siri” to ask Siri" : "Type to search apps, files, Shortcuts and settings").lineLimit(1)
            } else {
                hint("esc", "Clear")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(Color.isletSecondary)
        .padding(.horizontal, 20)
        .padding(.bottom, 2)
    }

    private var hints: [(String, String)] {
        guard let s = model.selected else { return [] }
        if model.isEmpty { return [("↩", "Open"), ("← →", "Choose")] }
        switch s.kind {
        case .calc: return [("↩", "Copy")]
        case .shortcut: return [("↩", "Run")]
        case .siri: return s.detail.isEmpty ? [] : [("↩", "Ask Siri")]
        case .spotlight: return [("↩", "Search in Spotlight")]
        case .web: return [("↩", "Open in browser")]
        case .setting: return [("↩", "Open")]
        case .contact: return [("↩", s.action?.verb ?? "Open in Contacts")]
        case .app, .file: return [("↩", "Open"), ("⌘↩", "Show in Finder")]
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key).fontWeight(.medium).foregroundStyle(Color.isletText)
            Text(label)
        }
    }
}

/// One result row: 34 pt (52 for the top hit, 60 for an answer), the selected one on a pill.
private struct SearchRow: View {
    let item: SearchItem
    let style: SearchModel.Section.Style
    let selected: Bool
    let glass: Bool
    let index: SearchIndex
    let model: SearchModel
    let open: () -> Void
    @State private var hovering = false

    private var height: CGFloat {
        switch style {
        case .topHit: SearchModel.Metrics.topHit
        case .calc: SearchModel.Metrics.calc
        default: SearchModel.Metrics.row
        }
    }

    var body: some View {
        HStack(spacing: style == .list ? 10 : 12) {
            SearchIcon(item: item, size: style == .list ? 22 : 32, index: index)
            switch style {
            case .calc:
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(item.detail) =").font(.system(size: 11)).monospacedDigit().foregroundStyle(Color.isletTertiary).lineLimit(1)
                    Text(item.name).font(.system(size: 22, weight: .semibold)).monospacedDigit().foregroundStyle(Color.isletText).lineLimit(1)
                }
            case .topHit:
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.isletText).lineLimit(1)
                    Text(item.kindLabel).font(.system(size: 11)).foregroundStyle(Color.isletTertiary).lineLimit(1).truncationMode(.middle)
                }
            default:
                Text(marked).font(.system(size: 13)).lineLimit(1)
                    .foregroundStyle(item.action != nil ? Color.isletText : Color.isletSecondary)
            }
            Spacer(minLength: 8)
            if style == .list, item.kind == .file {
                Text(SearchIndex.shortPath(item.detail)).font(.system(size: 11)).foregroundStyle(Color.isletTertiary).lineLimit(1)
            }
            // A contact's quick buttons: always on the top hit, on other rows when selected or under the pointer.
            // An action row ("Call Mom") does its one thing on Return, so it has none.
            if item.kind == .contact, item.action == nil, style == .topHit || selected || hovering {
                ContactButtons(item: item, model: model, size: style == .topHit ? 30 : 24)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: height)
        .background {
            if selected { SelectionPill(selected: true, glass: glass, radius: 10) }
            else if hovering { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)) }
        }
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
    }

    /// The matched letters bright, the rest grey ("More" rows all bright).
    private var marked: AttributedString {
        if item.kind == .spotlight || item.kind == .web || item.kind == .siri {
            var a = AttributedString(item.name); a.foregroundColor = .isletText; return a
        }
        var out = AttributedString()
        for (i, ch) in item.name.enumerated() {
            var a = AttributedString(String(ch))
            if item.marks.contains(i) { a.foregroundColor = .isletText; a.font = .system(size: 13, weight: .medium) }
            else { a.foregroundColor = .isletSecondary }
            out += a
        }
        return out
    }
}

private struct SelectionPill: View {
    let selected: Bool
    let glass: Bool
    let radius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if !selected { Color.clear }
        else if glass { shape.fill(Color.white.opacity(0.10)).overlay(shape.stroke(Color.white.opacity(0.2), lineWidth: 0.5)) }
        else { shape.fill(Color(hex: 0x1C1C1E)) }
    }
}

/// An app's or file's own icon; a coloured square with a symbol for the rest.
struct SearchIcon: View {
    let item: SearchItem
    let size: CGFloat
    let index: SearchIndex

    var body: some View {
        Group {
            switch item.kind {
            case .app, .file:
                if let image = index.icon(for: item) { Image(nsImage: image).resizable().interpolation(.high) } else { Color.clear }
            case .contact:
                // Their photo, or their initials on a purple circle.
                if let image = index.icon(for: item) {
                    Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fill).clipShape(Circle())
                } else {
                    Circle().fill(Color(hex: 0x5E5CE6))
                        .overlay(Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white))
                }
            case .calc:
                Image(nsImage: NSWorkspace.shared.icon(forFile: SearchIndex.calculatorURL.path)).resizable().interpolation(.high)
            case .shortcut:
                tile(LinearGradient(colors: [Color(hex: 0x5E5CE6), Color(hex: 0xBF5AF2)], startPoint: .top, endPoint: .bottom), "bolt.fill")
            case .setting:
                let page = SearchIndex.page(named: item.name)
                tile(LinearGradient(colors: [Color(hex: page?.color ?? 0x8E8E93)], startPoint: .top, endPoint: .bottom), page?.symbol ?? "gearshape.fill")
            case .siri:
                // Siri's orb: a ring of colour round a dark middle.
                Circle().fill(AngularGradient(colors: [Color(hex: 0xFF5FA2), Color(hex: 0xFFB340), Color(hex: 0x5AD6FF),
                                                       Color(hex: 0x8A5CFF), Color(hex: 0xFF5FA2)], center: .center, angle: .degrees(200)))
                    .overlay(Circle().fill(Color.black.opacity(0.55)).padding(size * 0.28))
                    .padding(size * 0.06)
            case .spotlight:
                tile(LinearGradient(colors: [Color(hex: 0x8E8E93), Color(hex: 0x636366)], startPoint: .top, endPoint: .bottom), "magnifyingglass")
            case .web:
                tile(LinearGradient(colors: [Color(hex: 0x64D2FF), Color(hex: 0x0A84FF)], startPoint: .top, endPoint: .bottom), "globe")
            }
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        item.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private func tile(_ fill: LinearGradient, _ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous).fill(fill)
            .overlay(Image(systemName: symbol).font(.system(size: size * 0.5, weight: .semibold)).foregroundStyle(.white))
            .padding(size * 0.04)
    }
}

/// The field. AppKit's, so it takes the cursor the moment it is in the window and keeps the letters typed before that
/// (the panel kept them in `model.text`), with the cursor after them.
private struct SearchTextField: NSViewRepresentable {
    let model: SearchModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> FocusingField {
        let f = FocusingField()
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 19)
        f.textColor = NSColor(Color.isletText)
        f.placeholderAttributedString = NSAttributedString(string: "Search", attributes: [
            .foregroundColor: NSColor(Color.isletTertiary), .font: NSFont.systemFont(ofSize: 19),
        ])
        f.usesSingleLineMode = true
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.delegate = context.coordinator
        f.stringValue = model.text
        f.onFocus = { [weak f] in
            guard let f else { return }
            f.stringValue = model.text
            f.currentEditor()?.selectedRange = NSRange(location: (f.stringValue as NSString).length, length: 0)
            model.fieldReady = true
        }
        return f
    }

    func updateNSView(_ f: FocusingField, context: Context) {
        _ = model.focusRequest
        if f.stringValue != model.text {
            f.stringValue = model.text
            f.currentEditor()?.selectedRange = NSRange(location: (f.stringValue as NSString).length, length: 0)
        }
        if context.coordinator.focusRequest != model.focusRequest {
            context.coordinator.focusRequest = model.focusRequest
            f.focusSoon()
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: SearchModel
        var focusRequest = -1
        init(model: SearchModel) { self.model = model }

        func controlTextDidChange(_ note: Notification) {
            guard let f = note.object as? NSTextField else { return }
            if model.text != f.stringValue { model.text = f.stringValue }
        }
    }

    final class FocusingField: NSTextField {
        var onFocus: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusSoon()
        }

        func focusSoon() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                if window.firstResponder !== self.currentEditor() || self.currentEditor() == nil {
                    guard window.makeFirstResponder(self) else { return }
                }
                self.onFocus?()
            }
        }
    }
}

/// Message, Call, FaceTime and Email for a contact, as small round glass buttons (DESIGN.md "Search", Contacts).
private struct ContactButtons: View {
    let item: SearchItem
    let model: SearchModel
    let size: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            ForEach(item.contactActions, id: \.self) { a in
                Button { model.perform(a, on: item) } label: {
                    Image(systemName: a.symbol).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(Color.isletText)
                        .frame(width: size, height: size)
                        .background(IsletCard(shape: Circle()))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help(a.verb)
            }
        }
    }
}
