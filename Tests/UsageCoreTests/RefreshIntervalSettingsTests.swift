import XCTest
@testable import UsageCore

final class RefreshIntervalSettingsTests: XCTestCase {
    func testStepsClampToSliderRange() {
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 5), 1)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 10), 1)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 14), 1)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 15), 2)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 300), 30)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: 3610), 360)
        XCTAssertEqual(UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: -100), 1)
    }

    func testSecondsAlwaysLandOnTenSecondSteps() {
        for steps in [1, 2, 30, 59, 60, 359, 360] {
            let seconds = UsageDisplaySettings.refreshIntervalSeconds(forSteps: steps)
            XCTAssertEqual(seconds.truncatingRemainder(dividingBy: 10), 0)
        }
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalSeconds(forSteps: 30), 300)
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalSeconds(forSteps: 360), 3600)
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalSeconds(forSteps: 9_999), 3600)
    }

    func testLabelsUseCompactUnits() {
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 1), "10s")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 6), "1m")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 33), "5m 30s")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 30), "5m")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 360), "1h")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 90), "15m")
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalLabel(forSteps: 359), "59m 50s")
    }

    func testDefaultRemainsFiveMinutes() {
        XCTAssertEqual(UsageDisplaySettings.refreshIntervalDefaultSeconds, 300)
        XCTAssertEqual(
            UsageDisplaySettings.refreshIntervalLabel(
                forSteps: UsageDisplaySettings.clampedRefreshIntervalSteps(
                    forSeconds: UsageDisplaySettings.refreshIntervalDefaultSeconds)),
            "5m")
    }
}
