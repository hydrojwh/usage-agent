import Foundation

public enum UsageWidgetSnapshotStoreError: Error, LocalizedError, Sendable {
    case appGroupUnavailable

    public var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Widget data is unavailable: the app-group container could not be resolved. "
                + "The app and widget must be signed to resolve the same macOS App Group."
        }
    }
}

/// Reads and writes `UsageWidgetSnapshot` JSON in the shared app-group
/// container. The app writes after each refresh; the widget extension only
/// reads. Both resolve the same group identifier from their Info.plist
/// (`UsageAppGroupID`), which is stamped from the `USAGE_APP_GROUP_ID`
/// build setting — `<TEAM_ID>.com.example.usageagents`.
public enum UsageWidgetSnapshotStore {
    public static let snapshotFilename = "usage-widget-snapshot.json"

    /// Group identifier from the host bundle's Info.plist, or `nil` when the
    /// value is missing, unexpanded, or malformed. An unexpanded or leading-dot
    /// value means signing configuration was not applied, which must surface as
    /// a loud failure rather than a silent fallback path.
    public static var appGroupID: String? {
        Self.validatedGroupID(Bundle.main.object(forInfoDictionaryKey: "UsageAppGroupID") as? String)
    }

    /// Validates a raw group identifier candidate. Exposed for tests.
    public static func validatedGroupID(_ raw: String?) -> String? {
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty,
              !value.hasPrefix("$("),
              !value.hasPrefix("."),
              !value.hasPrefix("group."),
              !value.contains(" "),
              let separator = value.firstIndex(of: ".")
        else {
            return nil
        }
        let teamPrefix = value[..<separator]
        guard teamPrefix.count == 10,
              teamPrefix.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) })
        else {
            return nil
        }
        return value
    }

    /// Snapshot URL inside the app-group container, or `nil` when the group is
    /// unavailable. There is deliberately no fallback directory: the widget
    /// would silently read a different location and show stale preview data.
    public static var defaultSnapshotURL: URL? {
        guard let groupID = Self.appGroupID else { return nil }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
        else { return nil }
        return container.appendingPathComponent(Self.snapshotFilename, isDirectory: false)
    }

    public static func save(_ snapshot: UsageWidgetSnapshot, to url: URL?) throws {
        guard let url else {
            throw UsageWidgetSnapshotStoreError.appGroupUnavailable
        }
        // The group container may not exist yet on first write; .atomic alone
        // does not create intermediate directories.
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: url, options: .atomic)
    }

    public static func saveDefault(_ snapshot: UsageWidgetSnapshot) throws {
        try Self.save(snapshot, to: Self.defaultSnapshotURL)
    }

    public static func load(from url: URL?) -> UsageWidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(UsageWidgetSnapshot.self, from: data)
    }

    public static func loadDefault() -> UsageWidgetSnapshot? {
        Self.load(from: Self.defaultSnapshotURL)
    }
}
