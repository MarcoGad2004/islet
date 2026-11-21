import SwiftUI

/// The round status line at the top of a page: a green tick when all is well, orange when something needs fixing.
struct SettingsHero: View {
    let symbol: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 42, height: 42)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.weight(.semibold))
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }
}

/// One issue and its fix. Without a fix of its own on another page, "Show" goes to where it's fixed.
struct SettingsIssueRow: View {
    let issue: SettingsIssue
    var showPage: ((SettingsPage) -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).fontWeight(.semibold)
                Text(issue.detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action = issue.action, let title = issue.actionTitle {
                if issue.prominent {
                    Button(title, action: action).buttonStyle(.borderedProminent)
                } else {
                    Button(title, action: action)
                }
            } else if let showPage, let page = issue.pages.first {
                Button("Show") { showPage(page) }
            }
        }
        .padding(.vertical, 3)
        .listRowBackground(Color.orange.opacity(0.12))
    }
}

/// The page's issues as a section of their own, above everything else on it.
struct SettingsIssuesSection: View {
    let issues: [SettingsIssue]
    var title: String?
    var showPage: ((SettingsPage) -> Void)?

    var body: some View {
        if !issues.isEmpty {
            Section {
                ForEach(issues) { SettingsIssueRow(issue: $0, showPage: showPage) }
            } header: {
                if let title { Text(title) }
            }
        }
    }
}

/// A caption under a setting.
struct SettingsCaption: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// A setting with its explanation underneath, the way System Settings lays them out.
struct SettingsLabel: View {
    let title: String
    let detail: String?
    init(_ title: String, _ detail: String? = nil) { self.title = title; self.detail = detail }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail { SettingsCaption(detail) }
        }
    }
}

/// The sidebar's coloured square icon.
struct SettingsIcon: View {
    let page: SettingsPage
    var size: CGFloat = 20
    var body: some View {
        Image(systemName: page.symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(page.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    }
}
