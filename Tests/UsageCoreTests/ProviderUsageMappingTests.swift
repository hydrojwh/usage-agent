import XCTest
@testable import UsageCore

final class ProviderUsageMappingTests: XCTestCase {
    func testGenericProviderMessagesDoNotIncludeUntrustedDetails() {
        let secretLikeDetail = "raw stderr private-home/example/.config/token-value"

        for provider in UsageProviderKind.allCases {
            let message = UsageErrorText.genericProviderMessage(for: provider)
            XCTAssertFalse(message.contains(secretLikeDetail))
            XCTAssertTrue(message.contains(provider.displayName))
        }
    }

    func testTrustedCollectorMessageBoundsOwnedText() {
        let detail = String(repeating: "d", count: 300)
        let message = UsageErrorText.trustedCollectorMessage(
            detail: detail,
            suggestion: "Refresh again later.")

        XCTAssertNotNil(message)
        XCTAssertLessThanOrEqual(message?.count ?? .max, UsageErrorText.maximumLength)
    }

    func testRefreshHistorySeparatesAttemptsFromSuccesses() {
        let first = Date(timeIntervalSinceReferenceDate: 100)
        let second = Date(timeIntervalSinceReferenceDate: 200)
        var history = UsageRefreshHistory()

        history.recordAttempt(at: first, hadSuccessfulProvider: true)
        history.recordAttempt(at: second, hadSuccessfulProvider: false)

        XCTAssertEqual(history.lastAttemptedAt, second)
        XCTAssertEqual(history.lastSuccessfulAt, first)
    }

    func testAccountIdentifiersAreHiddenByDefault() {
        XCTAssertFalse(UsageDisplaySettings.showsAccountIdentifiersDefault)
        XCTAssertEqual(
            UsageDisplaySettings.identityText(
                accountLabel: "person@example.com",
                sourceLabel: "Claude CLI",
                showsAccountIdentifiers: false),
            "Claude CLI")
    }

    func testClaudeVisibilityDefaultsOnAndPersistsExplicitOff() {
        let suiteName = "UsageDisplaySettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(UsageDisplaySettings.showsClaude(defaults: defaults))

        defaults.set(false, forKey: UsageDisplaySettings.showsClaudeKey)
        XCTAssertFalse(UsageDisplaySettings.showsClaude(defaults: defaults))
    }

    func testAccountIdentifiersCanBeShownWithoutChangingSourceLabel() {
        XCTAssertEqual(
            UsageDisplaySettings.identityText(
                accountLabel: " person@example.com ",
                sourceLabel: "Claude CLI",
                showsAccountIdentifiers: true),
            "person@example.com · Claude CLI")
        XCTAssertEqual(
            UsageDisplaySettings.identityText(
                accountLabel: nil,
                sourceLabel: "Claude CLI",
                showsAccountIdentifiers: true),
            "Claude CLI")
    }

    func testVisibleProvidersPreserveCanonicalOrderAndNeverBecomeEmpty() {
        XCTAssertEqual(
            UsageDisplaySettings.visibleProviders(
                showsClaude: true,
                showsCodex: false,
                showsGrok: true),
            [.claude, .grok])
        XCTAssertEqual(
            UsageDisplaySettings.visibleProviders(
                showsClaude: false,
                showsCodex: false,
                showsGrok: false),
            [.claude])
    }

    func testErrorTextIsTrimmedAndBounded() {
        XCTAssertEqual(UsageErrorText.sanitized("  Try again.  "), "Try again.")
        XCTAssertEqual(UsageErrorText.sanitized("abcdef", maximumLength: 5), "abcd…")
        XCTAssertEqual(UsageErrorText.sanitized("abcdef", maximumLength: 1), "…")
        XCTAssertEqual(UsageErrorText.sanitized("abcdef", maximumLength: 0), "")
    }

    func testResetDescriptionAddsMissingSpaceAfterResetWord() {
        XCTAssertEqual(UsageResetDescriptionFormatter.displayText("reset5am"), "reset 5am")
        XCTAssertEqual(UsageResetDescriptionFormatter.displayText("Resets5am"), "Resets 5am")
    }

    func testResetDescriptionPreservesExistingSpacingAndPrefixesBareTime() {
        XCTAssertEqual(UsageResetDescriptionFormatter.displayText("Resets at 5am"), "Resets at 5am")
        XCTAssertEqual(UsageResetDescriptionFormatter.displayText("5am"), "Resets 5am")
        XCTAssertNil(UsageResetDescriptionFormatter.displayText("  "))
    }

    func testResetDisplayCanSwitchToTimeRemaining() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            UsageResetDescriptionFormatter.displayText(
                resetsAt: now.addingTimeInterval(3 * 3_600 + 5 * 60),
                resetDescription: nil,
                mode: .remaining,
                now: now),
            "3h 5m left")
        XCTAssertEqual(
            UsageResetDescriptionFormatter.displayText(
                resetsAt: now.addingTimeInterval(-1),
                resetDescription: nil,
                mode: .remaining,
                now: now),
            "Reset due")
    }

    func testResetTimeIncludesMonthDayWeekdayAndClock() throws {
        let reset = Date(timeIntervalSince1970: 1_787_793_900)
        let text = try XCTUnwrap(UsageResetDescriptionFormatter.displayText(
            resetsAt: reset,
            resetDescription: nil,
            mode: .resetTime,
            now: reset.addingTimeInterval(-60)))

        XCTAssertTrue(text.contains(reset.formatted(.dateTime.month(.abbreviated).day())))
        XCTAssertTrue(text.contains(reset.formatted(.dateTime.weekday(.abbreviated))))
        XCTAssertTrue(text.contains(reset.formatted(.dateTime.hour().minute())))
    }

    func testResetTimeTreatsAPastBoundaryAsDue() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000)

        XCTAssertEqual(
            UsageResetDescriptionFormatter.displayText(
                resetsAt: now.addingTimeInterval(-1),
                resetDescription: "Resets 8:19pm",
                mode: .resetTime,
                now: now),
            "Reset due")
        XCTAssertEqual(
            UsageResetDescriptionFormatter.displayText(
                resetsAt: now,
                resetDescription: nil,
                mode: .resetTime,
                now: now),
            "Reset due")
    }

    func testResetDisplayFallsBackToProviderDescriptionWhenDateIsMissing() {
        XCTAssertEqual(
            UsageResetDescriptionFormatter.displayText(
                resetsAt: nil,
                resetDescription: "reset5am",
                mode: .remaining),
            "reset 5am")
    }

    func testGrokCreditsMapsProviderFieldsAndReset() throws {
        let reset = Date(timeIntervalSinceReferenceDate: 500)

        let usage = try XCTUnwrap(ProviderUsage.grokCredits(
            usedPercent: 28.5,
            resetsAt: reset,
            accountLabel: "Account",
            fetchedAt: Date(timeIntervalSinceReferenceDate: 400)))

        XCTAssertEqual(usage.provider, .grok)
        XCTAssertEqual(usage.accountLabel, "Account")
        XCTAssertEqual(usage.sourceLabel, "Grok CLI billing")
        XCTAssertEqual(usage.headlineMetric?.id, "credits")
        XCTAssertEqual(usage.headlineMetric?.label, "Credits")
        XCTAssertEqual(usage.headlineMetric?.remainingPercent, 71.5)
        XCTAssertEqual(usage.headlineMetric?.resetsAt, reset)
    }

    func testGrokCreditsDoesNotInventMissingOrNonFiniteUsage() {
        XCTAssertNil(ProviderUsage.grokCredits(
            usedPercent: nil,
            resetsAt: Date(),
            accountLabel: nil))
        XCTAssertNil(ProviderUsage.grokCredits(
            usedPercent: .nan,
            resetsAt: Date(),
            accountLabel: nil))
    }
}
