import Foundation
import XCTest
@testable import UsageCore

final class UsageResetBoundaryScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let interval: TimeInterval = 300

    private func status(
        _ provider: UsageProviderKind,
        resetsAt: Date?,
        hasUsage: Bool = true,
        errorMessage: String? = nil) -> ProviderUsageStatus
    {
        let usage = hasUsage
            ? ProviderUsage(
                provider: provider,
                metrics: [UsageMetric(
                    id: "session",
                    label: "5-hour",
                    usedPercent: 40,
                    resetsAt: resetsAt)],
                accountLabel: nil,
                sourceLabel: "test")
            : nil
        return ProviderUsageStatus(provider: provider, usage: usage, errorMessage: errorMessage)
    }

    private func wake(
        _ statuses: [ProviderUsageStatus],
        attempted: Set<Date> = [],
        endedWindowRetries: Int = 0) -> UsageResetBoundarySchedule.Wake?
    {
        UsageResetBoundarySchedule.nextWake(
            statuses: statuses,
            now: self.now,
            attemptedBoundaries: attempted,
            endedWindowRetries: endedWindowRetries,
            refreshInterval: self.interval)
    }

    // MARK: - Coming boundary

    func testBoundaryInsideTheIntervalIsScheduledAfterTheGrace() {
        let boundary = self.now.addingTimeInterval(60)

        XCTAssertEqual(
            self.wake([self.status(.claude, resetsAt: boundary)]),
            .boundary(boundary, delay: 60 + UsageResetBoundarySchedule.grace))
    }

    /// A boundary further out than the cadence is left to the regular tick.
    func testBoundaryBeyondTheIntervalKeepsTheRegularCadence() {
        XCTAssertNil(self.wake([self.status(.claude, resetsAt: self.now.addingTimeInterval(4 * 3_600))]))
    }

    /// Regression: the first version required the whole delay, grace included,
    /// to fit inside the interval. A boundary 280 s away therefore scheduled
    /// nothing, the regular tick landed 20 s *before* the reset and fetched the
    /// old window, and the app then waited a full interval more. The boundary
    /// itself is what has to fit; the grace may push the wake-up past it.
    func testBoundaryNearTheEndOfTheIntervalStillSchedules() {
        let boundary = self.now.addingTimeInterval(280)

        XCTAssertEqual(
            self.wake([self.status(.claude, resetsAt: boundary)]),
            .boundary(boundary, delay: 280 + UsageResetBoundarySchedule.grace))
    }

    func testMissingBoundaryKeepsTheRegularCadence() {
        XCTAssertNil(self.wake([self.status(.codex, resetsAt: nil)]))
    }

    /// A failed provider has no numbers to be stale about.
    func testProviderWithoutUsageIsIgnored() {
        XCTAssertNil(self.wake([
            self.status(.claude, resetsAt: nil, hasUsage: false, errorMessage: "boom"),
        ]))
    }

    func testEarliestBoundaryAcrossProvidersWins() {
        let soon = self.now.addingTimeInterval(30)
        let later = self.now.addingTimeInterval(120)

        XCTAssertEqual(
            self.wake([
                self.status(.claude, resetsAt: later),
                self.status(.grok, resetsAt: soon),
            ]),
            .boundary(soon, delay: 30 + UsageResetBoundarySchedule.grace))
    }

    func testAlreadyAttemptedBoundaryIsSkippedAndTheNextOneIsUsed() {
        let first = self.now.addingTimeInterval(30)
        let second = self.now.addingTimeInterval(90)
        let statuses = [
            self.status(.claude, resetsAt: first),
            self.status(.grok, resetsAt: second),
        ]

        XCTAssertEqual(
            self.wake(statuses, attempted: [first]),
            .boundary(second, delay: 90 + UsageResetBoundarySchedule.grace))
        XCTAssertNil(self.wake(statuses, attempted: [first, second]))
    }

    func testDelayNeverFallsBelowTheMinimum() {
        let boundary = self.now.addingTimeInterval(0.001)

        XCTAssertGreaterThanOrEqual(
            self.wake([self.status(.claude, resetsAt: boundary)])?.delay ?? 0,
            UsageResetBoundarySchedule.minimumDelay)
    }

    // MARK: - Window that has already ended

    /// The field failure of 2026-09-06: a five-hour window reset at 11:00, the
    /// Claude CLI kept reporting the ended window, and the parser resolved that
    /// report to a date in the past. Holding a past reset date means the numbers
    /// describe a window that is over, so retry soon instead of sleeping the
    /// interval out — twice over, that turned a reset into a ten-minute wait.
    func testPastResetSchedulesAPromptRetry() {
        XCTAssertEqual(
            self.wake([self.status(.claude, resetsAt: self.now.addingTimeInterval(-1))]),
            .staleWindow(delay: UsageResetBoundarySchedule.grace))
    }

    func testEndedWindowRetriesBackOffAndCapAtTheInterval() {
        let stale = [self.status(.claude, resetsAt: self.now.addingTimeInterval(-1))]
        let delays = (0...5).map { self.wake(stale, endedWindowRetries: $0)?.delay }

        XCTAssertEqual(delays, [30, 60, 120, 240, 300, 300])
    }

    /// An ended window is the more urgent signal: a boundary further ahead must
    /// not keep the app from catching up on the one that already passed.
    func testEndedWindowWinsOverAComingBoundary() {
        XCTAssertEqual(
            self.wake([
                self.status(.claude, resetsAt: self.now.addingTimeInterval(-1)),
                self.status(.grok, resetsAt: self.now.addingTimeInterval(60)),
            ]),
            .staleWindow(delay: UsageResetBoundarySchedule.grace))
    }

    func testHoldsEndedWindowSeesOnlyProvidersWithNumbers() {
        XCTAssertTrue(UsageResetBoundarySchedule.holdsEndedWindow(
            statuses: [self.status(.claude, resetsAt: self.now.addingTimeInterval(-1))],
            now: self.now))
        XCTAssertFalse(UsageResetBoundarySchedule.holdsEndedWindow(
            statuses: [self.status(.claude, resetsAt: self.now.addingTimeInterval(1))],
            now: self.now))
        XCTAssertFalse(UsageResetBoundarySchedule.holdsEndedWindow(
            statuses: [self.status(.claude, resetsAt: nil, hasUsage: false, errorMessage: "boom")],
            now: self.now))
    }

    // MARK: - Bookkeeping

    func testRememberKeepsTheSetBoundedAndDropsTheOldest() {
        var attempted: Set<Date> = []
        let total = UsageResetBoundarySchedule.attemptedBoundaryLimit + 10
        for index in 0..<total {
            UsageResetBoundarySchedule.remember(
                self.now.addingTimeInterval(Double(index) * 60),
                in: &attempted)
        }

        XCTAssertEqual(attempted.count, UsageResetBoundarySchedule.attemptedBoundaryLimit)
        XCTAssertFalse(attempted.contains(self.now))
        XCTAssertTrue(attempted.contains(self.now.addingTimeInterval(Double(total - 1) * 60)))
    }
}
