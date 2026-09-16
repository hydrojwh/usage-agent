import AppKit
import SwiftUI
import UsageCore

struct DashboardView: View {
    @ObservedObject var monitor: UsageMonitor
    @StateObject private var windowAlignment = ClaudeWindowAlignmentController.shared
    @StateObject private var macAwake = MacAwakeController.shared
    @AppStorage(UsageDisplaySettings.showsAccountIdentifiersKey)
    private var showsAccountIdentifiers = UsageDisplaySettings.showsAccountIdentifiersDefault
    @AppStorage(UsageDisplaySettings.resetDisplayModeKey)
    private var resetDisplayModeRaw = UsageDisplaySettings.resetDisplayModeDefault.rawValue
    @AppStorage(UsageDisplaySettings.showsClaudeKey) private var showsClaude = true
    @AppStorage(UsageDisplaySettings.showsCodexKey) private var showsCodex = true
    @AppStorage(UsageDisplaySettings.showsGrokKey) private var showsGrok = true
    @AppStorage(UsageDisplaySettings.refreshIntervalSecondsKey) private var refreshIntervalSeconds =
        UsageDisplaySettings.refreshIntervalDefaultSeconds
    @State private var isSettingsPresented = false
    @State private var draftShowsAccountIdentifiers = UsageDisplaySettings.showsAccountIdentifiersDefault
    @State private var draftShowsClaude = true
    @State private var draftShowsCodex = true
    @State private var draftShowsGrok = true
    @State private var draftRefreshIntervalSteps: Double =
        UsageDisplaySettings.refreshIntervalDefaultSeconds / UsageDisplaySettings.refreshIntervalStepSeconds
#if USAGE_APP_STORE
    @State private var draftReviewerSampleModeEnabled = false
#endif
    @State private var measuredContentHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            self.header

#if USAGE_APP_STORE
            if self.monitor.reviewerSampleModeEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "testtube.2")
                    Text("Reviewer Sample Mode")
                        .font(AppFont.captionSemibold)
                    Spacer()
                    Text("Not live provider data")
                        .font(AppFont.caption)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, AppLayout.headerHorizontalPadding)
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
#endif

            Divider()

            VStack(spacing: AppLayout.contentSpacing) {
                MacAwakePanel(controller: self.macAwake)
            }
                .padding(.horizontal, AppLayout.contentHorizontalPadding)
                .padding(.top, AppLayout.contentVerticalPadding)

            ScrollView {
                VStack(spacing: AppLayout.contentSpacing) {
                    ForEach(self.visibleStatuses) { status in
                        ProviderCard(
                            status: status,
                            showsAccountIdentifiers: self.showsAccountIdentifiers,
                            resetDisplayMode: self.resetDisplayMode)
                        // Each anchor lives with its provider card, so the
                        // toggle reads as a per-provider setting.
                        if status.provider == .claude {
                            ClaudeWindowAlignmentPanel(controller: self.windowAlignment)
                        }
                    }
                }
                .padding(.horizontal, AppLayout.contentHorizontalPadding)
                .padding(.vertical, AppLayout.contentVerticalPadding)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: DashboardContentHeightPreferenceKey.self,
                            value: proxy.size.height)
                    }
                }
            }
            .frame(height: self.contentViewportHeight)
            .scrollIndicators(
                self.measuredContentHeight > self.currentContentHeightCap ? .visible : .hidden)
            .onPreferenceChange(DashboardContentHeightPreferenceKey.self) { newHeight in
                guard newHeight > 0, abs(newHeight - self.measuredContentHeight) > 0.5 else { return }
                self.measuredContentHeight = newHeight
            }

            Divider()
            self.footer
        }
        .frame(width: AppLayout.popoverWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            self.monitor.setRefreshInterval(seconds: self.refreshIntervalSeconds)
            self.monitor.start()
            self.windowAlignment.reconcileClaudeProviderVisibility(self.showsClaude)
            self.windowAlignment.start()
            self.macAwake.start()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .font(AppFont.title3)
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(UsageBrand.displayName)
                    .font(AppFont.headline)
                Text(self.updatedText)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await self.monitor.refresh() }
            } label: {
                if self.monitor.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .help("Refresh usage")
            .accessibilityLabel("Refresh usage")
            .disabled(self.monitor.isRefreshing)
        }
        .padding(.horizontal, AppLayout.headerHorizontalPadding)
        .padding(.vertical, AppLayout.headerVerticalPadding)
    }

    private var settingsButton: some View {
        Button {
            self.prepareSettingsDraft()
            self.isSettingsPresented = true
        } label: {
            Image(systemName: "gearshape")
                .font(AppFont.title3)
                .frame(width: 24, height: 20)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .fixedSize()
        .help("\(UsageBrand.displayName) settings")
        .accessibilityLabel("\(UsageBrand.displayName) settings")
        .popover(isPresented: self.$isSettingsPresented, arrowEdge: .bottom) {
            self.settingsPanel
        }
    }

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(AppFont.headline)

            VStack(alignment: .leading, spacing: 7) {
                Text("Providers")
                    .font(AppFont.captionSemibold)
                    .foregroundStyle(.secondary)
                Toggle("Claude", isOn: self.$draftShowsClaude)
                Toggle("Codex", isOn: self.$draftShowsCodex)
                Toggle("Grok", isOn: self.$draftShowsGrok)
            }
            .toggleStyle(.checkbox)

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Auto-refresh")
                        .font(AppFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(UsageDisplaySettings.refreshIntervalLabel(
                        forSteps: Int(self.draftRefreshIntervalSteps)))
                        .font(AppFont.captionMonospaced)
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: self.$draftRefreshIntervalSteps,
                    in: 1...360,
                    step: 1,
                    onEditingChanged: { editing in
                        guard !editing else { return }
                        self.draftRefreshIntervalSteps = self.draftRefreshIntervalSteps.rounded()
                    })
                    // Blend the filled portion into the track: at the default
                    // 5-minute position the accent-colored stub reads as an
                    // unexplained dark bar in the plain settings panel.
                    .tint(Color(nsColor: .quaternaryLabelColor))                    .help("Refresh every 10-second steps, from 10 seconds to 1 hour. Applies when you press Apply.")
                Text("10-second steps, 10 s – 1 h. Shorter intervals poll the provider CLIs more often.")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Toggle("Show account identifiers", isOn: self.$draftShowsAccountIdentifiers)
                .toggleStyle(.checkbox)

#if USAGE_APP_STORE
            Divider()

            VStack(alignment: .leading, spacing: 5) {
                Toggle("Reviewer Sample Mode", isOn: self.$draftReviewerSampleModeEnabled)
                    .toggleStyle(.checkbox)
                Text("Shows clearly labeled sample values. No provider account is used.")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
#endif

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                ThirdPartyNoticesButton()
                Link(destination: AppInfo.issueReportURL()) {
                    Label("Report an Issue…", systemImage: "exclamationmark.bubble")
                }
                .buttonStyle(.plain)
                .help("Compose a support email with app and macOS details")
                .accessibilityLabel("Compose a support email with app and macOS details")
                Text("\(AppInfo.developer) · \(AppInfo.copyright)")
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button("Cancel") {
                    self.isSettingsPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    self.applySettingsDraft()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!self.draftHasVisibleProvider)
            }
        }
        .font(AppFont.callout)
        .padding(14)
        .frame(width: self.settingsPanelWidth)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack {
                Group {
#if USAGE_APP_STORE
                    if self.monitor.reviewerSampleModeEnabled {
                        Label("Reviewer samples · not live data", systemImage: "testtube.2")
                    } else {
                    }
#else
                    Label(
                        "Local CLI data · refreshes every \(UsageDisplaySettings.refreshIntervalLabel(forSteps: UsageDisplaySettings.clampedRefreshIntervalSteps(forSeconds: self.refreshIntervalSeconds)))",
                        systemImage: "lock.shield")
#endif
                }
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 14) {
                LoginItemToggle()
                Spacer()
                Button {
                    self.resetDisplayModeRaw = self.resetDisplayMode.toggled.rawValue
                } label: {
                    Image(systemName: self.resetDisplayMode == .remaining
                        ? "hourglass"
                        : "calendar.badge.clock")
                }
                .buttonStyle(.borderless)
                .help(self.resetDisplayHelp)
                .accessibilityLabel(self.resetDisplayHelp)
            }

            if let widgetError = self.monitor.widgetSyncError {
                Label(widgetError, systemImage: "exclamationmark.bubble")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack(spacing: 6) {
                self.settingsButton
                if let version = AppInfo.marketingVersionLabel() {
                    Text(version)
                        .font(AppFont.captionMonospaced)
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("Version \(version)")
                }
                Spacer()
                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(AppFont.title3)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .fixedSize()
                .help("Quit \(UsageBrand.displayName)")
                .accessibilityLabel("Quit \(UsageBrand.displayName)")
            }
        }
        .font(AppFont.callout)
        .padding(.horizontal, AppLayout.footerHorizontalPadding)
        .padding(.vertical, AppLayout.footerVerticalPadding)
    }

    private var updatedText: String {
        if self.monitor.isRefreshing {
            return "Checking providers…"
        }
        let history = self.monitor.refreshHistory
        if let attempted = history.lastAttemptedAt,
           let successful = history.lastSuccessfulAt,
           attempted > successful
        {
            return "Checked \(attempted.formatted(.relative(presentation: .named))) · data from \(successful.formatted(.relative(presentation: .named)))"
        }
        if let successful = history.lastSuccessfulAt {
            return "Updated \(successful.formatted(.relative(presentation: .named)))"
        }
        if let attempted = history.lastAttemptedAt {
            return "Checked \(attempted.formatted(.relative(presentation: .named))) · no data"
        }
        return "Waiting to refresh"
    }

    private var visibleProviders: [UsageProviderKind] {
        UsageDisplaySettings.visibleProviders(
            showsClaude: self.showsClaude,
            showsCodex: self.showsCodex,
            showsGrok: self.showsGrok)
    }

    private var visibleStatuses: [ProviderUsageStatus] {
        let visible = Set(self.visibleProviders)
        return self.monitor.statuses.filter { visible.contains($0.provider) }
    }

    private var resetDisplayMode: UsageResetDisplayMode {
        UsageResetDisplayMode(rawValue: self.resetDisplayModeRaw)
            ?? UsageDisplaySettings.resetDisplayModeDefault
    }

    private var draftHasVisibleProvider: Bool {
        self.draftShowsClaude || self.draftShowsCodex || self.draftShowsGrok
    }

    private func prepareSettingsDraft() {
        self.draftShowsClaude = self.showsClaude
        self.draftShowsCodex = self.showsCodex
        self.draftShowsGrok = self.showsGrok
        self.draftShowsAccountIdentifiers = self.showsAccountIdentifiers
        self.draftRefreshIntervalSteps = Double(UsageDisplaySettings.clampedRefreshIntervalSteps(
            forSeconds: self.refreshIntervalSeconds))
#if USAGE_APP_STORE
        self.draftReviewerSampleModeEnabled = self.monitor.reviewerSampleModeEnabled
#endif
    }

    private func applySettingsDraft() {
        guard self.draftHasVisibleProvider else { return }
        self.showsClaude = self.draftShowsClaude
        self.showsCodex = self.draftShowsCodex
        self.showsGrok = self.draftShowsGrok
        self.showsAccountIdentifiers = self.draftShowsAccountIdentifiers
        self.refreshIntervalSeconds = UsageDisplaySettings.refreshIntervalSeconds(
            forSteps: Int(self.draftRefreshIntervalSteps))
        self.monitor.setRefreshInterval(seconds: self.refreshIntervalSeconds)
        self.windowAlignment.reconcileClaudeProviderVisibility(self.draftShowsClaude)
        self.isSettingsPresented = false
#if USAGE_APP_STORE
        let reviewerSampleModeEnabled = self.draftReviewerSampleModeEnabled
        Task {
            await self.monitor.setReviewerSampleModeEnabled(reviewerSampleModeEnabled)
        }
#endif
    }

    /// Provider cards scroll only past the card cap plus one allowance per
    /// grouped anchor panel, so a provider below two anchors stays on screen.
    private var currentContentHeightCap: CGFloat {
        let anchorPanelCount = self.visibleProviders.filter { $0 == .claude || $0 == .codex }.count
        return AppLayout.maximumContentHeight(anchorPanelCount: anchorPanelCount)
    }

    private var contentViewportHeight: CGFloat {
        let contentHeight = self.measuredContentHeight > 0
            ? self.measuredContentHeight
            : AppLayout.estimatedContentHeight(providerCount: self.visibleProviders.count)
        return min(contentHeight, self.currentContentHeightCap)
    }

    private var resetDisplayHelp: String {
        switch self.resetDisplayMode {
        case .remaining:
            "Showing time remaining. Click to show reset time."
        case .resetTime:
            "Showing reset time. Click to show time remaining."
        }
    }

    private var settingsPanelWidth: CGFloat {
#if USAGE_APP_STORE
        320
#else
        260
#endif
    }
}

private struct DashboardContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MacAwakePanel: View {
    @ObservedObject var controller: MacAwakeController
    @State private var isInfoPresented = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: self.controller.isEnabled
                    ? "cup.and.saucer.fill"
                    : "cup.and.saucer")
                    .font(AppFont.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(self.coffeeAccent)
                    .frame(width: 22)
                    .accessibilityLabel(self.controller.isEnabled
                        ? "Filled coffee cup, Keep Mac Awake on"
                        : "Empty coffee cup, Keep Mac Awake off")

                Text("Keep Mac Awake")
                    .font(AppFont.subheadlineSemibold)

                Spacer()

                Button {
                    self.isInfoPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("About Keep Mac Awake")
                .accessibilityLabel("About Keep Mac Awake")
                .popover(isPresented: self.$isInfoPresented, arrowEdge: .top) {
                    self.infoPopover
                }

                Toggle("Keep Mac Awake", isOn: self.enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 10) {
                Text("Duration")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: self.durationBinding,
                    in: Double(MacAwakeSettings.minimumActiveDurationHours)...Double(
                        MacAwakeSettings.maximumActiveDurationHours),
                    step: 1)
                    .tint(Color(nsColor: .quaternaryLabelColor))
                    .help("Choose infinity or an automatic duration from 1 to 24 hours.")
                    .disabled(!self.controller.isEnabled)
                self.durationLabel
            }
        }
        .padding(AppLayout.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .fill(self.coffeeBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(self.coffeeBorder, lineWidth: 1)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.controller.isEnabled },
            set: { self.controller.setEnabled($0) })
    }

    private var durationBinding: Binding<Double> {
        Binding(
            get: { Double(self.controller.activeDurationHours) },
            set: { self.controller.setActiveDurationHours(Int($0.rounded())) })
    }

    @ViewBuilder private var durationLabel: some View {
        if self.controller.activeDurationHours == 0 {
            Image(systemName: "infinity")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(self.coffeeAccent)
                .frame(width: 32, height: 20)
                .accessibilityLabel("Infinite duration")
        } else {
            Text("\(self.controller.activeDurationHours)h")
                .font(AppFont.captionMonospaced)
                .frame(width: 32, height: 20, alignment: .trailing)
        }
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keep Mac Awake")
                .font(AppFont.headline)
            Text("Keeps the display on and prevents idle system sleep on battery or external power while \(UsageBrand.displayName) is running. This uses more battery when unplugged.")
            Text("Lid close, explicit sleep, low-battery or thermal forced sleep, and shutdown still work normally.")
                .foregroundStyle(.secondary)
            Text("∞ stays active until you turn it off or quit \(UsageBrand.displayName). A numbered duration turns only this feature off automatically.")
                .foregroundStyle(.secondary)
        }
        .font(AppFont.callout)
        .padding(14)
        .frame(width: 300)
    }

    private var coffeeBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 66.0 / 255.0, green: 49.0 / 255.0, blue: 38.0 / 255.0)
            : Color(red: 243.0 / 255.0, green: 230.0 / 255.0, blue: 216.0 / 255.0)
    }

    private var coffeeBorder: Color {
        self.coffeeAccent.opacity(self.colorScheme == .dark ? 0.46 : 0.28)
    }

    private var coffeeAccent: Color {
        self.colorScheme == .dark
            ? Color(red: 185.0 / 255.0, green: 138.0 / 255.0, blue: 104.0 / 255.0)
            : Color(red: 139.0 / 255.0, green: 94.0 / 255.0, blue: 60.0 / 255.0)
    }
}

private struct ClaudeWindowAlignmentPanel: View {
    @ObservedObject var controller: ClaudeWindowAlignmentController
    @State private var isInfoPresented = false
    @State private var draftAnchorHour: Double
    @Environment(\.colorScheme) private var colorScheme

    init(controller: ClaudeWindowAlignmentController) {
        self.controller = controller
        self._draftAnchorHour = State(initialValue: Double(
            Calendar.current.component(.hour, from: controller.anchorDate)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "timer")
                    .font(AppFont.subheadlineSemibold)
                    .foregroundStyle(ProviderBrand.claude)

                Text("Claude 5-Hour Anchor")
                    .font(AppFont.subheadlineSemibold)

                Spacer()

                Button {
                    self.isInfoPresented.toggle()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("About Claude 5-Hour Anchor")
                .accessibilityLabel("About Claude 5-Hour Anchor")
                .popover(isPresented: self.$isInfoPresented, arrowEdge: .top) {
                    self.infoPopover
                }

                Toggle("Claude 5-Hour Anchor", isOn: self.enabledBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            HStack(spacing: 12) {
                Text("Start")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: self.$draftAnchorHour,
                    in: 0...23,
                    step: 1,
                    onEditingChanged: { editing in
                        guard !editing else { return }
                        self.controller.setAnchorHour(Int(self.draftAnchorHour.rounded()))
                    })
                    // Same track de-emphasis as the settings slider: with a
                    // graphite system accent the default track reads as a
                    // black line on the card.
                    .tint(Color(nsColor: .quaternaryLabelColor))
                    .help("Set the anchor start hour. Changes apply when you release the slider.")
                Text(String(format: "%02d:00", Int(self.draftAnchorHour.rounded())))
                    .font(AppFont.captionMonospaced)
                    .frame(width: 46, alignment: .trailing)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle()
                    .fill(self.controller.isEnabled ? Color.green : Color.secondary)
                    .frame(width: 6, height: 6)
                Text(self.controller.statusText)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Spacer()

                if let next = self.controller.nextScheduledAt {
                    Text("Next \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(AppLayout.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .fill(self.anchorBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(self.anchorBorder, lineWidth: 1)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { self.controller.isEnabled },
            set: { self.controller.setEnabled($0) })
    }

    private var infoPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude 5-Hour Anchor")
                .font(AppFont.headline)
            Text("The selected start hour defines a continuous five-hour schedule. For example, 06:00 continues as 11:00, 16:00, 21:00, 02:00, and 07:00.")
#if USAGE_APP_STORE
            Text("Anchor is disabled in this Sandbox feasibility build until Claude provides an App Store-compatible authorization path for the scheduled request.")
                .foregroundStyle(.secondary)
#else
            Text("At each slot \(UsageBrand.displayName) sends one minimal request through the installed Claude CLI. Tools, customizations, and session persistence are disabled. The request counts toward Claude usage and runs only while \(UsageBrand.displayName) and the Mac are awake.")
                .foregroundStyle(.secondary)
#endif
        }
        .font(AppFont.callout)
        .padding(14)
        .frame(width: 320)
    }

    private var anchorBackground: Color {
        self.colorScheme == .dark
            ? Color(red: 250.0 / 255.0, green: 235.0 / 255.0, blue: 199.0 / 255.0).opacity(0.08)
            : Color(red: 251.0 / 255.0, green: 248.0 / 255.0, blue: 240.0 / 255.0)
    }

    private var anchorBorder: Color {
        self.colorScheme == .dark
            ? Color(red: 209.0 / 255.0, green: 188.0 / 255.0, blue: 140.0 / 255.0).opacity(0.24)
            : Color(red: 187.0 / 255.0, green: 169.0 / 255.0, blue: 127.0 / 255.0).opacity(0.24)
    }
}

private struct ProviderCard: View {
    let status: ProviderUsageStatus
    let showsAccountIdentifiers: Bool
    let resetDisplayMode: UsageResetDisplayMode

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProviderBrandIcon(provider: self.status.provider)
                Text(self.status.provider.displayName)
                    .font(AppFont.subheadlineSemibold)
                    .foregroundStyle(self.brandColor)

                Spacer()

                if self.status.isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }

                if let usage = self.status.usage {
                    Text(UsageDisplaySettings.identityText(
                        accountLabel: usage.accountLabel,
                        sourceLabel: usage.sourceLabel,
                        showsAccountIdentifiers: self.showsAccountIdentifiers))
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let usage = self.status.usage {
                ForEach(usage.metrics) { metric in
                    UsageMetricRow(
                        metric: metric,
                        meterColor: ProviderBrand.meterColor(for: self.status.provider),
                        resetDisplayMode: self.resetDisplayMode)
                }
            } else if let error = self.status.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Loading usage…")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            if let usage = self.status.usage, let error = self.status.errorMessage {
                // Naming the age of the numbers is the difference between "this
                // refresh failed" and knowing whether the figures above are
                // minutes or hours out of date.
                Label(
                    "Showing data from \(usage.fetchedAt.formatted(.relative(presentation: .named))) · \(error)",
                    systemImage: "clock.arrow.circlepath")
                    .font(AppFont.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppLayout.cardPadding)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .fill(self.brandColor.opacity(self.colorScheme == .dark ? 0.10 : 0.07))
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardCornerRadius, style: .continuous)
                .stroke(self.brandColor.opacity(0.22), lineWidth: 1)
        }
    }

    private var brandColor: Color {
        ProviderBrand.color(for: self.status.provider, colorScheme: self.colorScheme)
    }

}

private struct UsageMetricRow: View {
    let metric: UsageMetric
    let meterColor: Color
    let resetDisplayMode: UsageResetDisplayMode

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(self.metric.label)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(self.metric.remainingPercent.rounded()))% left")
                    .font(AppFont.captionMonospacedMedium)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(self.meterColor.opacity(0.12))
                    Capsule()
                        .fill(self.meterColor)
                        .frame(width: proxy.size.width * self.metric.remainingPercent / 100)
                }
            }
            .frame(height: 6)

            if let resetText = self.resetText {
                HStack {
                    Spacer()
                    Text(resetText)
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var resetText: String? {
        UsageResetDescriptionFormatter.displayText(
            resetsAt: self.metric.resetsAt,
            resetDescription: self.metric.resetDescription,
            mode: self.resetDisplayMode)
    }
}
