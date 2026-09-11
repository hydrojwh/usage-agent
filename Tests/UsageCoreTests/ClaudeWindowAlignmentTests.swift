import XCTest
@testable import UsageCore

final class ClaudeWindowAlignmentTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        self.calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute))!
    }

    func testScheduleUsesContinuousFiveHourIntervalsAcrossMidnight() {
        let anchor = self.date(2026, 8, 26, 6, 0)
        let schedule = ClaudeWindowAlignmentSchedule(anchor: anchor)

        XCTAssertEqual(schedule.slot(index: 0).dueAt, self.date(2026, 8, 26, 6, 0))
        XCTAssertEqual(schedule.slot(index: 1).dueAt, self.date(2026, 8, 26, 11, 0))
        XCTAssertEqual(schedule.slot(index: 2).dueAt, self.date(2026, 8, 26, 16, 0))
        XCTAssertEqual(schedule.slot(index: 3).dueAt, self.date(2026, 8, 26, 21, 0))
        XCTAssertEqual(schedule.slot(index: 4).dueAt, self.date(2026, 8, 27, 2, 0))
        XCTAssertEqual(schedule.slot(index: 5).dueAt, self.date(2026, 8, 27, 7, 0))
    }

    func testDueSlotAllowsSmallExecutionDelay() throws {
        let anchor = self.date(2026, 8, 26, 6, 0)
        let schedule = ClaudeWindowAlignmentSchedule(anchor: anchor)

        let slot = try XCTUnwrap(schedule.dueSlot(
            at: self.date(2026, 8, 26, 11, 6),
            gracePeriod: 8 * 60))

        XCTAssertEqual(slot.index, 1)
        XCTAssertEqual(slot.dueAt, self.date(2026, 8, 26, 11, 0))
    }

    func testMissedSlotIsNotRunLate() {
        let anchor = self.date(2026, 8, 26, 6, 0)
        let schedule = ClaudeWindowAlignmentSchedule(anchor: anchor)

        XCTAssertNil(schedule.dueSlot(
            at: self.date(2026, 8, 26, 11, 9),
            gracePeriod: 8 * 60))
        XCTAssertEqual(
            schedule.nextSlot(after: self.date(2026, 8, 26, 11, 9)).dueAt,
            self.date(2026, 8, 26, 16, 0))
    }

    func testNextSlotBeforeAnchorIsTheAnchor() {
        let anchor = self.date(2026, 8, 26, 6, 0)
        let schedule = ClaudeWindowAlignmentSchedule(anchor: anchor)

        XCTAssertEqual(
            schedule.nextSlot(after: self.date(2026, 8, 26, 5, 0)).dueAt,
            anchor)
    }

    func testChangingClockTimeKeepsReferenceDay() {
        let reference = self.date(2026, 8, 26, 20, 30)
        let selected = self.date(2001, 1, 1, 7, 45)

        XCTAssertEqual(
            ClaudeWindowAlignmentSettings.anchorDate(
                matching: reference,
                timeFrom: selected,
                calendar: self.calendar),
            self.date(2026, 8, 26, 7, 45))
    }

    func testDurationIsClampedToSliderRange() {
        XCTAssertEqual(MacAwakeSettings.defaultActiveDurationHours, 0)
        XCTAssertEqual(MacAwakeSettings.clampedDurationHours(-2), 0)
        XCTAssertEqual(MacAwakeSettings.clampedDurationHours(0), 0)
        XCTAssertEqual(MacAwakeSettings.clampedDurationHours(12), 12)
        XCTAssertEqual(MacAwakeSettings.clampedDurationHours(99), 24)
    }

    func testMacAwakePreventsDisplayAndSystemIdleSleep() {
        let options = MacAwakeSettings.activityOptions

        XCTAssertTrue(options.contains(.idleDisplaySleepDisabled))
        XCTAssertTrue(options.contains(.idleSystemSleepDisabled))
    }

    func testAnchorHourIsClampedAndAlwaysUsesWholeHour() {
        let reference = self.date(2026, 8, 26, 20, 30)

        XCTAssertEqual(
            ClaudeWindowAlignmentSettings.anchorDate(
                matching: reference,
                hour: -3,
                minute: 45,
                calendar: self.calendar),
            self.date(2026, 8, 26, 0, 45))
        XCTAssertEqual(
            ClaudeWindowAlignmentSettings.anchorDate(
                matching: reference,
                hour: 99,
                minute: 0,
                calendar: self.calendar),
            self.date(2026, 8, 26, 23, 0))
    }

    func testAnchorAndMacAwakeUseIndependentTimingContracts() {
        XCTAssertEqual(ClaudeWindowAlignmentSettings.interval, 5 * 60 * 60)
        XCTAssertEqual(MacAwakeSettings.defaultActiveDurationHours, 0)
    }

    func testDistributionPolicyResolvesPersistedAnchorState() {
#if USAGE_APP_STORE
        XCTAssertFalse(UsageDistributionPolicy.supportsClaudeWindowAnchor)
        XCTAssertFalse(UsageDistributionPolicy.resolvedClaudeWindowAnchorEnabled(storedValue: true))
#else
        XCTAssertTrue(UsageDistributionPolicy.supportsClaudeWindowAnchor)
        XCTAssertTrue(UsageDistributionPolicy.resolvedClaudeWindowAnchorEnabled(storedValue: true))
#endif
        XCTAssertFalse(UsageDistributionPolicy.resolvedClaudeWindowAnchorEnabled(storedValue: false))
    }

    func testHeadlessCommandDisablesToolsCustomizationsAndPersistence() {
        let arguments = ClaudeWindowAnchorCommand.arguments

        XCTAssertTrue(arguments.contains("--safe-mode"))
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("--disable-slash-commands"))
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--tools")! + 1], "")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--max-turns")! + 1], "1")
        XCTAssertEqual(arguments[arguments.firstIndex(of: "--model")! + 1], "haiku")
        XCTAssertEqual(arguments.last, ClaudeWindowAnchorCommand.prompt)
    }

    func testHeadlessCommandRemovesPaidAndCopiedCredentialOverrides() {
        let environment = [
            "HOME": "/safe/home",
            "PATH": "/safe/bin",
            "ANTHROPIC_API_KEY": "must-not-survive",
            "ANTHROPIC_AUTH_TOKEN": "must-not-survive",
            "ANTHROPIC_BASE_URL": "https://gateway.invalid",
            "CLAUDE_CODE_OAUTH_TOKEN": "must-not-survive",
            "CLAUDE_CODE_USE_BEDROCK": "1",
        ]

        let sanitized = ClaudeWindowAnchorCommand.sanitizedEnvironment(environment)

        XCTAssertEqual(sanitized["HOME"], "/safe/home")
        XCTAssertEqual(sanitized["PATH"], "/safe/bin")
        XCTAssertNil(sanitized["ANTHROPIC_API_KEY"])
        XCTAssertNil(sanitized["ANTHROPIC_AUTH_TOKEN"])
        XCTAssertNil(sanitized["ANTHROPIC_BASE_URL"])
        XCTAssertNil(sanitized["CLAUDE_CODE_OAUTH_TOKEN"])
        XCTAssertNil(sanitized["CLAUDE_CODE_USE_BEDROCK"])
    }
}
