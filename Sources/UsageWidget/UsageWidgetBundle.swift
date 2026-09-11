import SwiftUI
import UsageCore
import WidgetKit

@main
struct UsageWidgetBundle: WidgetBundle {
    var body: some Widget {
        UsageStripWidget()
    }
}

struct UsageStripWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UsageStrip", provider: UsageStripProvider()) { entry in
            UsageStripEntryView(entry: entry)
        }
        .configurationDisplayName(UsageBrand.displayName)
        .description("Claude, Codex, and Grok remaining quota at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
