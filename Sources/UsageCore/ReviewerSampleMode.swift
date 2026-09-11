import Foundation

/// Explicit, user-controlled sample data used only to demonstrate the App
/// Store build when provider data is unavailable. Callers must keep the mode
/// default-off and visibly label every surface that renders these values.
public enum UsageReviewerSampleMode {
    public static let isEnabledKey = "reviewerSampleModeEnabled"
    public static let isEnabledDefault = false
    public static let sourceLabel = "Reviewer sample · not live"

    public static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: self.isEnabledKey)
    }

    public static func usage(
        for provider: UsageProviderKind,
        fetchedAt: Date = Date()) -> ProviderUsage
    {
        let metrics: [UsageMetric]
        switch provider {
        case .claude:
            metrics = [
                UsageMetric(
                    id: "session",
                    label: "5-hour",
                    usedPercent: 18,
                    resetsAt: fetchedAt.addingTimeInterval(2 * 60 * 60)),
                UsageMetric(
                    id: "weekly",
                    label: "Weekly",
                    usedPercent: 36,
                    resetsAt: fetchedAt.addingTimeInterval(3 * 24 * 60 * 60)),
            ]
        case .codex:
            metrics = [
                UsageMetric(
                    id: "session",
                    label: "5-hour",
                    usedPercent: 37,
                    resetsAt: fetchedAt.addingTimeInterval(90 * 60)),
                UsageMetric(
                    id: "weekly",
                    label: "Weekly",
                    usedPercent: 22,
                    resetsAt: fetchedAt.addingTimeInterval(4 * 24 * 60 * 60)),
            ]
        case .grok:
            metrics = [
                UsageMetric(
                    id: "credits",
                    label: "Credits",
                    usedPercent: 9,
                    resetsAt: fetchedAt.addingTimeInterval(12 * 24 * 60 * 60)),
            ]
        }

        return ProviderUsage(
            provider: provider,
            metrics: metrics,
            sourceLabel: self.sourceLabel,
            fetchedAt: fetchedAt)
    }
}
