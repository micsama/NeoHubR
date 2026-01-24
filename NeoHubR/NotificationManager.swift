import NeoHubRLib
import UserNotifications

typealias NotificationMeta = [String: String]

extension NotificationMeta {
    init(userInfo: [AnyHashable: Any]) {
        var meta: NotificationMeta = [:]
        for (key, value) in userInfo {
            if let key = key as? String, let value = value as? String {
                meta[key] = value
            }
        }
        self = meta
    }

    var userInfo: [AnyHashable: Any] {
        Dictionary(uniqueKeysWithValues: map { ($0.key, $0.value) })
    }
}

enum NotificationKind: CaseIterable {
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
        case .failedToLaunchServer:
            return "FAILED_TO_LAUNCH_SERVER"
        case .failedToHandleRequestFromCLI:
            return "FAILED_TO_HANDLE_REQUEST_FROM_CLI"
        case .failedToRunEditorProcess:
            return "FAILED_TO_RUN_EDITOR_PROCESS"
        case .failedToGetRunningEditorApp:
            return "FAILED_TO_GET_RUNNING_EDITOR_APP"
        case .failedToActivateEditorApp:
            return "FAILED_TO_ACTIVATE_EDITOR_APP"
        case .failedToRestartEditor:
            return "FAILED_TO_RESTART_EDITOR"
        case .cliUnexpectedError:
            return "CLI_UNEXPECTED_ERROR"
        case .cliError:
            return "CLI_ERROR"
        }
    }

    var title: String {
        switch self {
        case .failedToLaunchServer:
            return String(localized: "Failed to launch the NeoHubR server")
        case .failedToHandleRequestFromCLI, .failedToRunEditorProcess:
            return String(localized: "Failed to open Neovide")
        case .failedToGetRunningEditorApp, .failedToActivateEditorApp:
            return String(localized: "Failed to activate Neovide")
        case .failedToRestartEditor:
            return String(localized: "Failed to restart the editor")
        case .cliUnexpectedError:
            return String(localized: "NeoHubR CLI error")
        case .cliError:
            return String(localized: "CLI Error")
        }
    }

    var body: String {
        switch self {
        case .failedToLaunchServer:
            return String(
                localized: "NeoHubR won't be able to function properly. Please, create an issue in the GitHub repo."
            )
        case .failedToHandleRequestFromCLI, .failedToRunEditorProcess:
            return String(localized: "Please create an issue in the GitHub repo.")
        case .failedToGetRunningEditorApp:
            return String(localized: "Requested Neovide instance is not running.")
        case .failedToActivateEditorApp:
            return String(localized: "Please create an issue in GitHub repo.")
        case .failedToRestartEditor:
            return String(localized: "Please, report the issue on GitHub.")
        case .cliUnexpectedError:
            return String(localized: "Please open Settings and check logs.")
        case .cliError:
            return String(localized: "Please create an issue in the GitHub repo.")
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

@MainActor
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    override init() {
        Self.registerCategories()
        super.init()
    }

    static func registerCategories() {
        let categories = Set(NotificationKind.allCases.map { $0.category })
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    private func requestAuthorization(completion: @Sendable @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    MainThread.run {
                        if let error {
                            log.notice("There was an error during notification authorization request. \(error)")
                        }
                        completion(granted || error != nil)
                    }
                }
            case .authorized, .provisional, .ephemeral:
                MainThread.run {
                    completion(true)
                }
            case .denied:
                MainThread.run {
                    completion(false)
                }
            @unknown default:
                MainThread.run {
                    completion(false)
                }
            }
        }
    }

    nonisolated static func send(kind: NotificationKind, error: ReportableError) {
        Task { @MainActor in
            NotificationManager.shared.sendOnMain(kind: kind, error: error)
        }
    }

    nonisolated static func sendCLIError(_ report: CLIErrorReport) {
        guard AppSettings.forwardCLIErrors else {
            return
        }
        Task { @MainActor in
            NotificationManager.shared.sendCLIErrorOnMain(report)
        }
    }

    private func sendOnMain(kind: NotificationKind, error: ReportableError) {
        MainThread.assert()
        let meta = ReportAction(error: error).meta
        scheduleNotification(
            categoryId: kind.id,
            title: kind.title,
            body: kind.body,
            meta: meta
        )
    }

    private func sendCLIErrorOnMain(_ report: CLIErrorReport) {
        MainThread.assert()
        var meta: [String: String] = ["source": "cli"]
        if let detail = report.detail {
            meta["detail"] = detail
        }
        if let code = report.code {
            meta["code"] = String(code)
        }

        let reportable = ReportableError(report.message, meta: meta)
        let actionMeta = ReportAction(error: reportable).meta
        scheduleNotification(
            categoryId: NotificationKind.cliError.id,
            title: NotificationKind.cliError.title,
            body: report.message,
            meta: actionMeta
        )
    }

    private func scheduleNotification(
        categoryId: String,
        title: String,
        body: String,
        meta: NotificationMeta
    ) {
        MainThread.assert()
        self.requestAuthorization { granted in
            guard granted else {
                return
            }

            let content = UNMutableNotificationContent()
            content.categoryIdentifier = categoryId
            content.title = title
            content.body = body
            content.userInfo = meta.userInfo

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: trigger
            )

            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    log.error("Error scheduling notification: \(error)")
                }
            }
        }
    }

    nonisolated static func sendInfo(title: String, body: String) {
        Task { @MainActor in
            NotificationManager.shared.sendInfoOnMain(title: title, body: body)
        }
    }

    private func sendInfoOnMain(title: String, body: String) {
        MainThread.assert()
        scheduleNotification(
            categoryId: "",
            title: title,
            body: body,
            meta: [:]
        )
    }
}

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
            let meta = NotificationMeta(userInfo: response.notification.request.content.userInfo)
            if let action = ReportAction(from: meta) {
                DispatchQueue.global().async {
                    action.run()
                }
            }
        }

        completionHandler()
    }
}

struct ReportAction {
    static let id: String = "REPORT_ACTION"
    static let button: String = String(localized: "Report")
    static var built: UNNotificationAction {
        UNNotificationAction(
            identifier: id,
            title: button,
            options: []
        )
    }

    let title: String
    let error: String

    init(error: ReportableError) {
        self.title = error.message
        self.error = String(describing: error)
    }

    var meta: NotificationMeta {
        [
            "REPORT_TITLE": title,
            "REPORT_ERROR": error,
        ]
    }

    init?(from meta: NotificationMeta) {
        guard let title = meta["REPORT_TITLE"],
            let error = meta["REPORT_ERROR"]
        else {
            log.warning("Failed to get metadata from notification. Meta: \(meta)")
            return nil
        }

        self.title = title
        self.error = error
    }

    func run() {
        BugReporter.report(
            title: self.title,
            error: self.error
        )
    }
}
