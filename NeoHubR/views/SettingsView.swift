import AppKit
import KeyboardShortcuts
import NeoHubRLib
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
        }
        .background(SettingsWindowLevelUpdater(alwaysOnTop: appSettings.settingsAlwaysOnTop))
        .frame(minWidth: 350, idealWidth: 350, minHeight: 345, idealHeight: 345)
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
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(String(localized: "NeoHubR"))
                    .font(.system(size: 18, weight: .semibold))
                HStack(spacing: 2) {
                    Text(String(localized: "Icon by"))
                    Link(String(localized: "u/danbee"), destination: URL(string: "https://www.reddit.com/user/danbee/")!)
                        .foregroundStyle(.link)
                        .focusable(false)
                }
                .font(.caption2)
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
    @State private var showAddError = false
    @State private var addErrorMessage = ""
    @State private var isAddHovering = false

    var body: some View {
        VStack(spacing: 0) {
            // Slider Section
            Form {
                LabeledContent("Items") {
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

                        Spacer(minLength: 8)

                        Menu {
                            Button("Add Folder") {
                                openAddFolderPanel()
                            }
                            Button("Add Session") {
                                openAddSessionPanel()
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 20, height: 20)
                                .background(
                                    isAddHovering ? Color.secondary.opacity(0.12) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                                )
                                .onHover { isAddHovering = $0 }
                        }
                        .buttonStyle(.plain)
                        .help("Add Project")
                    }
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 64)

            // Project List
            List {
                Section("Starred") {
                    if projectRegistry.starredEntries.isEmpty {
                        Text("No starred projects")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(projectRegistry.starredEntries) { entry in
                            ProjectRow(
                                entry: entry,
                                isStarred: true,
                                isInvalid: projectRegistry.isInvalid(entry),
                                projectRegistry: projectRegistry
                            )
                        }
                        .onMove { indices, newOffset in
                            projectRegistry.moveStarred(fromOffsets: indices, toOffset: newOffset)
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
                            ProjectRow(
                                entry: entry,
                                isStarred: false,
                                isInvalid: projectRegistry.isInvalid(entry),
                                projectRegistry: projectRegistry
                            )
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .padding(.top, -6)
        }
        .onAppear {
            projectRegistry.refreshValidity()
        }
        .alert("Add Project Failed", isPresented: $showAddError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(addErrorMessage)
        }
    }

    private func openAddFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            projectRegistry.addProject(root: url)
        }
    }

    private func openAddSessionPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard url.pathExtension.lowercased() == "vim" else {
                addErrorMessage = String(localized: "Please select a .vim file.")
                showAddError = true
                return
            }
            let displayName = url.deletingPathExtension().lastPathComponent
            projectRegistry.addProject(root: url, name: displayName, sessionPath: url)
        }
    }
}


// MARK: - Advanced Tab

private struct AdvancedSettingsTab: View {
    @Bindable var appSettings: AppSettingsStore
    @State private var notificationStatus = UNAuthorizationStatus.notDetermined

    var body: some View {
        Form {
            Section {
                Toggle("Keep Settings Window on Top", isOn: $appSettings.settingsAlwaysOnTop)

                Toggle("Show CLI errors in app", isOn: $appSettings.forwardCLIErrors)
            }

            Section {
                LabeledContent("Notification Permission") {
                    if notificationStatus == .notDetermined || notificationStatus == .denied {
                        Button("Request Notification Permission") {
                            handleNotificationPermission()
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(notificationStatusText)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent("Version") {
                    Text("\(APP_VERSION) (\(APP_BUILD))")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Text(String(localized: "Alex Fedoseev · © 2026 micsama"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            refreshNotificationStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshNotificationStatus()
        }
    }

    private var notificationStatusText: String {
        switch notificationStatus {
        case .notDetermined:
            return String(localized: "Not Determined")
        case .denied:
            return String(localized: "Denied")
        case .authorized:
            return String(localized: "Authorized")
        case .provisional:
            return String(localized: "Provisional")
        case .ephemeral:
            return String(localized: "Ephemeral")
        @unknown default:
            return String(localized: "Unknown")
        }
    }

    private func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async {
                notificationStatus = status
            }
        }
    }

    private func handleNotificationPermission() {
        if notificationStatus == .notDetermined {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in
                Task { @MainActor in
                    refreshNotificationStatus()
                }
            }
            return
        }

        if notificationStatus == .denied {
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

// MARK: - Project Row

private struct ProjectRow: View {
    let entry: ProjectEntry
    let isStarred: Bool
    let isInvalid: Bool
    @Bindable var projectRegistry: ProjectRegistryStore
    @Environment(\.openWindow) private var openWindow
    @State private var deleteArmed = false
    @State private var deleteResetTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            ProjectIconView(
                entry: entry,
                fallbackSystemName: "folder.fill",
                size: 16,
                isInvalid: isInvalid,
                fallbackColor: .secondary
            )

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    titleText
                    if isInvalid {
                        Text("(\(String(localized: "Not available")))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    if entry.isSession {
                        Text("(\(String(localized: "Session")))")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Text(ProjectPathFormatter.displayPath(entry.id))
                    .font(.caption)
                    .foregroundStyle(isInvalid ? .quaternary : .tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                projectRegistry.toggleStar(id: entry.id)
            } label: {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? .yellow : .secondary)
            }
            .buttonStyle(.plain)

            Button {
                openWindow(id: "project-editor", value: entry.id)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Button {
                handleDeleteTap()
            } label: {
                Image(systemName: deleteArmed ? "trash.fill" : "trash")
                    .foregroundStyle(.red)
                    .symbolEffect(.bounce, value: deleteArmed)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var titleText: some View {
        let fallbackName = entry.isSession
            ? entry.id.deletingPathExtension().lastPathComponent
            : entry.id.lastPathComponent
        let text = Text(entry.name ?? fallbackName)
            .lineLimit(1)
            .foregroundStyle(isInvalid ? .secondary : .primary)

        if isInvalid {
            text.strikethrough().italic()
        } else {
            text
        }
    }

    private func handleDeleteTap() {
        if deleteArmed {
            projectRegistry.remove(id: entry.id)
            return
        }
        deleteArmed = true
        deleteResetTask?.cancel()
        deleteResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            deleteArmed = false
        }
    }
}

#Preview {
    SettingsView(
        cli: CLI(),
        appSettings: AppSettingsStore(),
        projectRegistry: ProjectRegistryStore()
    )
}
