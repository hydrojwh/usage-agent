import Foundation
import XCTest
import UsageCore

final class AppInfoTests: XCTestCase {
    func testDisplayVersionPairsMarketingAndBuild() {
        XCTAssertEqual(
            AppInfo.displayVersion(marketingVersion: "2.0.33", buildVersion: "35"),
            "v2.0.33 (35)")
    }

    func testIssueReportCarriesAppAndOSDetails() throws {
        let url = AppInfo.issueReportURL(
            appName: "Usage Agents",
            displayVersion: "v2.0.33 (35)",
            operatingSystemVersion: "Version 26.0 (Build 25A123)")

        XCTAssertEqual(url.scheme, "mailto")
        XCTAssertEqual(url.path, AppInfo.supportEmail)

        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        let subject = try XCTUnwrap(items.first(where: { $0.name == "subject" })?.value)
        let body = try XCTUnwrap(items.first(where: { $0.name == "body" })?.value)

        XCTAssertTrue(subject.contains("Usage Agents issue"))
        XCTAssertTrue(subject.contains("v2.0.33 (35)"))
        XCTAssertTrue(body.contains("App: Usage Agents v2.0.33 (35)"))
        XCTAssertTrue(body.contains("macOS: Version 26.0 (Build 25A123)"))
    }

    func testMarketingVersionLabelHidesEmptyAndTrimsWhitespace() {
        final class MissingVersionBundle: Bundle {
            override func object(forInfoDictionaryKey key: String) -> Any? { nil }
        }
        final class WhitespaceVersionBundle: Bundle {
            override func object(forInfoDictionaryKey key: String) -> Any? { "  \n" }
        }
        final class PaddedVersionBundle: Bundle {
            override func object(forInfoDictionaryKey key: String) -> Any? { " 2.0.34 " }
        }

        XCTAssertNil(AppInfo.marketingVersionLabel(bundle: MissingVersionBundle()))
        XCTAssertNil(AppInfo.marketingVersionLabel(bundle: WhitespaceVersionBundle()))
        XCTAssertEqual(AppInfo.marketingVersionLabel(bundle: PaddedVersionBundle()), "2.0.34")
        XCTAssertEqual(AppInfo.marketingVersion(bundle: MissingVersionBundle()), "0.0.0")
    }

    // The `?? fallback` branches in issueReportURL are defensive only: the
    // mailto string is a compile-time constant and query items are
    // percent-encoded, so no input in this API's parameter space can force
    // them. This test pins the success path's URL shape, not the fallback.
    func testIssueReportAlwaysProducesAMailtoURL() {
        let url = AppInfo.issueReportURL(
            appName: "Usage Agents",
            displayVersion: "v2.0.33 (35)",
            operatingSystemVersion: "macOS")
        XCTAssertEqual(url.scheme, "mailto")
    }
}
