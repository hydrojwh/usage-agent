import Foundation

/// Presentation rules for Claude's model-scoped weekly windows.
///
/// These live in `UsageCore` rather than beside the collector because the
/// collector imports `CodexBarCore`, which the app-logic test target does not
/// link — logic kept there cannot be tested at all. The rules below are pure
/// string decisions, so they belong on the testable side of that boundary.
public enum ClaudeScopedWindowLabel {
    /// Model families that already have a dedicated row built from
    /// `ClaudeUsageSnapshot.opus`.
    ///
    /// Sonnet is included deliberately. Upstream fills that field with
    /// `sevenDaySonnet ?? sevenDayOpus`, so the row labelled "Opus weekly" can
    /// actually carry Sonnet data — in which case an unfiltered Sonnet scoped
    /// window would render the same quota twice under two names.
    private static let primaryWindowFamilies = ["opus", "sonnet"]

    /// The scope suffix upstream appends when naming a model-scoped window.
    private static let scopeSuffix = " only"

    /// Whether a scoped window duplicates the dedicated primary-model row.
    ///
    /// Matching is on the model name rather than the generated identifier.
    /// An identifier carries a version (`claude-weekly-scoped-claude-opus-5`),
    /// so testing it for an `-opus` suffix silently misses every versioned
    /// model id and would let a duplicate row through.
    public static func duplicatesPrimaryWindow(title: String, hasPrimaryModelWindow: Bool) -> Bool {
        guard hasPrimaryModelWindow else { return false }
        let normalized = self.modelName(from: title).lowercased()
        return self.primaryWindowFamilies.contains { normalized.contains($0) }
    }

    /// The window label to show for a scoped window.
    ///
    /// Upstream titles read "Fable only", which describes a scope rather than
    /// naming a window. Every other row in the card names its window —
    /// "5-hour", "Weekly", "Opus weekly" — so the scope form is rewritten to
    /// match. Titles that do not carry the suffix are left alone.
    public static func displayLabel(title: String) -> String {
        let name = self.modelName(from: title)
        guard name != title else { return title }
        return "\(name) weekly"
    }

    /// The model name inside a scoped-window title, with the scope suffix removed.
    private static func modelName(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().hasSuffix(self.scopeSuffix) else { return trimmed }
        return String(trimmed.dropLast(self.scopeSuffix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
