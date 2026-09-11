import Foundation

public enum UsageProviderKind: String, CaseIterable, Identifiable, Codable, Sendable {
    case claude
    case codex
    case grok

    public var id: String { self.rawValue }

    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .grok: "Grok"
        }
    }

    public var menuAbbreviation: String {
        switch self {
        case .claude: "Cl"
        case .codex: "Cx"
        case .grok: "Gk"
        }
    }
}

public struct UsageMetric: Identifiable, Equatable, Codable, Sendable {
    public let id: String
    public let label: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let resetDescription: String?

    public init(
        id: String,
        label: String,
        usedPercent: Double,
        resetsAt: Date? = nil,
        resetDescription: String? = nil)
    {
        self.id = id
        self.label = label
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.resetDescription = resetDescription
    }

    public var displayedUsedPercent: Double {
        min(100, max(0, self.usedPercent))
    }

    public var remainingPercent: Double {
        100 - self.displayedUsedPercent
    }
}

public enum UsageResetDescriptionFormatter {
    public static func displayText(_ description: String?) -> String? {
        guard let raw = description?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        let normalized = raw.replacingOccurrences(
            of: "(?i)\\b(resets(?=[\\p{L}\\p{N}])|reset(?!s)(?=[\\p{L}\\p{N}]))",
            with: "$1 ",
            options: .regularExpression)
        return normalized.localizedCaseInsensitiveContains("reset")
            ? normalized
            : "Resets \(normalized)"
    }

    public static func displayText(
        resetsAt: Date?,
        resetDescription: String?,
        mode: UsageResetDisplayMode,
        now: Date = Date()) -> String?
    {
        switch mode {
        case .resetTime:
            if let resetsAt {
                // Claude keeps reporting the ended window's clock time after
                // the boundary; that is not the next reset.
                guard resetsAt > now else { return "Reset due" }
                let formattedReset = resetsAt.formatted(
                    .dateTime
                        .month(.abbreviated)
                        .day()
                        .weekday(.abbreviated)
                        .hour()
                        .minute())
                return "Resets \(formattedReset)"
            }
        case .remaining:
            if let resetsAt {
                return self.remainingText(until: resetsAt, now: now)
            }
        }
        return self.displayText(resetDescription)
    }

    private static func remainingText(until resetDate: Date, now: Date) -> String {
        let seconds = resetDate.timeIntervalSince(now)
        guard seconds > 0 else { return "Reset due" }

        let totalMinutes = max(1, Int(ceil(seconds / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = totalMinutes % (24 * 60) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h left" : "\(days)d left"
        }
        if hours > 0 {
            return minutes > 0 ? "\(hours)h \(minutes)m left" : "\(hours)h left"
        }
        return "\(minutes)m left"
    }
}

public enum UsageResetDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case remaining
    case resetTime

    public var id: String { self.rawValue }

    public var toggled: UsageResetDisplayMode {
        self == .remaining ? .resetTime : .remaining
    }
}

public enum UsageDisplaySettings {
    public static let showsAccountIdentifiersKey = "showsAccountIdentifiers"
    public static let showsAccountIdentifiersDefault = false
    public static let resetDisplayModeKey = "resetDisplayMode"
    public static let resetDisplayModeDefault = UsageResetDisplayMode.resetTime
    public static let showsClaudeKey = "showsProviderClaude"
    public static let showsCodexKey = "showsProviderCodex"
    public static let showsGrokKey = "showsProviderGrok"

    public static func showsClaude(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: self.showsClaudeKey) as? Bool ?? true
    }

    public static func identityText(
        accountLabel: String?,
        sourceLabel: String,
        showsAccountIdentifiers: Bool) -> String
    {
        guard showsAccountIdentifiers,
              let account = accountLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
              !account.isEmpty
        else { return sourceLabel }
        return "\(account) · \(sourceLabel)"
    }

    public static func visibleProviders(
        showsClaude: Bool,
        showsCodex: Bool,
        showsGrok: Bool) -> [UsageProviderKind]
    {
        let visibility: [UsageProviderKind: Bool] = [
            .claude: showsClaude,
            .codex: showsCodex,
            .grok: showsGrok,
        ]
        let selected = UsageProviderKind.allCases.filter { visibility[$0] == true }
        return selected.isEmpty ? [.claude] : selected
    }
}

public enum UsageErrorText {
    public static let maximumLength = 240

    public static func sanitized(
        _ text: String,
        maximumLength: Int = UsageErrorText.maximumLength) -> String
    {
        guard maximumLength > 0 else { return "" }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maximumLength else { return trimmed }
        guard maximumLength > 1 else { return "…" }
        return String(trimmed.prefix(maximumLength - 1)) + "…"
    }

    public static func genericProviderMessage(for provider: UsageProviderKind) -> String {
        switch provider {
        case .claude: "Claude usage is unavailable. Run `claude` and sign in, then refresh."
        case .codex: "Codex usage is unavailable. Run `codex` and sign in with ChatGPT, then refresh."
        case .grok: "Grok usage is unavailable. Run `grok login`, then refresh."
        }
    }

    public static func trustedCollectorMessage(
        detail: String?,
        suggestion: String?) -> String?
    {
        let safeDetail = detail.map { self.sanitized($0, maximumLength: 160) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let safeSuggestion = suggestion.map { self.sanitized($0, maximumLength: 160) }
            .flatMap { $0.isEmpty ? nil : $0 }

        return switch (safeDetail, safeSuggestion) {
        case let (detail?, suggestion?): self.sanitized("\(detail) \(suggestion)")
        case let (detail?, nil): detail
        case let (nil, suggestion?): suggestion
        case (nil, nil): nil
        }
    }
}

public struct UsageRefreshHistory: Equatable, Sendable {
    public private(set) var lastAttemptedAt: Date?
    public private(set) var lastSuccessfulAt: Date?

    public init(lastAttemptedAt: Date? = nil, lastSuccessfulAt: Date? = nil) {
        self.lastAttemptedAt = lastAttemptedAt
        self.lastSuccessfulAt = lastSuccessfulAt
    }

    public mutating func recordAttempt(at date: Date, hadSuccessfulProvider: Bool) {
        self.lastAttemptedAt = date
        if hadSuccessfulProvider {
            self.lastSuccessfulAt = date
        }
    }
}

public struct ProviderUsage: Identifiable, Equatable, Codable, Sendable {
    public let provider: UsageProviderKind
    public let metrics: [UsageMetric]
    public let accountLabel: String?
    public let sourceLabel: String
    public let fetchedAt: Date

    public init(
        provider: UsageProviderKind,
        metrics: [UsageMetric],
        accountLabel: String? = nil,
        sourceLabel: String,
        fetchedAt: Date = Date())
    {
        self.provider = provider
        self.metrics = metrics
        self.accountLabel = accountLabel
        self.sourceLabel = sourceLabel
        self.fetchedAt = fetchedAt
    }

    public var id: UsageProviderKind { self.provider }
    public var headlineMetric: UsageMetric? { self.metrics.first }

    /// Maps Grok's CLI billing-proxy result without inventing a zero when the
    /// provider returns a billing period but no usage percentage.
    public static func grokCredits(
        usedPercent: Double?,
        resetsAt: Date?,
        accountLabel: String?,
        sourceLabel: String = "Grok CLI billing",
        fetchedAt: Date = Date()) -> ProviderUsage?
    {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return ProviderUsage(
            provider: .grok,
            metrics: [UsageMetric(
                id: "credits",
                label: "Credits",
                usedPercent: usedPercent,
                resetsAt: resetsAt)],
            accountLabel: accountLabel,
            sourceLabel: sourceLabel,
            fetchedAt: fetchedAt)
    }
}

public struct ProviderUsageStatus: Identifiable, Equatable, Codable, Sendable {
    public let provider: UsageProviderKind
    public var usage: ProviderUsage?
    public var isLoading: Bool
    public var errorMessage: String?

    public init(
        provider: UsageProviderKind,
        usage: ProviderUsage? = nil,
        isLoading: Bool = false,
        errorMessage: String? = nil)
    {
        self.provider = provider
        self.usage = usage
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    public var id: UsageProviderKind { self.provider }
}
