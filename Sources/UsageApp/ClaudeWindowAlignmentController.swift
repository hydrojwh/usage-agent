#if !USAGE_APP_STORE
import CodexBarCore
#endif
import Foundation
import UsageCore

protocol ClaudeWindowAnchorRunning: Sendable {
    func runAnchor() async throws
}

enum ClaudeWindowAnchorRunnerError: LocalizedError {
    case claudeNotInstalled
    case unavailableInAppStore
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .claudeNotInstalled:
            "Claude CLI is not installed or could not be found."
        case .unavailableInAppStore:
            "Anchor needs an App Store-compatible Claude authorization path."
        case .requestFailed:
            "Claude did not accept the scheduled warm-up request. Check the Claude CLI login."
        }
    }
}

struct ClaudeHeadlessWindowAnchorRunner: ClaudeWindowAnchorRunning {
#if USAGE_APP_STORE
    func runAnchor() async throws {
        throw ClaudeWindowAnchorRunnerError.unavailableInAppStore
    }
#else
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    func runAnchor() async throws {
        guard let binary = ClaudeCLIResolver.resolvedBinaryPath(environment: self.environment) else {
            throw ClaudeWindowAnchorRunnerError.claudeNotInstalled
        }

        // A scheduled alignment request must use the end user's existing
        // Claude subscription login. Never let a GUI-launch environment switch
        // this request to an API key, gateway, or long-lived copied token.
        let safeEnvironment = ClaudeWindowAnchorCommand.sanitizedEnvironment(self.environment)

        let workingDirectory = try Self.safeWorkingDirectory()

        do {
            _ = try await SubprocessRunner.run(
                binary: binary,
                arguments: ClaudeWindowAnchorCommand.arguments,
                environment: safeEnvironment,
                timeout: 45,
                maxOutputBytes: 4_096,
                currentDirectoryURL: workingDirectory,
                label: "Claude window alignment")
        } catch {
            // Raw provider output can contain account or local-environment
            // details. Convert every process failure to a bounded generic error.
            throw ClaudeWindowAnchorRunnerError.requestFailed
        }
    }

    private static func safeWorkingDirectory() throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask).first
        else {
            throw ClaudeWindowAnchorRunnerError.requestFailed
        }
        let directory = applicationSupport
            .appendingPathComponent("Usage", isDirectory: true)
            .appendingPathComponent("ClaudeWindowAlignment", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true)
        return directory
    }
#endif
}

@MainActor
final class ClaudeWindowAlignmentController: ObservableObject {
    static let shared = ClaudeWindowAlignmentController()

    @Published private(set) var isEnabled: Bool
    @Published private(set) var anchorDate: Date
    @Published private(set) var nextScheduledAt: Date?
    @Published private(set) var lastRunAt: Date?
    @Published private(set) var statusText: String

    private let defaults: UserDefaults
    private let runner: any ClaudeWindowAnchorRunning
    private let supportsClaudeWindowAnchor: Bool
    private var lastHandledSlotID: String?
    private var schedulerTask: Task<Void, Never>?
    private var hasStarted = false
    private var isExecuting = false

    init(
        defaults: UserDefaults = .standard,
        runner: any ClaudeWindowAnchorRunning = ClaudeHeadlessWindowAnchorRunner(),
        supportsClaudeWindowAnchor: Bool = UsageDistributionPolicy.supportsClaudeWindowAnchor)
    {
        self.defaults = defaults
        self.runner = runner
        self.supportsClaudeWindowAnchor = supportsClaudeWindowAnchor
        let storedEnabled = defaults.bool(forKey: ClaudeWindowAlignmentSettings.isEnabledKey)
        let resolvedEnabled = supportsClaudeWindowAnchor ? storedEnabled : false
        self.isEnabled = resolvedEnabled
        self.anchorDate = defaults.object(
            forKey: ClaudeWindowAlignmentSettings.anchorDateKey) as? Date
            ?? ClaudeWindowAlignmentSettings.defaultAnchorDate()
        self.lastHandledSlotID = defaults.string(
            forKey: ClaudeWindowAlignmentSettings.lastHandledSlotKey)
        self.statusText = supportsClaudeWindowAnchor
            ? (resolvedEnabled ? "Waiting to resume" : "Off")
            : ClaudeWindowAnchorRunnerError.unavailableInAppStore.localizedDescription
        if storedEnabled != resolvedEnabled {
            defaults.set(resolvedEnabled, forKey: ClaudeWindowAlignmentSettings.isEnabledKey)
        }
    }

    deinit {
        self.schedulerTask?.cancel()
    }

    func start() {
        guard !self.hasStarted else { return }
        self.hasStarted = true
        guard self.supportsClaudeWindowAnchor else {
            self.disable(status: ClaudeWindowAnchorRunnerError.unavailableInAppStore.localizedDescription)
            return
        }
        guard self.isEnabled else {
            self.updateNextScheduledDate(now: Date())
            return
        }

        self.statusText = "Waiting for the next anchor"
        self.restartScheduler()
    }

    func stop() {
        self.schedulerTask?.cancel()
        self.schedulerTask = nil
        self.hasStarted = false
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != self.isEnabled else { return }
        if enabled {
            guard self.supportsClaudeWindowAnchor else {
                self.isEnabled = false
                self.defaults.set(false, forKey: ClaudeWindowAlignmentSettings.isEnabledKey)
                self.statusText = ClaudeWindowAnchorRunnerError.unavailableInAppStore.localizedDescription
                self.updateNextScheduledDate(now: Date())
                return
            }
            self.isEnabled = true
            self.defaults.set(true, forKey: ClaudeWindowAlignmentSettings.isEnabledKey)
            self.defaults.set(self.anchorDate, forKey: ClaudeWindowAlignmentSettings.anchorDateKey)
            self.statusText = "Waiting for the next anchor"
            self.restartScheduler()
        } else {
            self.disable(status: "Off")
        }
    }

    /// Provider visibility is also an execution boundary. Hiding Claude must
    /// never leave a scheduled Claude request running invisibly. Showing the
    /// provider again is intentionally a no-op; the user must re-enable Anchor.
    func reconcileClaudeProviderVisibility(_ isVisible: Bool) {
        guard !isVisible else { return }
        let status = self.supportsClaudeWindowAnchor
            ? "Off"
            : ClaudeWindowAnchorRunnerError.unavailableInAppStore.localizedDescription
        self.disable(status: status)
    }

    func setAnchorHour(_ hour: Int) {
        self.anchorDate = ClaudeWindowAlignmentSettings.anchorDate(
            matching: Date(),
            hour: hour,
            minute: 0)
        self.defaults.set(self.anchorDate, forKey: ClaudeWindowAlignmentSettings.anchorDateKey)
        self.lastHandledSlotID = nil
        self.defaults.removeObject(forKey: ClaudeWindowAlignmentSettings.lastHandledSlotKey)
        self.restartScheduler()
    }

    func upcomingDates(count: Int = 5, now: Date = Date()) -> [Date] {
        ClaudeWindowAlignmentSchedule(anchor: self.anchorDate)
            .upcomingSlots(after: now, count: count)
            .map(\.dueAt)
    }

    private func restartScheduler() {
        self.schedulerTask?.cancel()
        self.schedulerTask = nil
        let now = Date()
        self.updateNextScheduledDate(now: now)
        guard self.isEnabled, self.hasStarted else { return }
        self.schedulerTask = Task { [weak self] in
            await self?.runSchedulerLoop()
        }
    }

    private func runSchedulerLoop() async {
        while !Task.isCancelled, self.isEnabled {
            let now = Date()
            let schedule = ClaudeWindowAlignmentSchedule(anchor: self.anchorDate)
            if let dueSlot = schedule.dueSlot(at: now),
               dueSlot.id != self.lastHandledSlotID,
               !self.isExecuting
            {
                await self.execute(dueSlot)
                continue
            }

            let nextSlot = schedule.nextSlot(after: now)
            self.nextScheduledAt = nextSlot.dueAt
            let delay = max(0.25, nextSlot.dueAt.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
        }
    }

    private func execute(_ slot: ClaudeWindowAlignmentSlot) async {
        self.isExecuting = true
        self.lastHandledSlotID = slot.id
        self.defaults.set(slot.id, forKey: ClaudeWindowAlignmentSettings.lastHandledSlotKey)
        self.statusText = "Starting Claude warm-up…"
        defer {
            self.isExecuting = false
            self.updateNextScheduledDate(now: Date())
        }

        do {
            try await self.runner.runAnchor()
            self.lastRunAt = Date()
            self.statusText = "Last warm-up completed"
        } catch let error as ClaudeWindowAnchorRunnerError {
            self.statusText = error.localizedDescription
        } catch {
            self.statusText = ClaudeWindowAnchorRunnerError.requestFailed.localizedDescription
        }
    }

    private func disable(status: String) {
        self.schedulerTask?.cancel()
        self.schedulerTask = nil
        self.isEnabled = false
        self.defaults.set(false, forKey: ClaudeWindowAlignmentSettings.isEnabledKey)
        self.updateNextScheduledDate(now: Date())
        self.statusText = status
    }

    private func updateNextScheduledDate(now: Date) {
        self.nextScheduledAt = ClaudeWindowAlignmentSchedule(anchor: self.anchorDate)
            .nextSlot(after: now)
            .dueAt
    }
}
