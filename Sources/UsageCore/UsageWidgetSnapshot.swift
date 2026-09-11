import Foundation

/// Snapshot of the representative per-provider remaining quota, written by the
/// Usage app after each successful refresh and read by the sandboxed widget
/// extension. The widget never fetches provider data on its own.
public struct UsageWidgetSnapshot: Codable, Equatable, Sendable {
    public struct ProviderEntry: Codable, Equatable, Sendable, Identifiable {
        public let provider: UsageProviderKind
        /// Representative remaining percent for the provider's headline window,
        /// or `nil` when no value has ever been fetched.
        public let remainingPercent: Double?
        /// Headline window label (for example "5-hour window"), when known.
        public let windowLabel: String?
        /// Populated only when the provider has no last-known-good value.
        /// While a value exists it is kept and this stays `nil`, matching the
        /// "keep previous good data on transient errors" display contract.
        public let errorMessage: String?
        public let fetchedAt: Date?

        public init(
            provider: UsageProviderKind,
            remainingPercent: Double?,
            windowLabel: String? = nil,
            errorMessage: String? = nil,
            fetchedAt: Date? = nil)
        {
            self.provider = provider
            self.remainingPercent = remainingPercent
            self.windowLabel = windowLabel
            self.errorMessage = errorMessage
            self.fetchedAt = fetchedAt
        }

        public var id: UsageProviderKind { self.provider }
    }

    public static let currentSchemaVersion = 2

    public let schemaVersion: Int
    public let generatedAt: Date
    public let entries: [ProviderEntry]
    /// True only for explicitly enabled reviewer/sample data. Widget views
    /// must label these values as samples rather than presenting them as live.
    public let isSample: Bool

    public init(
        schemaVersion: Int = UsageWidgetSnapshot.currentSchemaVersion,
        generatedAt: Date,
        entries: [ProviderEntry],
        isSample: Bool = false)
    {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.entries = entries
        self.isSample = isSample
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case entries
        case isSample
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        self.entries = try container.decode([ProviderEntry].self, forKey: .entries)
        self.isSample = try container.decodeIfPresent(Bool.self, forKey: .isSample) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.schemaVersion, forKey: .schemaVersion)
        try container.encode(self.generatedAt, forKey: .generatedAt)
        try container.encode(self.entries, forKey: .entries)
        try container.encode(self.isSample, forKey: .isSample)
    }

    /// Builds a snapshot from monitor statuses in the canonical provider order
    /// (Claude, Codex, Grok). Entries without a value but with an error surface
    /// the error; entries with a last-known-good value keep the number.
    public init(
        statuses: [ProviderUsageStatus],
        generatedAt: Date = Date(),
        isSample: Bool = false)
    {
        // Duplicate providers would crash uniqueKeysWithValues; last one wins.
        let indexed = Dictionary(
            statuses.map { ($0.provider, $0) },
            uniquingKeysWith: { _, last in last })

        self.init(
            generatedAt: generatedAt,
            entries: UsageProviderKind.allCases.map { provider in
                let status = indexed[provider]
                let metric = status?.usage?.headlineMetric

                return ProviderEntry(
                    provider: provider,
                    remainingPercent: metric.map { $0.remainingPercent },
                    windowLabel: metric?.label,
                    errorMessage: (status?.usage == nil)
                        ? status?.errorMessage.map { UsageErrorText.sanitized($0) }
                        : nil,
                    fetchedAt: status?.usage?.fetchedAt)
            },
            isSample: isSample)
    }

    /// Sample data for widget placeholders, previews, and the gallery.
    public static var placeholder: UsageWidgetSnapshot {
        UsageWidgetSnapshot(
            generatedAt: Date(),
            entries: [
                ProviderEntry(provider: .claude, remainingPercent: 82, windowLabel: "5-hour window"),
                ProviderEntry(provider: .codex, remainingPercent: 63, windowLabel: "Rate-limit window"),
                ProviderEntry(provider: .grok, remainingPercent: 91, windowLabel: "Monthly window"),
            ],
            isSample: true)
    }

    public func entry(for provider: UsageProviderKind) -> ProviderEntry? {
        self.entries.first { $0.provider == provider }
    }

    /// Oldest acquisition time among values currently displayed by the widget.
    /// Falls back to snapshot generation for older snapshots without `fetchedAt`.
    public var freshnessReferenceDate: Date? {
        let displayedEntries = self.entries.filter { $0.remainingPercent != nil }
        guard !displayedEntries.isEmpty else { return nil }
        return displayedEntries.compactMap(\.fetchedAt).min() ?? self.generatedAt
    }

    public func freshnessDate(for provider: UsageProviderKind) -> Date? {
        guard let entry = self.entry(for: provider), entry.remainingPercent != nil else { return nil }
        return entry.fetchedAt ?? self.generatedAt
    }
}
