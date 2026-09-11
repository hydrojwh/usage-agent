import AppKit
import SwiftUI
import UsageCore

/// Renders the selected provider menu-bar label as one bitmap.
///
/// `MenuBarExtra` can under-measure nested SwiftUI label content and clip after
/// the first provider. A single image has one explicit intrinsic width, so the
/// status item reserves the selected providers' full width. Rendering is
/// event-driven by usage/settings publication; there is no timeline or timer.
@MainActor
private enum MenuBarUsageLabelRenderer {
    private static var lastKey: String?
    private static var lastImage: NSImage?

    static func image(items: [MenuBarSummaryItem], colorScheme: ColorScheme) -> NSImage {
        let key = ([colorScheme == .dark ? "dark" : "light"] + items.map {
            "\($0.provider.rawValue):\($0.value)"
        }).joined(separator: "|")
        if self.lastKey == key, let lastImage = self.lastImage {
            return lastImage
        }

        let iconSize: CGFloat = 12
        let labelHeight: CGFloat = 16
        let iconTextSpacing: CGFloat = 2
        let providerSpacing: CGFloat = 6
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        let textColor: NSColor = colorScheme == .dark ? .white : .black
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let textSizes = items.map { ($0.value as NSString).size(withAttributes: attributes) }
        let totalWidth = items.enumerated().reduce(CGFloat.zero) { result, pair in
            let (index, _) = pair
            return result + iconSize + iconTextSpacing + ceil(textSizes[index].width)
                + (index == items.count - 1 ? 0 : providerSpacing)
        }

        let image = NSImage(size: NSSize(width: ceil(totalWidth), height: labelHeight))
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high

        var x: CGFloat = 0
        for (index, item) in items.enumerated() {
            let iconRect = NSRect(
                x: x,
                y: floor((labelHeight - iconSize) / 2),
                width: iconSize,
                height: iconSize)
            self.drawMonochromeIcon(
                named: ProviderBrand.assetName(for: item.provider),
                colorScheme: colorScheme,
                in: iconRect)
            x += iconSize + iconTextSpacing

            let textSize = textSizes[index]
            (item.value as NSString).draw(
                at: NSPoint(x: x, y: floor((labelHeight - textSize.height) / 2)),
                withAttributes: attributes)
            x += ceil(textSize.width)
            if index != items.count - 1 {
                x += providerSpacing
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        self.lastKey = key
        self.lastImage = image
        return image
    }

    private static func drawMonochromeIcon(
        named name: String,
        colorScheme: ColorScheme,
        in rect: NSRect)
    {
        guard let base = NSImage(named: name) else { return }
        base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        self.monochromeColor(for: colorScheme).setFill()
        rect.fill(using: .sourceIn)
    }

    private static func monochromeColor(for colorScheme: ColorScheme) -> NSColor {
        colorScheme == .dark ? .white : .black
    }
}

struct MenuBarUsageLabel: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageDisplaySettings.showsClaudeKey) private var showsClaude = true
    @AppStorage(UsageDisplaySettings.showsCodexKey) private var showsCodex = true
    @AppStorage(UsageDisplaySettings.showsGrokKey) private var showsGrok = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let image = MenuBarUsageLabelRenderer.image(
            items: MenuBarSummary.items(
                for: self.menuBarStatuses,
                providers: self.visibleProviders),
            colorScheme: self.colorScheme)

        Image(nsImage: image)
            .renderingMode(.original)
            .frame(width: image.size.width, height: image.size.height)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(self.accessibilityText)
    }

    /// The compact status item has no room for a durable sample badge. Keep
    /// its percentages unavailable while sample mode is active; the popover
    /// and widget render the labeled sample values instead.
    private var menuBarStatuses: [ProviderUsageStatus] { self.monitor.menuBarStatuses }

    private var accessibilityText: String {
        let summary = MenuBarSummary.accessibilityText(
            for: self.menuBarStatuses,
            providers: self.visibleProviders)
        return self.monitor.reviewerSampleModeEnabled
            ? "Reviewer sample mode. Open Usage Agents for labeled sample values. \(summary)"
            : summary
    }

    private var visibleProviders: [UsageProviderKind] {
        UsageDisplaySettings.visibleProviders(
            showsClaude: self.showsClaude,
            showsCodex: self.showsCodex,
            showsGrok: self.showsGrok)
    }
}
