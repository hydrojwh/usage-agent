import XCTest
@testable import UsageCore

final class ClaudeScopedWindowLabelTests: XCTestCase {
    // MARK: - displayLabel

    func testRewritesScopeSuffixIntoAWindowName() {
        XCTAssertEqual(ClaudeScopedWindowLabel.displayLabel(title: "Fable only"), "Fable weekly")
    }

    func testKeepsTitlesThatDoNotCarryTheScopeSuffix() {
        XCTAssertEqual(ClaudeScopedWindowLabel.displayLabel(title: "Weekly"), "Weekly")
        XCTAssertEqual(ClaudeScopedWindowLabel.displayLabel(title: "Opus weekly"), "Opus weekly")
    }

    func testDoesNotTreatAModelNamedOnlySomethingAsScoped() {
        // "only" must be a trailing scope marker, not a substring anywhere.
        XCTAssertEqual(ClaudeScopedWindowLabel.displayLabel(title: "Only Model"), "Only Model")
    }

    func testHandlesSurroundingWhitespace() {
        XCTAssertEqual(ClaudeScopedWindowLabel.displayLabel(title: "  Fable only  "), "Fable weekly")
    }

    // MARK: - duplicatesPrimaryWindow

    func testKeepsScopedWindowsWhenThereIsNoPrimaryModelRow() {
        XCTAssertFalse(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Opus only",
            hasPrimaryModelWindow: false))
    }

    func testDropsOpusScopeWhenThePrimaryModelRowExists() {
        XCTAssertTrue(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Opus only",
            hasPrimaryModelWindow: true))
    }

    func testDropsSonnetScopeBecauseThePrimaryRowMayCarrySonnetData() {
        // Upstream fills the dedicated window with `sevenDaySonnet ?? sevenDayOpus`,
        // so a Sonnet scoped window can duplicate it.
        XCTAssertTrue(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Sonnet only",
            hasPrimaryModelWindow: true))
    }

    func testMatchesVersionedModelNames() {
        // The regression this replaced: identifiers carry a version, so suffix
        // matching on the id missed `claude-opus-5` entirely.
        XCTAssertTrue(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Claude Opus 5 only",
            hasPrimaryModelWindow: true))
        XCTAssertTrue(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Sonnet 4.6 only",
            hasPrimaryModelWindow: true))
    }

    func testKeepsUnrelatedModelScopes() {
        XCTAssertFalse(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Fable only",
            hasPrimaryModelWindow: true))
        XCTAssertFalse(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "Haiku only",
            hasPrimaryModelWindow: true))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(ClaudeScopedWindowLabel.duplicatesPrimaryWindow(
            title: "OPUS only",
            hasPrimaryModelWindow: true))
    }
}
