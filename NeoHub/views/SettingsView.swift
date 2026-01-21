import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let defaultWidth: CGFloat = 400

    @ObservedObject var cli: CLI
    @ObservedObject var appSettings: AppSettingsStore

    @State var runningCLIAction: Bool = false
    @State private var launchAtLoginEnabled: Bool = false
    private let glassAvailable = AppSettings.isGlassAvailable

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image("EditorIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .foregroundColor(.gray)
                Text("NeoHub").font(.title)
            }
            VStack(spacing: 0) {
                HStack {
                    Text("Launch at Login")
                    Spacer()
                    Toggle("", isOn: $launchAtLoginEnabled)
                        .toggleStyle(SwitchToggleStyle())
                        .onChange(of: launchAtLoginEnabled) { newValue in
                            do {
                                if newValue {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                log.error("Failed to update launch at login: \(error)")
                                launchAtLoginEnabled = isLaunchAtLoginEnabled()
                            }
                        }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider().padding(.horizontal)

                HStack {
                    Text("Toggle Editor Selector")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleSwitcher)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                HStack {
                    Text("Toggle Last Active Editor")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .toggleLastActiveEditor)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider().padding(.horizontal)

                HStack {
                    Text("Restart Active Editor")
                    Spacer()
                    KeyboardShortcuts.Recorder("", name: .restartEditor)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                HStack {
                    Text("Use Liquid Glass Switcher (macOS 26)")
                    Spacer()
                    Toggle("", isOn: $appSettings.useGlassSwitcherUI)
                        .toggleStyle(SwitchToggleStyle())
                }
                .opacity(glassAvailable ? 1.0 : 0.5)
                .disabled(!glassAvailable)
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .settingsGroup()
            Text("CLI").font(.title)
            VStack(spacing: 20) {
                HStack {
                    Text("Show CLI errors in app")
                    Spacer()
                    Toggle("", isOn: $appSettings.forwardCLIErrors)
                        .toggleStyle(SwitchToggleStyle())
                }
                switch cli.status {
                case .ok:
                    VStack(spacing: 10) {
                        if self.runningCLIAction {
                            InstallationView.Spinner()
                        } else {
                            Image(systemName: "gear.badge.checkmark")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.green, Color.gray)
                                .font(.system(size: 32))
                            Text("Installed")
                        }
                    }
                    Divider()
                    VStack(spacing: 10) {
                        Button("Uninstall") {
                            self.runningCLIAction = true
                            Task { @MainActor in
                                _ = await cli.run(.uninstall)
                                self.runningCLIAction = false
                            }
                        }
                        .buttonStyle(LinkButtonStyle())
                        .disabled(self.runningCLIAction)
                        .focusable()
                        InstallationView.ButtonNote()
                    }
                case .error(reason: .notInstalled):
                    VStack(spacing: 10) {
                        if self.runningCLIAction {
                            InstallationView.Spinner()
                        } else {
                            Image(systemName: "gear.badge.xmark")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.red, Color.gray)
                                .font(.system(size: 32))
                            Text("Not Installed")
                        }
                    }
                    VStack(spacing: 10) {
                        Button("Install") {
                            self.runningCLIAction = true
                            Task { @MainActor in
                                _ = await cli.run(.install)
                                self.runningCLIAction = false
                            }
                        }
                        .disabled(self.runningCLIAction)
                        .focusable()
                        InstallationView.ButtonNote()
                    }
                case .error(reason: .versionMismatch):
                    VStack(spacing: 10) {
                        if self.runningCLIAction {
                            InstallationView.Spinner()
                        } else {
                            Image(systemName: "gear.badge")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(Color.yellow, Color.gray)
                                .font(.system(size: 32))
                            Text("Needs Update")
                        }
                    }
                    VStack(spacing: 20) {
                        Button("Update") {
                            self.runningCLIAction = true
                            Task { @MainActor in
                                _ = await cli.run(.install)
                                self.runningCLIAction = false
                            }
                        }
                        .disabled(self.runningCLIAction)
                        .focusable()
                        Divider()
                        Button("Uninstall") {
                            self.runningCLIAction = true
                            Task { @MainActor in
                                _ = await cli.run(.uninstall)
                                self.runningCLIAction = false
                            }
                        }
                        .buttonStyle(LinkButtonStyle())
                        .disabled(self.runningCLIAction)
                        .focusable()
                        InstallationView.ButtonNote()
                    }
                case .error(reason: .unexpectedError(let error)):
                    VStack(spacing: 10) {
                        Image(systemName: "gear.badge.xmark")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.red, Color.gray)
                            .font(.system(size: 32))
                        Text("Unexpected Error")
                    }
                    Button("Create an Issue on GitHub") {
                        BugReporter.report(ReportableError("CLI failed to report a status", error: error))
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .settingsGroup()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .onAppear {
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}
