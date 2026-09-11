import Foundation
import UsageCore

@MainActor
protocol MacAwakeActivityManaging {
    func begin(options: ProcessInfo.ActivityOptions, reason: String) -> NSObjectProtocol
    func end(_ activity: NSObjectProtocol)
}

@MainActor
struct ProcessInfoMacAwakeActivityManager: MacAwakeActivityManaging {
    func begin(options: ProcessInfo.ActivityOptions, reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
    }

    func end(_ activity: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(activity)
    }
}

/// Caffeinated-style display and system idle-sleep prevention. This controller
/// is intentionally independent from Claude scheduling: either feature can be
/// enabled alone.
@MainActor
final class MacAwakeController: ObservableObject {
    static let shared = MacAwakeController()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var activeDurationHours: Int
    @Published private(set) var enabledUntil: Date?

    private var autoOffTask: Task<Void, Never>?
    private var keepAwakeActivity: NSObjectProtocol?
    private var hasStarted = false
    private let activityManager: any MacAwakeActivityManaging
    private let sleep: @Sendable (Duration) async throws -> Void

    init(
        activityManager: any MacAwakeActivityManaging = ProcessInfoMacAwakeActivityManager(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        })
    {
        self.activityManager = activityManager
        self.sleep = sleep
        // Keep-awake activation is session-scoped. A relaunch always starts
        // off so Start at Login cannot silently create an infinite assertion.
        self.isEnabled = false
        self.activeDurationHours = MacAwakeSettings.defaultActiveDurationHours
        self.enabledUntil = nil
    }

    deinit {
        self.autoOffTask?.cancel()
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
    }

    func stop() {
        self.deactivate()
        self.hasStarted = false
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != self.isEnabled else { return }
        if enabled {
            self.isEnabled = true
            // Every OFF → ON transition starts at infinity. The user can then
            // choose a finite duration while the feature is active.
            self.activeDurationHours = MacAwakeSettings.defaultActiveDurationHours
            self.updateDeadlineFromNow()
            self.beginKeepingMacAwake()
            self.restartAutoOffTask()
        } else {
            self.deactivate()
        }
    }

    func setActiveDurationHours(_ hours: Int) {
        let clamped = MacAwakeSettings.clampedDurationHours(hours)
        guard clamped != self.activeDurationHours else { return }
        self.activeDurationHours = clamped
        if self.isEnabled {
            self.updateDeadlineFromNow()
            self.restartAutoOffTask()
        }
    }

    private func restartAutoOffTask() {
        self.autoOffTask?.cancel()
        self.autoOffTask = nil
        guard self.isEnabled, self.hasStarted, let enabledUntil = self.enabledUntil else { return }
        self.autoOffTask = Task { [weak self] in
            guard let self else { return }
            let delay = max(0.25, enabledUntil.timeIntervalSinceNow)
            do {
                try await self.sleep(.seconds(delay))
            } catch {
                return
            }
            guard self.isEnabled, self.enabledUntil == enabledUntil else { return }
            self.deactivate()
        }
    }

    private func deactivate() {
        self.autoOffTask?.cancel()
        self.autoOffTask = nil
        self.isEnabled = false
        self.activeDurationHours = MacAwakeSettings.defaultActiveDurationHours
        self.enabledUntil = nil
        self.endKeepingMacAwake()
    }

    private func updateDeadlineFromNow() {
        self.enabledUntil = self.activeDurationHours == 0
            ? nil
            : Date().addingTimeInterval(Double(self.activeDurationHours) * 3_600)
    }

    private func beginKeepingMacAwake() {
        guard self.keepAwakeActivity == nil else { return }
        self.keepAwakeActivity = self.activityManager.begin(
            options: MacAwakeSettings.activityOptions,
            reason: "Keep Mac Awake is active")
    }

    private func endKeepingMacAwake() {
        guard let keepAwakeActivity else { return }
        self.activityManager.end(keepAwakeActivity)
        self.keepAwakeActivity = nil
    }
}
