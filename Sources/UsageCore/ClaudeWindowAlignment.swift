import Foundation

public enum ClaudeWindowAlignmentSettings {
    public static let isEnabledKey = "claudeWindowAlignmentEnabled"
    public static let anchorDateKey = "claudeWindowAlignmentAnchorDate"
    public static let lastHandledSlotKey = "claudeWindowAlignmentLastHandledSlot"

    public static let defaultAnchorHour = 6
    public static let defaultAnchorMinute = 0
    public static let interval: TimeInterval = 5 * 60 * 60
    public static let executionGracePeriod: TimeInterval = 8 * 60

    public static func defaultAnchorDate(
        now: Date = Date(),
        calendar: Calendar = .current) -> Date
    {
        self.anchorDate(
            matching: now,
            hour: self.defaultAnchorHour,
            minute: self.defaultAnchorMinute,
            calendar: calendar)
    }

    public static func anchorDate(
        matching referenceDate: Date,
        hour: Int,
        minute: Int,
        calendar: Calendar = .current) -> Date
    {
        let safeHour = min(23, max(0, hour))
        let safeMinute = min(59, max(0, minute))
        return calendar.date(
            bySettingHour: safeHour,
            minute: safeMinute,
            second: 0,
            of: referenceDate) ?? referenceDate
    }

    public static func anchorDate(
        matching referenceDate: Date,
        timeFrom selectedDate: Date,
        calendar: Calendar = .current) -> Date
    {
        let components = calendar.dateComponents([.hour, .minute], from: selectedDate)
        return self.anchorDate(
            matching: referenceDate,
            hour: components.hour ?? self.defaultAnchorHour,
            minute: components.minute ?? self.defaultAnchorMinute,
            calendar: calendar)
    }
}

public enum UsageDistributionPolicy {
#if USAGE_APP_STORE
    public static let supportsClaudeWindowAnchor = false
#else
    public static let supportsClaudeWindowAnchor = true
#endif

    public static func resolvedClaudeWindowAnchorEnabled(storedValue: Bool) -> Bool {
        self.supportsClaudeWindowAnchor && storedValue
    }
}

public enum MacAwakeSettings {
    /// Zero is the slider's infinity position: stay active until the user
    /// turns the feature off or quits Usage.
    public static let defaultActiveDurationHours = 0
    public static let minimumActiveDurationHours = 0
    public static let maximumActiveDurationHours = 24
    /// Coffee ON keeps both the display and the system awake from idle sleep.
    /// Forced sleep, including lid close and explicit user sleep, is unaffected.
    public static let activityOptions: ProcessInfo.ActivityOptions = [
        .idleDisplaySleepDisabled,
        .idleSystemSleepDisabled,
    ]

    public static func clampedDurationHours(_ value: Int) -> Int {
        min(self.maximumActiveDurationHours, max(self.minimumActiveDurationHours, value))
    }
}

public enum ClaudeWindowAnchorCommand {
    public static let prompt = "Reply exactly READY. Do not call tools."

    public static var arguments: [String] {
        [
            "--safe-mode",
            "--tools", "",
            "--permission-mode", "dontAsk",
            "--no-session-persistence",
            "--max-turns", "1",
            "--model", "haiku",
            "--no-chrome",
            "--disable-slash-commands",
            "-p", self.prompt,
        ]
    }

    public static let removedEnvironmentKeys: Set<String> = [
        "ANTHROPIC_API_KEY",
        "ANTHROPIC_AUTH_TOKEN",
        "ANTHROPIC_BASE_URL",
        "CLAUDE_CODE_OAUTH_TOKEN",
        "CLAUDE_CODE_USE_BEDROCK",
        "CLAUDE_CODE_USE_FOUNDRY",
        "CLAUDE_CODE_USE_VERTEX",
    ]

    public static func sanitizedEnvironment(_ environment: [String: String]) -> [String: String] {
        environment.filter { !self.removedEnvironmentKeys.contains($0.key) }
    }
}

public struct ClaudeWindowAlignmentSlot: Equatable, Sendable {
    public let index: Int
    public let dueAt: Date
    public let id: String

    public init(index: Int, dueAt: Date, anchor: Date) {
        self.index = index
        self.dueAt = dueAt
        self.id = "\(Int(anchor.timeIntervalSince1970)):\(index)"
    }
}

/// A continuous five-hour lattice anchored to one absolute date and time.
/// The wall-clock time therefore advances by one hour on the following day;
/// it is intentionally not reset to the same four daily times.
public struct ClaudeWindowAlignmentSchedule: Equatable, Sendable {
    public let anchor: Date
    public let interval: TimeInterval

    public init(
        anchor: Date,
        interval: TimeInterval = ClaudeWindowAlignmentSettings.interval)
    {
        self.anchor = anchor
        self.interval = max(1, interval)
    }

    public func slot(index: Int) -> ClaudeWindowAlignmentSlot {
        let safeIndex = max(0, index)
        return ClaudeWindowAlignmentSlot(
            index: safeIndex,
            dueAt: self.anchor.addingTimeInterval(Double(safeIndex) * self.interval),
            anchor: self.anchor)
    }

    public func dueSlot(
        at date: Date,
        gracePeriod: TimeInterval = ClaudeWindowAlignmentSettings.executionGracePeriod)
        -> ClaudeWindowAlignmentSlot?
    {
        let elapsed = date.timeIntervalSince(self.anchor)
        guard elapsed >= 0 else { return nil }
        let index = Int(floor(elapsed / self.interval))
        let candidate = self.slot(index: index)
        let lateness = date.timeIntervalSince(candidate.dueAt)
        guard lateness >= 0, lateness <= max(0, gracePeriod) else { return nil }
        return candidate
    }

    public func nextSlot(after date: Date) -> ClaudeWindowAlignmentSlot {
        guard date >= self.anchor else { return self.slot(index: 0) }
        let elapsed = date.timeIntervalSince(self.anchor)
        let nextIndex = Int(floor(elapsed / self.interval)) + 1
        return self.slot(index: nextIndex)
    }

    public func upcomingSlots(after date: Date, count: Int) -> [ClaudeWindowAlignmentSlot] {
        guard count > 0 else { return [] }
        let first = self.nextSlot(after: date)
        return (first.index..<(first.index + count)).map(self.slot(index:))
    }
}
