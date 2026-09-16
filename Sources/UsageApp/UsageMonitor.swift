import Combine
import Foundation
import UsageCore
import WidgetKit

@MainActor
final class UsageMonitor: ObservableObject {
    static let shared: UsageMonitor = {
#if USAGE_APP_STORE
        UsageMonitor(
            collector: LiveUsageCollector(),
            reviewerSampleModeEnabled: UsageReviewerSampleMode.isEnabled())
#else
        UsageMonitor(collector: LiveUsageCollector())
#endif
    }()

    @Published private(set) var statuses: [ProviderUsageStatus]
    @Published private(set) var isRefreshing = false
    @Published private(set) var refreshHistory = UsageRefreshHistory()
    @Published private(set) var reviewerSampleModeEnabled: Bool
    /// Non-nil when the last widget snapshot write failed. Surfaced in the
    /// popover footer so an unresolved app-group problem is never silent.
    @Published private(set) var widgetSyncError: String?

    private let collector: any ProviderUsageCollecting
    private(set) var refreshInterval: Duration
    private let defaults: UserDefaults
    private var refreshLoop: Task<Void, Never>?
    /// Reset boundaries this process has already refreshed for. Bounded by
    /// `UsageResetBoundarySchedule.remember`.
    private var attemptedResetBoundaries: Set<Date> = []
    /// Consecutive refreshes that came back still describing a window whose
    /// reset has passed. Backs off the retry towards the regular cadence.
    private var endedWindowRetries = 0

    init(
        collector: any ProviderUsageCollecting,
        refreshInterval: Duration = .seconds(300),
        reviewerSampleModeEnabled: Bool = UsageReviewerSampleMode.isEnabledDefault,
        defaults: UserDefaults = .standard)
    {
        self.collector = collector
        self.refreshInterval = refreshInterval
        self.reviewerSampleModeEnabled = reviewerSampleModeEnabled
        self.defaults = defaults
        self.statuses = UsageProviderKind.allCases.map {
            ProviderUsageStatus(provider: $0, isLoading: true)
        }
    }

    var menuBarText: String {
        MenuBarSummary.text(for: self.menuBarStatuses)
    }

    var menuBarAccessibilityText: String {
        let summary = MenuBarSummary.accessibilityText(for: self.menuBarStatuses)
        return self.reviewerSampleModeEnabled
            ? "Reviewer sample data. \(summary)"
            : summary
    }

    var menuBarStatuses: [ProviderUsageStatus] {
        guard self.reviewerSampleModeEnabled else { return self.statuses }
        return UsageProviderKind.allCases.map { ProviderUsageStatus(provider: $0) }
    }

    func start() {
        guard self.refreshLoop == nil else { return }
        self.refreshLoop = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                // A window that resets mid-interval would otherwise keep showing
                // the previous window's numbers until the next regular tick:
                // land the fetch just after the boundary instead. And once the
                // boundary has passed while the provider still reports the
                // ended window, retry soon rather than sleeping the interval out.
                let wake = self.nextWake()
                do {
                    try await Task.sleep(for: wake.map { .seconds($0.delay) } ?? self.refreshInterval)
                } catch {
                    return
                }
                // Consume the boundary before fetching. If the provider answers
                // with the window that just ended, the same boundary must not
                // schedule a second wake-up; the stale-window retry takes over.
                switch wake {
                case let .boundary(boundary, _):
                    UsageResetBoundarySchedule.remember(boundary, in: &self.attemptedResetBoundaries)
                case .staleWindow:
                    // Counts retries already spent, so the first one waits the
                    // plain grace and only a provider that keeps lagging backs off.
                    self.endedWindowRetries += 1
                case nil:
                    break
                }
                await self.refresh()
                if !UsageResetBoundarySchedule.holdsEndedWindow(statuses: self.statuses, now: Date()) {
                    self.endedWindowRetries = 0
                }
            }
        }
    }

    /// Adjusts the auto-refresh cadence at runtime. The value is clamped to
    /// the settings slider's range and quantized to its 10-second steps. An
    /// idle loop restarts immediately so a shorter interval takes effect
    /// without waiting out the previous sleep; a refresh already in flight
    /// picks the new interval up at its next sleep.
    func setRefreshInterval(seconds: Double) {
        let interval = Duration.seconds(
            UsageDisplaySettings.refreshIntervalSeconds(
                forSteps: UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: seconds)))
        guard interval != self.refreshInterval else { return }
        self.refreshInterval = interval
        guard self.refreshLoop != nil, !self.isRefreshing else { return }
        self.refreshLoop?.cancel()
        self.refreshLoop = nil
        self.start()
    }

    /// The next wake-up worth taking before the regular cadence, or nil to keep it.
    ///
    /// Reviewer sample mode is excluded: its reset dates are fixtures, not
    /// windows a provider will actually roll over.
    private func nextWake() -> UsageResetBoundarySchedule.Wake? {
        guard !self.reviewerSampleModeEnabled else { return nil }
        return UsageResetBoundarySchedule.nextWake(
            statuses: self.statuses,
            now: Date(),
            attemptedBoundaries: self.attemptedResetBoundaries,
            endedWindowRetries: self.endedWindowRetries,
            refreshInterval: Double(self.refreshInterval.components.seconds))
    }

    func stop() {
        self.refreshLoop?.cancel()
        self.refreshLoop = nil
    }

#if USAGE_APP_STORE
    func setReviewerSampleModeEnabled(_ enabled: Bool) async {
        guard enabled != self.reviewerSampleModeEnabled else { return }
        self.defaults.set(enabled, forKey: UsageReviewerSampleMode.isEnabledKey)
        self.reviewerSampleModeEnabled = enabled
        self.statuses = UsageProviderKind.allCases.map {
            ProviderUsageStatus(provider: $0, isLoading: true)
        }
        self.refreshHistory = UsageRefreshHistory()

        // If a refresh is already running, it will detect the changed mode,
        // discard its results, and immediately refresh again in the new mode.
        guard !self.isRefreshing else { return }
        await self.refresh()
    }
#endif

    func refresh() async {
        guard !self.isRefreshing else { return }
        self.isRefreshing = true
        let refreshUsesReviewerSamples = self.reviewerSampleModeEnabled

        let collector = self.collector
        var hadSuccessfulProvider = false
        await withTaskGroup(of: ProviderFetchOutcome.self) { group in
            for provider in UsageProviderKind.allCases {
                group.addTask {
                    if refreshUsesReviewerSamples {
                        return ProviderFetchOutcome(
                            provider: provider,
                            usage: UsageReviewerSampleMode.usage(for: provider),
                            errorMessage: nil)
                    }
                    do {
                        let usage = try await collector.fetch(provider)
                        return ProviderFetchOutcome(provider: provider, usage: usage, errorMessage: nil)
                    } catch {
                        return ProviderFetchOutcome(
                            provider: provider,
                            usage: nil,
                            errorMessage: Self.userFacingMessage(for: provider, error: error))
                    }
                }
            }

            // Publish each provider as soon as it answers. Codex and Grok
            // return in about a second; the Claude CLI probe can take fifteen
            // seconds or more, and holding the fast cards hostage to the slow
            // one made every refresh feel as slow as the slowest provider.
            for await outcome in group {
                // A reviewer-mode flip mid-refresh reset `statuses`; results
                // from the old mode must not be written over that reset.
                guard refreshUsesReviewerSamples == self.reviewerSampleModeEnabled else { continue }
                if outcome.usage != nil {
                    hadSuccessfulProvider = true
                }
                self.apply(outcome)
            }
        }

        guard refreshUsesReviewerSamples == self.reviewerSampleModeEnabled else {
            self.isRefreshing = false
            await self.refresh()
            return
        }

        self.refreshHistory.recordAttempt(
            at: Date(),
            hadSuccessfulProvider: hadSuccessfulProvider)
        self.isRefreshing = false
        self.publishWidgetSnapshot()
    }

    /// Writes one provider's result into `statuses`, keeping the other
    /// providers' cards untouched so a slow provider never blanks a fast one.
    private func apply(_ outcome: ProviderFetchOutcome) {
        guard let index = self.statuses.firstIndex(where: { $0.provider == outcome.provider }) else {
            return
        }
        var updated = self.statuses[index]
        updated.isLoading = false
        if let usage = outcome.usage {
            updated.usage = usage
            updated.errorMessage = nil
        } else {
            updated.errorMessage = outcome.errorMessage
        }
        self.statuses[index] = updated
    }

    /// Persists the current statuses for the widget extension and asks
    /// WidgetKit to reload. File I/O runs off the main actor so a slow disk
    /// never blocks the menu-bar label or popover. The reload is pushed only
    /// after a successful write — reloading on failure would make the widget
    /// re-render old data under a fresh timestamp.
    private func publishWidgetSnapshot() {
        let snapshot = UsageWidgetSnapshot(
            statuses: self.statuses,
            isSample: self.reviewerSampleModeEnabled)
        Task { [weak self] in
            do {
                try await Task.detached(priority: .utility) {
                    try UsageWidgetSnapshotStore.saveDefault(snapshot)
                }.value
                self?.widgetSyncError = nil
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                self?.widgetSyncError = error.localizedDescription
            }
        }
    }

    nonisolated private static func userFacingMessage(for provider: UsageProviderKind, error: Error) -> String {
        if let collectorError = error as? UsageCollectorError {
            if let message = UsageErrorText.trustedCollectorMessage(
                detail: collectorError.localizedDescription,
                suggestion: collectorError.recoverySuggestion)
            {
                return message
            }
        }
        return UsageErrorText.genericProviderMessage(for: provider)
    }
}

private struct ProviderFetchOutcome: Sendable {
    let provider: UsageProviderKind
    let usage: ProviderUsage?
    let errorMessage: String?
}
