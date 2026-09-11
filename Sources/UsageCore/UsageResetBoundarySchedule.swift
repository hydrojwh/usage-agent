import Foundation

/// Decides when a refresh should happen sooner than the regular cadence because
/// a quota window is about to roll over, or has already rolled over while the
/// numbers on screen still describe the window that ended.
///
/// The fixed refresh cadence means a window that resets mid-interval can keep
/// showing the previous window's numbers until the next tick. Shortening the
/// cadence is the wrong trade: every Claude fetch spawns the full Claude CLI
/// binary, so halving the interval doubles that cost all day to save a few
/// minutes once per window.
///
/// Two cases need a wake-up, and both were observed on 2026-09-06 against a
/// five-hour window that reset at 11:00:
///
/// 1. **The boundary is coming.** Land the next fetch just after it instead of
///    wherever the cadence happens to fall.
/// 2. **The boundary has passed and the provider has not caught up.** The Claude
///    CLI keeps reporting the ended window for a while after the boundary, and
///    `ClaudeStatusProbe.parseResetDate` resolves that report to a date in the
///    *past* (the next occurrence of that clock time cannot belong to a
///    five-hour window, so the recent one is chosen). Held data with a reset
///    date in the past therefore means "these numbers describe a window that
///    has already ended" — the moment a re-fetch is most wanted. Waiting a full
///    interval here, and another if the provider is still behind, is what made
///    an 11:00 reset show up at 11:10.
///
/// The design otherwise mirrors CodexBar's own `UsageStore+ResetBoundaryRefresh`,
/// which lives in that project's app target and so cannot be linked from here.
public enum UsageResetBoundarySchedule {
    /// Wait this long after the boundary before refetching. A provider CLI asked
    /// exactly at the boundary can still answer with the window that just ended.
    public static let grace: TimeInterval = 30

    /// Never schedule a wake-up closer than this, so a boundary that is already
    /// passing cannot produce a busy loop of near-zero sleeps.
    public static let minimumDelay: TimeInterval = 5

    /// How many recently used boundaries a caller should remember. Bounded so a
    /// long-running process cannot grow the set without limit.
    public static let attemptedBoundaryLimit = 64

    public enum Wake: Equatable, Sendable {
        /// Sleep `delay`, then refresh for `boundary`. The caller records the
        /// boundary so one rollover produces one early fetch.
        case boundary(Date, delay: TimeInterval)
        /// Sleep `delay`, then refresh because the numbers on hand describe a
        /// window that has already ended.
        case staleWindow(delay: TimeInterval)

        public var delay: TimeInterval {
            switch self {
            case let .boundary(_, delay): delay
            case let .staleWindow(delay): delay
            }
        }
    }

    /// True when any provider's numbers describe a window whose reset has passed.
    public static func holdsEndedWindow(statuses: [ProviderUsageStatus], now: Date) -> Bool {
        self.resetDates(in: statuses).contains { $0 <= now }
    }

    /// The next wake-up worth taking before the regular cadence, or nil to keep it.
    ///
    /// - Parameters:
    ///   - statuses: Current provider statuses. Only providers holding usage are
    ///     considered: a failed provider has no numbers to be stale about.
    ///   - now: Current time. Recomputed by the caller on every iteration so
    ///     that sleep, wake, and clock changes correct themselves.
    ///   - attemptedBoundaries: Boundaries already refreshed for, so one
    ///     rollover cannot schedule itself twice.
    ///   - endedWindowRetries: How many consecutive refreshes have come back
    ///     still describing an ended window. Backs the retry off so a provider
    ///     that lags for minutes is not polled every 30 seconds.
    ///   - refreshInterval: The regular cadence.
    public static func nextWake(
        statuses: [ProviderUsageStatus],
        now: Date,
        attemptedBoundaries: Set<Date>,
        endedWindowRetries: Int,
        refreshInterval: TimeInterval) -> Wake?
    {
        guard refreshInterval > 0 else { return nil }
        let resets = self.resetDates(in: statuses)

        // The numbers on screen already describe a window that ended. Retry
        // soon, backing off towards the regular cadence so a provider that
        // takes minutes to roll over costs a few extra fetches, not a storm.
        if resets.contains(where: { $0 <= now }) {
            let backoff = self.grace * pow(2, Double(max(0, endedWindowRetries)))
            return .staleWindow(delay: min(max(backoff, self.minimumDelay), refreshInterval))
        }

        // Otherwise land the next fetch just after the coming boundary. The
        // boundary itself has to fall inside the interval; the grace may push
        // the wake-up slightly past it, which delays that one tick by at most
        // `grace` and is what keeps the fetch from landing a moment too early.
        guard let boundary = resets
            .filter({ $0 > now && !attemptedBoundaries.contains($0) })
            .min(),
            boundary.timeIntervalSince(now) <= refreshInterval
        else { return nil }

        return .boundary(
            boundary,
            delay: max(boundary.timeIntervalSince(now) + self.grace, self.minimumDelay))
    }

    /// Records a boundary as used, keeping the set bounded by dropping the
    /// oldest entries. Boundaries are only ever consumed in time order, so the
    /// oldest are the ones that can no longer be scheduled.
    public static func remember(_ boundary: Date, in attemptedBoundaries: inout Set<Date>) {
        attemptedBoundaries.insert(boundary)
        guard attemptedBoundaries.count > self.attemptedBoundaryLimit else { return }
        let excess = attemptedBoundaries.count - self.attemptedBoundaryLimit
        for old in attemptedBoundaries.sorted().prefix(excess) {
            attemptedBoundaries.remove(old)
        }
    }

    private static func resetDates(in statuses: [ProviderUsageStatus]) -> [Date] {
        statuses.compactMap(\.usage).flatMap(\.metrics).compactMap(\.resetsAt)
    }
}
