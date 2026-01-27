import NeoHubRLib
@preconcurrency import UserNotifications

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    override init() {
        super.init()
        Self.registerCategories()
    }

    private static func registerCategories() {
        let categories = Set(Kind.allCases.map { $0.category })
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    nonisolated static func send(kind: Kind, error: ReportableError) {
        Task { @MainActor in
            shared.schedule(kind: kind, error: error)
        }
    }

    nonisolated static func sendCLIError(_ report: CLIErrorReport) {
        guard AppSettings.forwardCLIErrors else { return }
        Task { @MainActor in
            shared.scheduleCLIError(report)
        }
    }

    nonisolated static func sendInfo(title: String, body: String) {
        Task { @MainActor in
            shared.schedule(title: title, body: body)
        }
    }

    private func schedule(kind: Kind, error: ReportableError) {
        let meta = ReportAction(error: error).meta
        scheduleNotification(
            categoryId: kind.id,
            title: kind.title,
            body: kind.body,
            userInfo: meta
        )
    }

    private func scheduleCLIError(_ report: CLIErrorReport) {
        var meta: [String: String] = ["source": "cli"]
        if let detail = report.detail { meta["detail"] = detail }
        if let code = report.code { meta["code"] = String(code) }

        let reportable = ReportableError(report.message, meta: meta)
        let actionMeta = ReportAction(error: reportable).meta
        
        scheduleNotification(
            categoryId: Kind.cliError.id,
            title: Kind.cliError.title,
            body: report.message,
            userInfo: actionMeta
        )
    }

    private func schedule(title: String, body: String) {
        scheduleNotification(
            categoryId: "",
            title: title,
            body: body,
            userInfo: [:]
        )
    }

    private func scheduleNotification(
        categoryId: String,
        title: String,
        body: String,
        userInfo: [String: String]
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                if settings.authorizationStatus == .notDetermined {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                        if granted {
                            Task { @MainActor in
                                self.performSchedule(categoryId: categoryId, title: title, body: body, userInfo: userInfo)
                            }
                        }
                    }
                }
                return
            }
            
            Task { @MainActor in
                self.performSchedule(categoryId: categoryId, title: title, body: body, userInfo: userInfo)
            }
        }
    }

    private func performSchedule(
        categoryId: String,
        title: String,
        body: String,
        userInfo: [String: String]
    ) {
        let content = UNMutableNotificationContent()
        content.categoryIdentifier = categoryId
        content.title = title
        content.body = body
        content.userInfo = userInfo

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log.error("Error scheduling notification: \(error)")
            }
        }
    }
}

// MARK: - Delegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    func registerDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == ReportAction.id {
            let userInfo = response.notification.request.content.userInfo
            if let action = ReportAction(from: userInfo) {
                // BugReporter handles UI, so we can run on main or background.
                // BugReporter uses NSWorkspace.open which is thread safe.
                action.run()
            }
        }
        completionHandler()
    }
}

// MARK: - Supporting Types

extension NotificationManager {
    enum Kind: CaseIterable {
        case failedToLaunchServer
        case failedToHandleRequestFromCLI
        case failedToRunEditorProcess
        case failedToGetRunningEditorApp
        case failedToActivateEditorApp
        case failedToRestartEditor
        case cliUnexpectedError
        case cliError

        var id: String {
            switch self {
            case .failedToLaunchServer: return "FAILED_TO_LAUNCH_SERVER"
            case .failedToHandleRequestFromCLI: return "FAILED_TO_HANDLE_REQUEST_FROM_CLI"
            case .failedToRunEditorProcess: return "FAILED_TO_RUN_EDITOR_PROCESS"
            case .failedToGetRunningEditorApp: return "FAILED_TO_GET_RUNNING_EDITOR_APP"
            case .failedToActivateEditorApp: return "FAILED_TO_ACTIVATE_EDITOR_APP"
            case .failedToRestartEditor: return "FAILED_TO_RESTART_EDITOR"
            case .cliUnexpectedError: return "CLI_UNEXPECTED_ERROR"
            case .cliError: return "CLI_ERROR"
            }
        }

        var title: String {
            switch self {
            case .failedToLaunchServer: return String(localized: "Failed to launch the NeoHubR server")
            case .failedToHandleRequestFromCLI, .failedToRunEditorProcess: return String(localized: "Failed to open Neovide")
            case .failedToGetRunningEditorApp, .failedToActivateEditorApp: return String(localized: "Failed to activate Neovide")
            case .failedToRestartEditor: return String(localized: "Failed to restart the editor")
            case .cliUnexpectedError: return String(localized: "NeoHubR CLI error")
            case .cliError: return String(localized: "CLI Error")
            }
        }

        var body: String {
            switch self {
            case .failedToLaunchServer:
                return String(localized: "NeoHubR won't be able to function properly. Please, create an issue in the GitHub repo.")
            case .failedToHandleRequestFromCLI, .failedToRunEditorProcess, .failedToActivateEditorApp, .cliError:
                return String(localized: "Please create an issue in the GitHub repo.")
            case .failedToGetRunningEditorApp:
                return String(localized: "Requested Neovide instance is not running.")
            case .failedToRestartEditor:
                return String(localized: "Please, report the issue on GitHub.")
            case .cliUnexpectedError:
                return String(localized: "Please open Settings and check logs.")
            }
        }

        var category: UNNotificationCategory {
            UNNotificationCategory(
                identifier: id,
                actions: [ReportAction.built],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "",
                options: .customDismissAction
            )
        }
    }
}

private struct ReportAction {
    static let id = "REPORT_ACTION"
    static var built: UNNotificationAction {
        UNNotificationAction(identifier: id, title: String(localized: "Report"), options: [])
    }

    let title: String
    let error: String

    init(error: ReportableError) {
        self.title = error.message
        self.error = String(describing: error)
    }

    init?(from userInfo: [AnyHashable: Any]) {
        guard let title = userInfo["REPORT_TITLE"] as? String,
              let error = userInfo["REPORT_ERROR"] as? String
        else {
            log.warning("Failed to get metadata from notification userInfo")
            return nil
        }
        self.title = title
        self.error = error
    }

    var meta: [String: String] {
        ["REPORT_TITLE": title, "REPORT_ERROR": error]
    }

    func run() {
        BugReporter.report(title: title, error: error)
    }
}