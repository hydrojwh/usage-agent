import Foundation

public struct MenuBarSummaryItem: Equatable, Identifiable, Sendable {
    public let provider: UsageProviderKind
    public let value: String

    public init(provider: UsageProviderKind, value: String) {
        self.provider = provider
        self.value = value
    }

    public var id: UsageProviderKind { self.provider }
}

public enum MenuBarSummary {
    public static func items(
        for statuses: [ProviderUsageStatus],
        providers: [UsageProviderKind] = UsageProviderKind.allCases) -> [MenuBarSummaryItem]
    {
        providers.map { provider in
            MenuBarSummaryItem(provider: provider, value: self.value(for: provider, in: statuses))
        }
    }

    public static func text(for statuses: [ProviderUsageStatus]) -> String {
        self.items(for: statuses).map { item in
            "\(item.provider.menuAbbreviation)\(item.value)"
        }.joined(separator: " ")
    }

    public static func value(
        for provider: UsageProviderKind,
        in statuses: [ProviderUsageStatus]) -> String
    {
        statuses.first(where: { $0.provider == provider })?.usage?.headlineMetric.map {
            String(Int($0.remainingPercent.rounded()))
        } ?? "—"
    }

    public static func accessibilityText(
        for statuses: [ProviderUsageStatus],
        providers: [UsageProviderKind] = UsageProviderKind.allCases) -> String
    {
        let indexed = Dictionary(
            statuses.map { ($0.provider, $0) },
            uniquingKeysWith: { _, last in last })

        return providers.map { provider in
            guard let metric = indexed[provider]?.usage?.headlineMetric else {
                return "\(provider.displayName) usage unavailable"
            }
            return "\(provider.displayName) \(Int(metric.remainingPercent.rounded())) percent remaining"
        }.joined(separator: ", ")
    }
}
