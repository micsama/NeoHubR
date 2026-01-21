import KeyboardShortcuts
import NeoHubLib
import ServiceManagement
import SwiftUI

// MARK: - Main Settings View

struct SettingsView: View {
    static let defaultWidth: CGFloat = 500
    static let defaultHeight: CGFloat = 520

    @ObservedObject var cli: CLI
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var projectRegistry: ProjectRegistryStore

    @State private var runningCLIAction = false
    @State private var launchAtLoginEnabled = false

    private let glassAvailable = AppSettings.isGlassAvailable

    var body: some View {
        VStack(spacing: 12) {
            headerView

            TabView {
                GeneralSettingsTab(
                    cli: cli,
                    runningCLIAction: $runningCLIAction,
                    launchAtLoginEnabled: $launchAtLoginEnabled
                )
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(0)

                ProjectRegistryTab(
                    appSettings: appSettings,
                    projectRegistry: projectRegistry
                )
                .tabItem {
                    Label("Projects", systemImage: "folder")
                }
                .tag(1)

                AdvancedSettingsTab(
                    appSettings: appSettings,
                    glassAvailable: glassAvailable
                )
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }
                .tag(2)
            }
        }
        .padding(16)
        .frame(width: Self.defaultWidth, height: Self.defaultHeight)
        .onAppear {
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
        }
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            Image("EditorIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
            Text("NeoHub")
                .font(.system(size: 18, weight: .semibold))
            Spacer()
            Text("v\(APP_VERSION) (\(APP_BUILD))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @ObservedObject var cli: CLI
    @Binding var runningCLIAction: Bool
    @Binding var launchAtLoginEnabled: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Launch at Login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled) { newValue in
                        updateLaunchAtLogin(newValue)
                    }
            }

            Section("Keyboard Shortcuts") {
                LabeledContent("Toggle Editor Selector") {
                    KeyboardShortcuts.Recorder("", name: .toggleSwitcher)
                }

                LabeledContent("Toggle Last Active Editor") {
                    KeyboardShortcuts.Recorder("", name: .toggleLastActiveEditor)
                }

                LabeledContent("Restart Active Editor") {
                    KeyboardShortcuts.Recorder("", name: .restartEditor)
                }
            }

            Section("Command Line Tool") {
                CLIStatusView(cli: cli, runningCLIAction: $runningCLIAction)
            }
        }
        .formStyle(.grouped)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Failed to update launch at login: \(error)")
            launchAtLoginEnabled = isLaunchAtLoginEnabled()
        }
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let status = SMAppService.mainApp.status
        return status == .enabled || status == .requiresApproval
    }
}

// MARK: - CLI Status View

private struct CLIStatusView: View {
    @ObservedObject var cli: CLI
    @Binding var runningCLIAction: Bool

    var body: some View {
        switch cli.status {
        case .ok:
            statusRow(
                title: "Installed",
                subtitle: CLI.binPath
            ) {
                HStack(spacing: 12) {
                    Button("Reinstall") { runCLI(.install) }
                    Button("Uninstall") { runCLI(.uninstall) }
                }
                .disabled(runningCLIAction)
            }

        case .error(reason: .notInstalled):
            statusRow(
                title: "Not Installed",
                subtitle: CLI.binPath
            ) {
                Button("Install") { runCLI(.install) }
                    .disabled(runningCLIAction)
            }

        case .error(reason: .versionMismatch):
            statusRow(
                title: "Needs Update",
                subtitle: CLI.binPath
            ) {
                HStack(spacing: 12) {
                    Button("Update") { runCLI(.install) }
                    Button("Uninstall") { runCLI(.uninstall) }
                }
                .disabled(runningCLIAction)
            }

        case .error(reason: .unexpectedError(let error)):
            statusRow(
                title: "Unexpected Error",
                subtitle: "Check logs for details",
                useStatusIcon: false
            ) {
                Button("Report Issue") {
                    BugReporter.report(ReportableError("CLI failed to report a status", error: error))
                }
            }
        }

        Text("Requires administrator privileges")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if runningCLIAction {
            ProgressView()
                .controlSize(.small)
        } else {
            switch cli.status {
            case .ok:
                gearIcon(name: "gear.badge.checkmark", color: .green)
            case .error(reason: .notInstalled):
                gearIcon(name: "gear.badge.xmark", color: .orange)
            case .error(reason: .versionMismatch):
                gearIcon(name: "gear.badge", color: .orange)
            case .error(reason: .unexpectedError):
                gearIcon(name: "gear.badge.xmark", color: .red)
            }
        }
    }

    @ViewBuilder
    private func statusRow<Action: View>(
        title: String,
        subtitle: String,
        useStatusIcon: Bool = true,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if useStatusIcon {
                statusIcon
            } else {
                Image(systemName: "gear.badge.xmark")
                    .font(.system(size: 24))
                    .foregroundStyle(.red)
                    .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            action()
        }
    }

    private func gearIcon(name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 24))
            .foregroundStyle(color)
            .frame(width: 24, height: 24)
    }

    private func runCLI(_ action: CLIOperation) {
        runningCLIAction = true
        Task { @MainActor in
            _ = await cli.run(action)
            runningCLIAction = false
        }
    }
}

// MARK: - Projects Tab

private struct ProjectRegistryTab: View {
    @ObservedObject var appSettings: AppSettingsStore
    @ObservedObject var projectRegistry: ProjectRegistryStore

    var body: some View {
        VStack(spacing: 0) {
            // Slider Section
            Form {
                LabeledContent("Switcher Items") {
                    HStack(spacing: 8) {
                        Text("\(appSettings.switcherMaxItems)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)

                        Slider(
                            value: Binding(
                                get: { Double(appSettings.switcherMaxItems) },
                                set: { appSettings.switcherMaxItems = Int($0) }
                            ),
                            in: Double(AppSettings.minSwitcherItems)...Double(AppSettings.maxSwitcherItems),
                            step: 1
                        )
                        .frame(width: 140)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(height: 72)

            // Project List
            List {
                Section("Starred") {
                    if starredEntries.isEmpty {
                        Text("No starred projects")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(starredEntries) { entry in
                            ProjectRow(entry: entry, projectRegistry: projectRegistry)
                        }
                        .onMove { indices, newOffset in
                            var ids = starredEntries.map { $0.id }
                            ids.move(fromOffsets: indices, toOffset: newOffset)
                            projectRegistry.updatePinnedOrder(ids: ids)
                        }
                    }
                }

                Section("Recent") {
                    if recentEntries.isEmpty {
                        Text("No recent projects")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(recentEntries) { entry in
                            ProjectRow(entry: entry, projectRegistry: projectRegistry)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
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

// MARK: - Advanced Tab

private struct AdvancedSettingsTab: View {
    @ObservedObject var appSettings: AppSettingsStore
    let glassAvailable: Bool

    var body: some View {
        Form {
            Section {
                Toggle("Use Liquid Glass Switcher (macOS 26)", isOn: $appSettings.useGlassSwitcherUI)
                    .disabled(!glassAvailable)

                Toggle("Show CLI errors in app", isOn: $appSettings.forwardCLIErrors)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("\(APP_VERSION) (\(APP_BUILD))")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let entry: ProjectEntry
    @ObservedObject var projectRegistry: ProjectRegistryStore

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name ?? entry.id.lastPathComponent)
                    .lineLimit(1)

                Text(entry.id.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                projectRegistry.toggleStar(id: entry.id)
            } label: {
                Image(systemName: entry.isStarred ? "star.fill" : "star")
                    .foregroundStyle(entry.isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }
}
