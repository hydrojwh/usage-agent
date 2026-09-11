import ServiceManagement
import SwiftUI
import UsageCore

/// Optional "Start at Login" toggle (SMAppService.mainApp). Registered only
/// when the user opts in; off by default. Keeps the widget and menu-bar label
/// fresh without a separate launcher.
struct LoginItemToggle: View {
    @State private var isRegistered = LoginItemToggle.isCurrentlyRegistered
    @State private var registrationError: String?

    var body: some View {
        Toggle("Start at Login", isOn: self.registrationBinding)
            .toggleStyle(.switch)
            .controlSize(.mini)
            .font(AppFont.caption)
            .help(self.helpText)
            .onAppear {
                self.isRegistered = Self.isCurrentlyRegistered
            }
    }

    private var registrationBinding: Binding<Bool> {
        Binding(
            get: { self.isRegistered },
            set: { newValue in
                self.isRegistered = newValue
                self.syncRegistration(newValue)
            })
    }

    private var helpText: String {
        if let registrationError {
            return registrationError
        }
        return "Run \(UsageBrand.displayName) automatically when you log in."
    }

    private static var isCurrentlyRegistered: Bool {
        SMAppService.mainApp.status == .enabled
    }

    private func syncRegistration(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            self.registrationError = nil
        } catch {
            self.isRegistered = Self.isCurrentlyRegistered
            self.registrationError = error.localizedDescription
        }
    }
}
