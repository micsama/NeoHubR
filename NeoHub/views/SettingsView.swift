import KeyboardShortcuts
import NeoHubLib
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    static let defaultWidth: CGFloat = 400

    @ObservedObject var cli: CLI
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var projectRegistry: ProjectRegistryStore

    @State var runningCLIAction: Bool = false
    @State private var launchAtLoginEnabled: Bool = false
    private let glassAvailable = AppSettings.isGlassAvailable

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image("EditorIcon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.gray)
                Text("NeoHub")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
            }
            TabView {
                GeneralSettingsTab(
                    cli: cli,
                    appSettings: appSettings,
                    runningCLIAction: $runningCLIAction,
                    launchAtLoginEnabled: $launchAtLoginEnabled,
                    glassAvailable: glassAvailable
                )
                .tabItem { Text("General") }
                ProjectRegistryTab(
                    appSettings: appSettings,
                    projectRegistry: projectRegistry
                )
                .tabItem { Text("Projects") }
                AdvancedSettingsTab(
                    appSettings: appSettings,
                    glassAvailable: glassAvailable
                )
                .tabItem { Text("Advanced") }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}

private struct GeneralSettingsTab: View {
    @ObservedObject var cli: CLI
    @ObservedObject var appSettings: AppSettingsStore
    @Binding var runningCLIAction: Bool
    @Binding var launchAtLoginEnabled: Bool

    let glassAvailable: Bool

    var body: some View {
        VStack(spacing: 20) {
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
            }
            .settingsGroup()
            VStack(spacing: 20) {
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
                        HStack(spacing: 16) {
                            Button("Reinstall") {
                                self.runningCLIAction = true
                                Task { @MainActor in
                                    _ = await cli.run(.install)
                                    self.runningCLIAction = false
                                }
                            }
                            .buttonStyle(LinkButtonStyle())
                            .disabled(self.runningCLIAction)
                            .focusable()
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
                        }
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}

private struct AdvancedSettingsTab: View {
    @ObservedObject var appSettings: AppSettingsStore

    let glassAvailable: Bool

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 0) {
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

                HStack {
                    Text("Show CLI errors in app")
                    Spacer()
                    Toggle("", isOn: $appSettings.forwardCLIErrors)
                        .toggleStyle(SwitchToggleStyle())
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .settingsGroup()
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

private struct ProjectRegistryTab: View {
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var projectRegistry: ProjectRegistryStore

    @State private var sliderValue: Double = Double(AppSettings.defaultSwitcherMaxItems)

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 0) {
                HStack {
                    Text("Switcher Items")
                    Spacer()
                    Text("\(appSettings.switcherMaxItems)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal)
                .padding(.top, 10)
                .padding(.bottom, 6)

                HStack {
                    Slider(
                        value: $sliderValue,
                        in: Double(AppSettings.minSwitcherItems)...Double(AppSettings.maxSwitcherItems),
                        step: 1
                    )
                    .applyLiquidGlassSliderStyle()
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .settingsGroup()

            VStack(spacing: 0) {
                HStack {
                    Text("Starred Projects")
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider().padding(.horizontal)

                List {
                    Section("Starred") {
                        if starredEntries.isEmpty {
                            Text("No starred projects yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(starredEntries) { entry in
                                ProjectRow(entry: entry, projectRegistry: projectRegistry)
                            }
                            .onMove { indices, newOffset in
                                var ids = starredEntries.map { $0.id }
                                ids.move(fromOffsets: indices, toOffset: newOffset)
                                projectRegistry.updatePinnedOrder(ids: ids)
                            }
                            .moveDisabled(false)
                        }
                    }
                    Section("Recent") {
                        if recentEntries.isEmpty {
                            Text("No recent projects yet.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(recentEntries) { entry in
                                ProjectRow(entry: entry, projectRegistry: projectRegistry)
                            }
                        }
                    }
                }
                .frame(height: 260)
            }
            .settingsGroup()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .onAppear {
            sliderValue = Double(appSettings.switcherMaxItems)
        }
        .onChange(of: sliderValue) { newValue in
            appSettings.switcherMaxItems = Int(newValue.rounded())
        }
    }

    private var starredEntries: [ProjectEntry] {
        projectRegistry.entries
            .filter { $0.isStarred }
            .sorted { lhs, rhs in
                let lhsOrder = lhs.pinnedOrder ?? Int.max
                let rhsOrder = rhs.pinnedOrder ?? Int.max
                if lhsOrder != rhsOrder {
                    return lhsOrder < rhsOrder
                }
                return (lhs.lastOpenedAt ?? .distantPast) > (rhs.lastOpenedAt ?? .distantPast)
            }
    }

    private var recentEntries: [ProjectEntry] {
        projectRegistry.entries
            .filter { !$0.isStarred }
            .sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
    }

}

private struct ProjectRow: View {
    let entry: ProjectEntry
    @ObservedObject var projectRegistry: ProjectRegistryStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.isStarred ? "star.circle.fill" : "folder.fill")
                .foregroundColor(entry.isStarred ? .yellow : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name ?? entry.id.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                Text(SettingsPath.format(entry.id))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(action: { projectRegistry.toggleStar(id: entry.id) }) {
                Image(systemName: entry.isStarred ? "star.fill" : "star")
                    .foregroundColor(entry.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 2)
    }
}

private enum SettingsPath {
    static func format(_ url: URL) -> String {
        let fullPath = url.path(percentEncoded: false)
        let pattern = "^/Users/[^/]+/"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return fullPath
        }

        let range = NSRange(fullPath.startIndex..., in: fullPath)
        return regex.stringByReplacingMatches(
            in: fullPath,
            options: [],
            range: range,
            withTemplate: "~/"
        )
    }
}

private extension View {
    @ViewBuilder
    func applyLiquidGlassSliderStyle() -> some View {
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular.interactive())
                .controlSize(.large)
        } else {
            self
                .controlSize(.large)
        }
    }
}
