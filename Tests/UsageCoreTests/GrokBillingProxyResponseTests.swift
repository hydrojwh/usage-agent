import XCTest
@testable import UsageCore

final class GrokBillingProxyResponseTests: XCTestCase {
    func testVerifiedEmptyUnifiedPeriodMapsToZeroUsed() throws {
        let snapshot = try GrokBillingProxyResponse.parse(Data(Self.emptyUnifiedResponse.utf8))

        XCTAssertEqual(GrokBillingProxyResponse.policyVersion, 1)
        XCTAssertEqual(snapshot.usedPercent, 0)
        XCTAssertEqual(snapshot.source, .verifiedEmptyUnifiedPeriod)
        XCTAssertEqual(
            snapshot.resetsAt,
            ISO8601DateFormatter().date(from: "2026-09-04T01:04:42Z"))
    }

    func testReportedPercentRemainsAuthoritative() throws {
        let snapshot = try GrokBillingProxyResponse.parse(Data(#"""
        {
          "config": {
            "creditUsagePercent": 28.5,
            "currentPeriod": {
              "start": "2026-08-28T01:04:42Z",
              "end": "2026-09-04T01:04:42Z"
            }
          }
        }
        """#.utf8))

        XCTAssertEqual(snapshot.usedPercent, 28.5)
        XCTAssertEqual(snapshot.source, .reportedPercent)
    }

    func testLegacyPositiveCapStillMapsRatio() throws {
        let snapshot = try GrokBillingProxyResponse.parse(Data(#"""
        {
          "config": {
            "onDemandCap": {"val": 400},
            "onDemandUsed": {"val": 100},
            "billingPeriodEnd": "2026-09-04T01:04:42Z"
          }
        }
        """#.utf8))

        XCTAssertEqual(snapshot.usedPercent, 25)
        XCTAssertEqual(snapshot.source, .onDemandRatio)
    }

    func testMissingUnifiedEvidenceDoesNotInventZero() {
        for mutation in [
            Self.emptyUnifiedResponse.replacingOccurrences(
                of: #""isUnifiedBillingUser": true,"#,
                with: #""isUnifiedBillingUser": false,"#),
            Self.emptyUnifiedResponse.replacingOccurrences(
                of: #""prepaidBalance": {"val": 0},"#,
                with: ""),
            Self.emptyUnifiedResponse.replacingOccurrences(
                of: #""onDemandUsed": {"val": 0},"#,
                with: #""onDemandUsed": {"val": 1},"#),
            Self.emptyUnifiedResponse.replacingOccurrences(
                of: #""topUpMethod": "manual""#,
                with: #""topUpMethod": "manual", "productUsage": [{}]"#),
        ] {
            XCTAssertThrowsError(try GrokBillingProxyResponse.parse(Data(mutation.utf8))) {
                XCTAssertEqual($0 as? GrokBillingProxyResponseError, .usageUnavailable)
            }
        }
    }

    func testMalformedPeriodAndNonFiniteUsageFailClosed() {
        let reversedPeriod = Self.emptyUnifiedResponse.replacingOccurrences(
            of: "2026-09-04T01:04:42Z",
            with: "2026-08-20T01:04:42Z")
        XCTAssertThrowsError(try GrokBillingProxyResponse.parse(Data(reversedPeriod.utf8))) {
            XCTAssertEqual($0 as? GrokBillingProxyResponseError, .invalidResponse)
        }

        XCTAssertThrowsError(try GrokBillingProxyResponse.parse(Data(#"""
        {
          "config": {
            "onDemandCap": {"val": 1e999},
            "onDemandUsed": {"val": 0}
          }
        }
        """#.utf8))) {
            XCTAssertEqual($0 as? GrokBillingProxyResponseError, .invalidResponse)
        }
    }

    func testEmptyAndOversizedResponsesFailClosed() {
        XCTAssertThrowsError(try GrokBillingProxyResponse.parse(Data())) {
            XCTAssertEqual($0 as? GrokBillingProxyResponseError, .invalidResponse)
        }
        XCTAssertThrowsError(try GrokBillingProxyResponse.parse(
            Data(repeating: 0x20, count: GrokBillingProxyResponse.maximumResponseBytes + 1)))
        {
            XCTAssertEqual($0 as? GrokBillingProxyResponseError, .invalidResponse)
        }
    }

    private static let emptyUnifiedResponse = #"""
    {
      "config": {
        "billingPeriodStart": "2026-08-28T01:04:42Z",
        "billingPeriodEnd": "2026-09-04T01:04:42Z",
        "currentPeriod": {
          "type": "USAGE_PERIOD_TYPE_WEEKLY",
          "start": "2026-08-28T01:04:42Z",
          "end": "2026-09-04T01:04:42Z"
        },
        "isUnifiedBillingUser": true,
        "onDemandCap": {"val": 0},
        "onDemandUsed": {"val": 0},
        "prepaidBalance": {"val": 0},
        "topUpMethod": "manual"
      }
    }
    """#
}
