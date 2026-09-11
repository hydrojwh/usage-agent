import XCTest
@testable import UsageCore

final class MenuBarSummaryTests: XCTestCase {
    func testSummaryKeepsStableProviderOrder() {
        let statuses = [
            self.status(.grok, remaining: 91.4),
            self.status(.claude, remaining: 82.1),
            self.status(.codex, remaining: 62.6),
        ]

        XCTAssertEqual(MenuBarSummary.text(for: statuses), "Cl82 Cx63 Gk91")

        let items = MenuBarSummary.items(for: statuses)
        XCTAssertEqual(items.map(\.provider), UsageProviderKind.allCases)
        XCTAssertEqual(items.map(\.value), ["82", "63", "91"])
    }

    func testSummaryUsesDashWhenProviderHasNoData() {
        let statuses = [
            self.status(.claude, remaining: 50),
            ProviderUsageStatus(provider: .codex, errorMessage: "Not signed in"),
        ]

        XCTAssertEqual(MenuBarSummary.text(for: statuses), "Cl50 Cx— Gk—")
    }

    func testSummaryValueSupportsIconBasedMenuBarLabel() {
        let statuses = [self.status(.codex, remaining: 62.6)]

        XCTAssertEqual(MenuBarSummary.value(for: .codex, in: statuses), "63")
        XCTAssertEqual(MenuBarSummary.value(for: .claude, in: statuses), "—")
    }

    func testSummaryCanLimitVisibleProvidersInCanonicalSelectionOrder() {
        let statuses = [
            self.status(.claude, remaining: 82.1),
            self.status(.codex, remaining: 62.6),
            self.status(.grok, remaining: 91.4),
        ]
        let providers: [UsageProviderKind] = [.claude, .grok]

        let items = MenuBarSummary.items(for: statuses, providers: providers)
        XCTAssertEqual(items.map(\.provider), providers)
        XCTAssertEqual(items.map(\.value), ["82", "91"])
        XCTAssertEqual(
            MenuBarSummary.accessibilityText(for: statuses, providers: providers),
            "Claude 82 percent remaining, Grok 91 percent remaining")
    }

    func testAccessibilitySummaryToleratesDuplicateProviders() {
        let statuses = [
            self.status(.claude, remaining: 10),
            self.status(.claude, remaining: 90),
        ]

        XCTAssertEqual(
            MenuBarSummary.accessibilityText(for: statuses, providers: [.claude]),
            "Claude 90 percent remaining")
    }

    func testMetricClampsDisplayRange() {
        let over = UsageMetric(id: "over", label: "Over", usedPercent: 130)
        let under = UsageMetric(id: "under", label: "Under", usedPercent: -20)

        XCTAssertEqual(over.remainingPercent, 0)
        XCTAssertEqual(under.remainingPercent, 100)
    }

    private func status(_ provider: UsageProviderKind, remaining: Double) -> ProviderUsageStatus {
        ProviderUsageStatus(
            provider: provider,
            usage: ProviderUsage(
                provider: provider,
                metrics: [UsageMetric(
                    id: "primary",
                    label: "Primary",
                    usedPercent: 100 - remaining)],
                sourceLabel: "Test"))
    }
}
