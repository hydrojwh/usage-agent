import AppKit
import SwiftUI
import UsageCore

@main
struct UsageMenuBarApp: App {
    @NSApplicationDelegateAdaptor(UsageAppDelegate.self) private var appDelegate
    @StateObject private var monitor = UsageMonitor.shared

    var body: some Scene {
        MenuBarExtra {
            DashboardView(monitor: self.monitor)
        } label: {
            MenuBarUsageLabel(monitor: self.monitor)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class UsageAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UsageMonitor.shared.start()
        let windowAlignment = ClaudeWindowAlignmentController.shared
        windowAlignment.reconcileClaudeProviderVisibility(
            UsageDisplaySettings.showsClaude())
        windowAlignment.start()
        MacAwakeController.shared.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        MacAwakeController.shared.stop()
        ClaudeWindowAlignmentController.shared.stop()
        UsageMonitor.shared.stop()
    }
}
