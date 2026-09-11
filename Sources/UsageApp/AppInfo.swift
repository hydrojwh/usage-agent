import Foundation
import UsageCore

/// Static product facts for the settings panel About block. Versions come from
/// the bundle so they can never drift from the shipped build; the footer keeps
/// showing the marketing version only (the build number lives in the
/// issue-report email, where it is diagnostic input rather than display
/// content — the UI shows the marketing version only).
enum AppInfo {
    static let developer = "HydRoMo"
    static let supportEmail = "support@hydromo.dev"
    static let copyright = "© 2026 HydRoMo. All rights reserved."

    /// Trimmed marketing version for display, or nil when the bundle carries
    /// none. Display callers hide the surface entirely instead of rendering a
    /// placeholder — an empty version draws nothing.
    static func marketingVersionLabel(bundle: Bundle = .main) -> String? {
        let value = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    /// Diagnostic contexts (the issue-report email) want an always-present
    /// value even when the bundle is broken; display must use the label above.
    static func marketingVersion(bundle: Bundle = .main) -> String {
        marketingVersionLabel(bundle: bundle) ?? "0.0.0"
    }

    static func buildVersion(bundle: Bundle = .main) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static func displayVersion(
        marketingVersion: String,
        buildVersion: String) -> String
    {
        "v\(marketingVersion) (\(buildVersion))"
    }

    /// mailto URL with the app version and macOS version prefilled so a report
    /// is actionable without the user transcribing diagnostic strings.
    static func issueReportURL(
        appName: String,
        displayVersion: String,
        operatingSystemVersion: String) -> URL
    {
        let fallback = URL(string: "mailto:\(supportEmail)")!
        guard var components = URLComponents(string: "mailto:\(supportEmail)") else {
            return fallback
        }
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "\(appName) issue — \(displayVersion)"),
            URLQueryItem(
                name: "body",
                value: """
                Issue description:

                Steps to reproduce:
                1.

                Expected result:

                Actual result:

                App: \(appName) \(displayVersion)
                macOS: \(operatingSystemVersion)
                """),
        ]
        return components.url ?? fallback
    }

    static func issueReportURL(bundle: Bundle = .main) -> URL {
        issueReportURL(
            appName: UsageBrand.displayName,
            displayVersion: displayVersion(
                marketingVersion: marketingVersion(bundle: bundle),
                buildVersion: buildVersion(bundle: bundle)),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString)
    }
}
