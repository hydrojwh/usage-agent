import XCTest
@testable import UsageCore

final class UsageWidgetSnapshotTests: XCTestCase {
    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = UsageWidgetSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 100),
            entries: [
                UsageWidgetSnapshot.ProviderEntry(
                    provider: .claude,
                    remainingPercent: 82.4,
                    windowLabel: "5-hour window",
                    fetchedAt: Date(timeIntervalSinceReferenceDate: 90)),
                UsageWidgetSnapshot.ProviderEntry(provider: .codex, remainingPercent: nil, errorMessage: "Not signed in"),
            ])

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageWidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.schemaVersion, UsageWidgetSnapshot.currentSchemaVersion)
        XCTAssertFalse(decoded.isSample)
    }

    func testInitFromStatusesKeepsCanonicalOrderAndHeadlinePercent() {
        let statuses = [
            self.status(.grok, remaining: 91.4),
            self.status(.claude, remaining: 82.1),
            self.status(.codex, remaining: 62.6),
        ]

        let snapshot = UsageWidgetSnapshot(statuses: statuses)

        XCTAssertEqual(snapshot.entries.map(\.provider), UsageProviderKind.allCases)
        XCTAssertEqual(snapshot.entry(for: .claude)?.remainingPercent, 82.1)
        XCTAssertEqual(snapshot.entry(for: .codex)?.remainingPercent, 62.6)
        XCTAssertEqual(snapshot.entry(for: .grok)?.remainingPercent, 91.4)
        XCTAssertEqual(snapshot.entry(for: .claude)?.windowLabel, "5-hour window")
    }

    func testInitFromStatusesKeepsLastGoodValueOverTransientError() {
        var claude = self.status(.claude, remaining: 82)
        claude.errorMessage = "Provider temporarily unavailable"

        let snapshot = UsageWidgetSnapshot(statuses: [claude])

        XCTAssertEqual(snapshot.entry(for: .claude)?.remainingPercent, 82)
        XCTAssertNil(snapshot.entry(for: .claude)?.errorMessage)
    }

    func testFreshnessUsesOldestDisplayedProviderAcquisitionTime() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let older = Date(timeIntervalSinceReferenceDate: 100)
        let newer = Date(timeIntervalSinceReferenceDate: 200)
        let snapshot = UsageWidgetSnapshot(
            generatedAt: generatedAt,
            entries: [
                .init(provider: .claude, remainingPercent: 82, fetchedAt: newer),
                .init(provider: .codex, remainingPercent: 63, fetchedAt: older),
                .init(
                    provider: .grok,
                    remainingPercent: nil,
                    fetchedAt: Date(timeIntervalSinceReferenceDate: 50)),
            ])

        XCTAssertEqual(snapshot.freshnessReferenceDate, older)
        XCTAssertEqual(snapshot.freshnessDate(for: .claude), newer)
        XCTAssertEqual(snapshot.freshnessDate(for: .codex), older)
        XCTAssertNil(snapshot.freshnessDate(for: .grok))
    }

    func testFreshnessFallsBackToSnapshotGenerationForLegacyEntries() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 300)
        let snapshot = UsageWidgetSnapshot(
            generatedAt: generatedAt,
            entries: [.init(provider: .claude, remainingPercent: 82)])

        XCTAssertEqual(snapshot.freshnessReferenceDate, generatedAt)
        XCTAssertEqual(snapshot.freshnessDate(for: .claude), generatedAt)
    }

    func testFreshnessIsMissingWhenNoProviderHasUsage() {
        let snapshot = UsageWidgetSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 300),
            entries: [
                .init(provider: .claude, remainingPercent: nil, errorMessage: "Unavailable"),
                .init(provider: .codex, remainingPercent: nil),
            ])

        XCTAssertNil(snapshot.freshnessReferenceDate)
    }

    func testEntriesWithoutUsageExposeErrorAndNoPercent() {
        let failed = ProviderUsageStatus(provider: .grok, errorMessage: "Run `grok login`, then refresh.")
        let untouched = ProviderUsageStatus(provider: .codex)

        let snapshot = UsageWidgetSnapshot(statuses: [failed, untouched])

        XCTAssertNil(snapshot.entry(for: .grok)?.remainingPercent)
        XCTAssertNotNil(snapshot.entry(for: .grok)?.errorMessage)
        XCTAssertNil(snapshot.entry(for: .codex)?.remainingPercent)
        XCTAssertNil(snapshot.entry(for: .codex)?.errorMessage)
    }

    func testSnapshotBoundsStoredErrorText() {
        let failed = ProviderUsageStatus(
            provider: .grok,
            errorMessage: String(repeating: "x", count: UsageErrorText.maximumLength + 50))

        let snapshot = UsageWidgetSnapshot(statuses: [failed])
        let message = snapshot.entry(for: .grok)?.errorMessage

        XCTAssertEqual(message?.count, UsageErrorText.maximumLength)
        XCTAssertTrue(message?.hasSuffix("…") == true)
    }

    func testInitFromStatusesToleratesDuplicateProviders() {
        let first = self.status(.claude, remaining: 10)
        let second = self.status(.claude, remaining: 90)

        let snapshot = UsageWidgetSnapshot(statuses: [first, second])

        XCTAssertEqual(snapshot.entries.count, UsageProviderKind.allCases.count)
        XCTAssertEqual(snapshot.entry(for: .claude)?.remainingPercent, 90)
    }

    func testPlaceholderCoversAllThreeProviders() {
        let placeholder = UsageWidgetSnapshot.placeholder

        XCTAssertEqual(placeholder.entries.map(\.provider), UsageProviderKind.allCases)
        XCTAssertTrue(placeholder.entries.allSatisfy { $0.remainingPercent != nil })
        XCTAssertTrue(placeholder.isSample)
    }

    func testReviewerSnapshotRoundTripPreservesVisibleSampleMarker() throws {
        let snapshot = UsageWidgetSnapshot(
            statuses: [self.status(.claude, remaining: 82)],
            isSample: true)

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(UsageWidgetSnapshot.self, from: data)

        XCTAssertTrue(decoded.isSample)
        XCTAssertEqual(decoded.schemaVersion, 2)
    }

    func testLegacySnapshotWithoutSampleMarkerDefaultsToLiveData() throws {
        let legacyJSON = """
        {
          "schemaVersion": 1,
          "generatedAt": 100,
          "entries": []
        }
        """
        let decoded = try JSONDecoder().decode(
            UsageWidgetSnapshot.self,
            from: Data(legacyJSON.utf8))

        XCTAssertFalse(decoded.isSample)
        XCTAssertEqual(decoded.schemaVersion, 1)
    }

    func testStoreSaveAndLoadRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-snapshot-tests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let snapshot = UsageWidgetSnapshot.placeholder
        try UsageWidgetSnapshotStore.save(snapshot, to: url)

        XCTAssertEqual(UsageWidgetSnapshotStore.load(from: url), snapshot)
    }

    func testStoreSaveWithoutURLFailsLoudly() {
        XCTAssertThrowsError(try UsageWidgetSnapshotStore.save(.placeholder, to: nil)) { error in
            XCTAssertTrue(error is UsageWidgetSnapshotStoreError)
        }
    }

    func testStoreLoadMissingFileReturnsNil() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("usage-snapshot-missing-\(UUID().uuidString).json")

        XCTAssertNil(UsageWidgetSnapshotStore.load(from: missing))
        XCTAssertNil(UsageWidgetSnapshotStore.load(from: nil))
    }

    func testAppGroupIDRejectsUnexpandedOrMalformedValues() {
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID(nil))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID(""))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID("$(USAGE_APP_GROUP_ID)"))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID(".com.example.usageagents"))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID("group.com.example.usageagents"))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID("SHORT.com.example.usageagents"))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID("abcdefghij.com.example.usageagents"))
        XCTAssertNil(UsageWidgetSnapshotStore.validatedGroupID("  "))
        XCTAssertEqual(
            UsageWidgetSnapshotStore.validatedGroupID("XXXXXXXXXX.com.example.usageagents"),
            "XXXXXXXXXX.com.example.usageagents")
        XCTAssertEqual(
            UsageWidgetSnapshotStore.validatedGroupID("XXXXXXXXXX.com.example.usageagents"),
            "XXXXXXXXXX.com.example.usageagents")
    }

    private func status(_ provider: UsageProviderKind, remaining: Double) -> ProviderUsageStatus {
        ProviderUsageStatus(
            provider: provider,
            usage: ProviderUsage(
                provider: provider,
                metrics: [UsageMetric(
                    id: "primary",
                    label: "5-hour window",
                    usedPercent: 100 - remaining)],
                sourceLabel: "Test"))
    }
}
