import AppKit
import SwiftUI

/// A small window with one version's release notes (its CHANGELOG.md section, as published on GitHub). Opened from the
/// island's "What's new" after an update, or from Settings before installing.
@MainActor
enum ReleaseNotesWindow {
    private static var window: NSWindow?

    static func show(version: String, notes: String) {
        let view = ReleaseNotesView(version: version, notes: notes) { window?.close() }
        if let w = window {
            w.contentView = NSHostingView(rootView: view)
        } else {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 520),
                             styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 380, height: 300)
            w.contentView = NSHostingView(rootView: view)
            w.center()
            window = w
        }
        window?.title = "What's new in Islet \(version)"
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct ReleaseNotesView: View {
    let version: String
    let notes: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Islet \(version)").font(.title.weight(.semibold))
                    if blocks.isEmpty {
                        Text("No release notes for this version.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, b in
                        switch b.kind {
                        case .heading:
                            Text(Self.inline(b.text)).font(.headline).padding(.top, 6)
                        case .paragraph:
                            Text(Self.inline(b.text)).fixedSize(horizontal: false, vertical: true)
                        case .bullet(let level):
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(level == 0 ? "•" : "◦").foregroundStyle(.secondary)
                                Text(Self.inline(b.text)).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.leading, CGFloat(level) * 18)
                        }
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
            Divider()
            HStack {
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
    }

    // MARK: Markdown: the subset CHANGELOG.md uses (bold headings, nested "- " lists, hard-wrapped lines)

    private enum Kind: Equatable { case heading, paragraph, bullet(Int) }
    private struct Block { var kind: Kind; var text: String }

    private var blocks: [Block] {
        var out: [Block] = []
        var open = false // a block that wrapped lines continue
        for raw in notes.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let indent = line.prefix { $0 == " " }.count
            if trimmed.isEmpty { open = false; continue }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                out.append(Block(kind: .bullet(indent / 2), text: String(trimmed.dropFirst(2)))); open = true
            } else if trimmed.hasPrefix("#") {
                out.append(Block(kind: .heading, text: trimmed.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces))); open = false
            } else if trimmed.hasPrefix("**") && trimmed.hasSuffix("**") && !open {
                out.append(Block(kind: .heading, text: String(trimmed.dropFirst(2).dropLast(2)))); open = false
            } else if open, !out.isEmpty {
                out[out.count - 1].text += " " + trimmed
            } else {
                out.append(Block(kind: .paragraph, text: trimmed)); open = true
            }
        }
        return out
    }

    private static func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
