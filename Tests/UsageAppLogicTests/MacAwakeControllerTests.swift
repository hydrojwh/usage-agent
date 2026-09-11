import Foundation
import XCTest
@testable import UsageCore

@MainActor
final class MacAwakeControllerTests: XCTestCase {
    func testEnableAndDisableOwnOneActivityToken() {
        let activityManager = RecordingActivityManager()
        let controller = MacAwakeController(activityManager: activityManager)
        controller.start()

        controller.setEnabled(true)

        XCTAssertTrue(controller.isEnabled)
        XCTAssertEqual(activityManager.beginCount, 1)
        XCTAssertTrue(activityManager.options?.contains(.idleDisplaySleepDisabled) == true)
        XCTAssertTrue(activityManager.options?.contains(.idleSystemSleepDisabled) == true)

        controller.setEnabled(false)

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(activityManager.endCount, 1)
    }

    func testStopReleasesAnActiveActivity() {
        let activityManager = RecordingActivityManager()
        let controller = MacAwakeController(activityManager: activityManager)
        controller.start()
        controller.setEnabled(true)

        controller.stop()

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(activityManager.endCount, 1)
    }

    func testFiniteDurationAutomaticallyReleasesActivity() async {
        let activityManager = RecordingActivityManager()
        let controller = MacAwakeController(
            activityManager: activityManager,
            sleep: { _ in })
        controller.start()
        controller.setEnabled(true)

        controller.setActiveDurationHours(1)
        for _ in 0..<5 {
            await Task.yield()
        }

        XCTAssertFalse(controller.isEnabled)
        XCTAssertEqual(activityManager.endCount, 1)
    }
}

@MainActor
private final class RecordingActivityManager: MacAwakeActivityManaging {
    private final class Token: NSObject {}

    private(set) var beginCount = 0
    private(set) var endCount = 0
    private(set) var options: ProcessInfo.ActivityOptions?

    func begin(options: ProcessInfo.ActivityOptions, reason: String) -> NSObjectProtocol {
        self.beginCount += 1
        self.options = options
        return Token()
    }

    func end(_ activity: NSObjectProtocol) {
        self.endCount += 1
    }
}
