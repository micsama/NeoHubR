import AppKit
import KeyboardShortcuts
import NeoHubLib
import Observation
import SwiftUI
import UserNotifications

// MARK: - Main Settings View

struct SettingsView: View {
    @Bindable var cli: CLI
    @Bindable var appSettings: AppSettingsStore
    @Bindable var projectRegistry: ProjectRegistryStore

    @State private var runningCLIAction = false

    var body: some View {
        TabView {
            GeneralSettingsTab(
                cli: cli,
                runningCLIAction: $runningCLIAction,
                appSettings: appSettings
            )
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            ProjectRegistryTab(
                appSettings: appSettings,
                projectRegistry: projectRegistry
            )
            .tabItem {
                Label("Projects", systemImage: "folder")
            }

            AdvancedSettingsTab(appSettings: appSettings)
                .tabItem {
                    Label("Advanced", systemImage: "gearshape.2")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .background(SettingsWindowLevelUpdater(alwaysOnTop: appSettings.settingsAlwaysOnTop))
        .frame(minWidth: 375, idealWidth: 375, minHeight: 350, idealHeight: 350)
        .fixedSize(horizontal: true, vertical: true)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

private struct SettingsWindowLevelUpdater: NSViewRepresentable {
    let alwaysOnTop: Bool

    func makeNSView(context _: Context) -> SettingsWindowLevelView {
        SettingsWindowLevelView()
    }

    func updateNSView(_ nsView: SettingsWindowLevelView, context _: Context) {
        nsView.alwaysOnTop = alwaysOnTop
    }
}

private final class SettingsWindowLevelView: NSView {
    var alwaysOnTop: Bool = false {
        didSet { updateLevelIfNeeded() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLevelIfNeeded()
    }

    private func updateLevelIfNeeded() {
        guard let window = window else { return }
        let level: NSWindow.Level = alwaysOnTop ? .floating : .normal
        if window.level != level {
            window.level = level
        }
    }
}

// MARK: - General Tab

private struct GeneralSettingsTab: View {
    @Bindable var cli: CLI
    @Binding var runningCLIAction: Bool
    @Bindable var appSettings: AppSettingsStore

    var body: some View {
        VStack(spacing: 0) {
            // Header 放在 Form 外部，透明背景，垂直居中
            headerView
                .frame(height: 70, alignment: .center)
            Form {
                Section {
                    Toggle(
                        "Launch at Login",
                        isOn: Binding(
                            get: { appSettings.launchAtLogin },
                            set: { appSettings.launchAtLogin = $0 }
                        )
                    )
                }

                Section {
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

                Section {
                    CLIStatusView(cli: cli, runningCLIAction: $runningCLIAction)
                }
            }
            .formStyle(.grouped)
            .padding(.top, -10)
        }
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            Image("EditorIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text("NeoHub")
                    .font(.system(size: 18, weight: .semibold))
                Text("v\(APP_VERSION) (\(APP_BUILD))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

}
// MARK: - CLI Status View

private struct CLIStatusView: View {
    @Bindable var cli: CLI
    @Binding var runningCLIAction: Bool
    @State private var didCopyPath = false

    var body: some View {
        switch cli.status {
        case .ok:
            installedView

        case .error(reason: .notInstalled):
            installRequiredView

        case .error(reason: .versionMismatch):
            updateRequiredView

        case .error(reason: .unexpectedError(let error)):
            errorView(error)
        }

    }

    private var installedView: some View {
        statusRow(
            title: { statusTitle("CLI Installed", color: .primary, bold: false) },
            subtitle: { pathSubtitle }
        ) {
            HStack(spacing: 12) {
                Button("Reinstall") { runCLI(.install) }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                Button("Uninstall") { runCLI(.uninstall) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .disabled(runningCLIAction)
        }
    }

    private var installRequiredView: some View {
        statusRow(
            title: { Text("CLI Install Required").font(.title3).foregroundStyle(.red) },
            subtitle: { EmptyView() }
        ) {
            Button("Install") { runCLI(.install) }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(runningCLIAction)
        }
    }

    private var updateRequiredView: some View {
        statusRow(
            title: { statusTitle("CLI Update Required", color: .orange, bold: true) },
            subtitle: { pathSubtitle }
        ) {
            HStack(spacing: 12) {
                Button("Update") { runCLI(.install) }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                Button("Uninstall") { runCLI(.uninstall) }
                    .buttonStyle(.bordered)
                    .tint(.red)
            }
            .disabled(runningCLIAction)
        }
    }

    private func errorView(_ error: Error) -> some View {
        statusRow(
            title: { statusTitle("CLI Error", color: .red, bold: true) },
            subtitle: {
                Text("Check logs for details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            },
            useStatusIcon: false
        ) {
            Button("Report Issue") {
                BugReporter.report(ReportableError("CLI failed to report a status", error: error))
            }
        }
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
    private func statusRow<Title: View, Action: View, Subtitle: View>(
        @ViewBuilder title: () -> Title,
        @ViewBuilder subtitle: () -> Subtitle,
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
                title()
                subtitle()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            action()
                .fixedSize()
                .frame(alignment: .trailing)
                .layoutPriority(0)
        }
    }

    private func statusTitle(_ title: LocalizedStringKey, color: Color, bold: Bool) -> Text {
        let text = Text(title).foregroundStyle(color)
        return bold ? text.bold() : text
    }

    private var pathSubtitle: some View {
        Button {
            copyPath()
        } label: {
            Text(CLI.binPath)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .opacity(0)
                .overlay(alignment: .leading) {
                    Text(didCopyPath ? String(localized: "Copied to clipboard") : CLI.binPath)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(didCopyPath ? AnyShapeStyle(.secondary) : AnyShapeStyle(.blue))
                }
        }
        .buttonStyle(.plain)
    }

    private func copyPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(CLI.binPath, forType: .string)
        didCopyPath = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            didCopyPath = false
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
    @Bindable var appSettings: AppSettingsStore
    @Bindable var projectRegistry: ProjectRegistryStore

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
                    if projectRegistry.starredEntries.isEmpty {
                        Text("No starred projects")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(projectRegistry.starredEntries) { entry in
                            ProjectRow(entry: entry, projectRegistry: projectRegistry)
                        }
                        .onMove { indices, newOffset in
                            var ids = projectRegistry.starredEntries.map { $0.id }
                            ids.move(fromOffsets: indices, toOffset: newOffset)
                            projectRegistry.updatePinnedOrder(ids: ids)
                        }
                    }
                }

                Section("Recent") {
                    if projectRegistry.recentEntries.isEmpty {
                        Text("No recent projects")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(projectRegistry.recentEntries) { entry in
                            ProjectRow(entry: entry, projectRegistry: projectRegistry)
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Advanced Tab

private struct AdvancedSettingsTab: View {
    @Bindable var appSettings: AppSettingsStore
    @State private var notificationStatusText = "Unknown"

    var body: some View {
        Form {
            Section {
                Toggle("Keep Settings Window on Top", isOn: $appSettings.settingsAlwaysOnTop)

                Toggle("Show CLI errors in app", isOn: $appSettings.forwardCLIErrors)
            }

            Section("About") {
                LabeledContent("Version") {
                    Text("\(APP_VERSION) (\(APP_BUILD))")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Notification Permission") {
                    Text(notificationStatusText)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let text: String
            switch settings.authorizationStatus {
            case .notDetermined:
                text = String(localized: "Not Determined")
            case .denied:
                text = String(localized: "Denied")
            case .authorized:
                text = String(localized: "Authorized")
            case .provisional:
                text = String(localized: "Provisional")
            case .ephemeral:
                text = String(localized: "Ephemeral")
            @unknown default:
                text = String(localized: "Unknown")
            }

            await MainActor.run {
                notificationStatusText = text
            }
        }
    }
}

// MARK: - About Tab

private struct AboutSettingsTab: View {
    private var versionText: String {
        String(format: String(localized: "Version %@ (%@)"), APP_VERSION, APP_BUILD)
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)

            Text(APP_NAME)
                .font(.title2)
                .fontWeight(.semibold)

            Text(versionText)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            VStack(spacing: 4) {
                Text("© 2023 Alex Fedoseev")

                HStack(spacing: 2) {
                    Text("Icon by")
                    Link("u/danbee", destination: URL(string: "https://www.reddit.com/user/danbee/")!)
                        .foregroundStyle(.link)
                        .focusable(false)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let entry: ProjectEntry
    @Bindable var projectRegistry: ProjectRegistryStore

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

#Preview {
    SettingsView(
        cli: CLI(),
        appSettings: AppSettingsStore(),
        projectRegistry: ProjectRegistryStore()
    )
}
