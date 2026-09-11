import SwiftUI
import UsageCore

// Brand tokens shared with the menu-bar app (Lobe Icons 1.90.0 identifiers).
// Duplicated here so the widget bundle stays free of app-target code.
private enum ProviderTint {
    static let claude = Color(red: 217.0 / 255.0, green: 119.0 / 255.0, blue: 87.0 / 255.0)
    static let gpt = Color(red: 25.0 / 255.0, green: 195.0 / 255.0, blue: 125.0 / 255.0)

    static func color(for provider: UsageProviderKind, colorScheme: ColorScheme) -> Color {
        switch provider {
        case .claude: Self.claude
        case .codex: Self.gpt
        case .grok: colorScheme == .dark ? .white : .black
        }
    }

    static func assetName(for provider: UsageProviderKind) -> String {
        switch provider {
        case .claude: "ProviderClaude"
        case .codex: "ProviderOpenAI"
        case .grok: "ProviderX"
        }
    }
}

/// Longest staleness the widget shows before dimming the numbers and nudging
/// the user to open the app.
private let staleThreshold: TimeInterval = 3600

struct UsageStripEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    let entry: UsageStripEntry

    var body: some View {
        Group {
            switch self.family {
            case .systemMedium: UsageStripMediumView(entry: self.entry)
            default: UsageStripSmallView(entry: self.entry)
            }
        }
        .containerBackground(for: .widget) {
            Color(nsColor: .windowBackgroundColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(self.accessibilityText)
    }

    private var accessibilityText: String {
        guard let snapshot = self.entry.snapshot else {
            return "\(UsageBrand.displayName) widget waiting for the app"
        }
        let parts = UsageProviderKind.allCases.map { provider -> String in
            guard let entry = snapshot.entry(for: provider) else {
                return "\(provider.displayName) unavailable"
            }
            guard let percent = entry.remainingPercent else {
                if let errorMessage = entry.errorMessage {
                    return "\(provider.displayName) unavailable: \(errorMessage)"
                }
                return "\(provider.displayName) usage unavailable"
            }
            return "\(provider.displayName) \(Int(percent.rounded())) percent remaining"
        }
        let prefix = snapshot.isSample ? "Reviewer sample data, " : ""
        guard !snapshot.isSample,
              let freshnessReferenceDate = snapshot.freshnessReferenceDate
        else {
            return prefix + parts.joined(separator: ", ")
        }
        return prefix + parts.joined(separator: ", ")
            + ", updated \(Self.freshnessText(freshnessReferenceDate, at: self.entry.date))"
    }

    static func freshnessText(_ generatedAt: Date, at now: Date) -> String {
        let age = max(0, now.timeIntervalSince(generatedAt))
        return switch age {
        case ..<90: "just now"
        case ..<3600: "\(Int(age / 60))m ago"
        case ..<86_400: "\(Int(age / 3600))h ago"
        default: generatedAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct ProviderMark: View {
    let provider: UsageProviderKind
    var size: CGFloat = 14

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(ProviderTint.assetName(for: self.provider))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(ProviderTint.color(for: self.provider, colorScheme: self.colorScheme))
            .frame(width: self.size, height: self.size)
            .accessibilityHidden(true)
    }
}

/// Small orange marker for providers that have never produced a value and
/// carry an error (for example "not signed in"). Keeps the widget honest
/// without cramming the full error text into the layout.
private struct ErrorMarker: View {
    var size: CGFloat = 10

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: self.size))
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
    }
}

private struct PercentText: View {
    let percent: Double?
    let tint: Color
    let dimmed: Bool

    var body: some View {
        Text(self.percent.map { "\(Int($0.rounded()))%" } ?? "—")
            .monospacedDigit()
            .foregroundStyle(self.percent == nil ? Color.secondary : self.tint.opacity(self.dimmed ? 0.45 : 1))
    }
}

private struct FreshnessFooter: View {
    let referenceDate: Date?
    let now: Date
    let isSample: Bool

    var body: some View {
        Group {
            if self.isSample {
                Label("Sample · not live", systemImage: "testtube.2")
            } else if let referenceDate {
                let text = UsageStripEntryView.freshnessText(referenceDate, at: self.now)
                Text(self.isStale(referenceDate) ? "\(text) · open \(UsageBrand.displayName)" : text)
            } else {
                Text("Open \(UsageBrand.displayName)")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func isStale(_ referenceDate: Date) -> Bool {
        self.now.timeIntervalSince(referenceDate) > staleThreshold
    }
}

private struct UsageStripSmallView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: UsageStripEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(UsageProviderKind.allCases) { provider in
                HStack(spacing: 6) {
                    ProviderMark(provider: provider)
                    Text(provider.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if self.needsAttention(provider) {
                        ErrorMarker()
                    }
                    Spacer()
                    PercentText(
                        percent: self.snapshot?.entry(for: provider)?.remainingPercent,
                        tint: ProviderTint.color(for: provider, colorScheme: self.colorScheme),
                        dimmed: self.isStale(provider))
                    .font(.callout.weight(.semibold))
                }
            }

            HStack {
                Spacer()
                FreshnessFooter(
                    referenceDate: self.snapshot?.freshnessReferenceDate,
                    now: self.entry.date,
                    isSample: self.snapshot?.isSample == true)
            }
        }
        .padding(2)
    }

    private var snapshot: UsageWidgetSnapshot? { self.entry.snapshot }

    private func isStale(_ provider: UsageProviderKind) -> Bool {
        guard self.snapshot?.isSample != true,
              let fetchedAt = self.snapshot?.freshnessDate(for: provider)
        else { return false }
        return self.entry.date.timeIntervalSince(fetchedAt) > staleThreshold
    }

    private func needsAttention(_ provider: UsageProviderKind) -> Bool {
        guard let entry = self.snapshot?.entry(for: provider) else { return false }
        return entry.remainingPercent == nil && entry.errorMessage != nil
    }
}

private struct UsageStripMediumView: View {
    @Environment(\.colorScheme) private var colorScheme

    let entry: UsageStripEntry

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                ForEach(UsageProviderKind.allCases) { provider in
                    self.column(for: provider)
                }
            }
            .frame(maxWidth: .infinity)

            FreshnessFooter(
                referenceDate: self.snapshot?.freshnessReferenceDate,
                now: self.entry.date,
                isSample: self.snapshot?.isSample == true)
        }
        .padding(4)
    }

    private var snapshot: UsageWidgetSnapshot? { self.entry.snapshot }

    private func isStale(_ provider: UsageProviderKind) -> Bool {
        guard self.snapshot?.isSample != true,
              let fetchedAt = self.snapshot?.freshnessDate(for: provider)
        else { return false }
        return self.entry.date.timeIntervalSince(fetchedAt) > staleThreshold
    }

    private func column(for provider: UsageProviderKind) -> some View {
        let tint = ProviderTint.color(for: provider, colorScheme: self.colorScheme)
        let widgetEntry = self.snapshot?.entry(for: provider)
        let sublabel = widgetEntry?.windowLabel
            ?? ((widgetEntry?.errorMessage != nil) ? "Check the app" : provider.displayName)

        return VStack(spacing: 4) {
            ProviderMark(provider: provider, size: 18)
            PercentText(percent: widgetEntry?.remainingPercent, tint: tint, dimmed: self.isStale(provider))
                .font(.title3.weight(.semibold))
            if widgetEntry?.remainingPercent == nil, widgetEntry?.errorMessage != nil {
                ErrorMarker()
            }
            Text(sublabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
