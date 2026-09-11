import UsageCore
import WidgetKit

struct UsageStripEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageWidgetSnapshot?
}

/// The widget never fetches provider data. It renders the snapshot the app
/// wrote to the shared app-group container, and relies on the app's
/// `WidgetCenter.reloadAllTimelines()` pushes instead of its own schedule.
///
/// The timeline publishes several entries that share one snapshot but advance
/// the entry date, so the displayed freshness keeps moving forward while the
/// app is closed. Without this, the age shown next to the numbers would freeze
/// at the moment of the last app push and stale data would look current.
struct UsageStripProvider: TimelineProvider {
    /// Coverage offsets from the timeline request: sub-hour steps while data is
    /// fresh, then coarser steps out to 24 hours. After the last entry the
    /// system asks for a new timeline, which re-reads the snapshot file.
    private static let entryOffsets: [TimeInterval] = [
        0, 300, 900, 1_800, 3_600, 7_200, 14_400, 28_800, 43_200, 86_400,
    ]

    func placeholder(in context: Context) -> UsageStripEntry {
        UsageStripEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageStripEntry) -> Void) {
        // Sample numbers are for the gallery preview only. Everywhere else a
        // missing snapshot must render as "no data", never as invented values.
        let snapshot = context.isPreview ? UsageWidgetSnapshot.placeholder : UsageWidgetSnapshotStore.loadDefault()
        completion(UsageStripEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageStripEntry>) -> Void) {
        let snapshot = UsageWidgetSnapshotStore.loadDefault()
        let now = Date()
        let entries = Self.entryOffsets.map {
            UsageStripEntry(date: now.addingTimeInterval($0), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.entryOffsets.last ?? 86_400))))
    }
}
