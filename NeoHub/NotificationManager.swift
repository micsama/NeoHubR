import NeoHubLib
import UserNotifications

typealias NotificationMeta = [String: String]

private let cliErrorCategoryId = "CLI_ERROR"

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
        }
    }

    var title: String {
        switch self {
        case .failedToLaunchServer:
            return String(localized: "Failed to launch the NeoHub server")
        case .failedToHandleRequestFromCLI, .failedToRunEditorProcess:
            return String(localized: "Failed to open Neovide")
        case .failedToGetRunningEditorApp, .failedToActivateEditorApp:
            return String(localized: "Failed to activate Neovide")
        }
    }

    var body: String {
        switch self {
        case .failedToLaunchServer:
            return String(
                localized: "NeoHub won't be able to function properly. Please, create an issue in the GitHub repo."
            )
        case .failedToHandleRequestFromCLI, .failedToRunEditorProcess:
            return String(localized: "Please create an issue in the GitHub repo.")
        case .failedToGetRunningEditorApp:
            return String(localized: "Requested Neovide instance is not running.")
        case .failedToActivateEditorApp:
            return String(localized: "Please create an issue in GitHub repo.")
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

protocol NotificationAction: Sendable {
    static var id: String { get }
    static var button: String { get }

    static var built: UNNotificationAction { get }

    var meta: NotificationMeta { get }

    init?(from meta: NotificationMeta)

    func run()
}

extension NotificationAction {
    static var built: UNNotificationAction {
        UNNotificationAction(
            identifier: Self.id,
            title: Self.button,
            options: []
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
        let cliErrorCategory = UNNotificationCategory(
            identifier: cliErrorCategoryId,
            actions: [ReportAction.built],
            intentIdentifiers: [],
            hiddenPreviewsBodyPlaceholder: "",
            options: .customDismissAction
        )
        let categories = Set(NotificationKind.allCases.map { $0.category })
            .union([cliErrorCategory])

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    private enum AuthStatus {
        case unknown
        case granted
        case rejected
    }

    private var status: AuthStatus = .unknown

    private func requestAuthorization(completion: @Sendable @escaping (Bool) -> Void) {
        switch self.status {
        case .unknown:
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                MainThread.run {
                    switch (granted, error) {
                    case (true, nil):
                        self.status = .granted
                        completion(true)
                    case (true, .some(let error)):
                        log.notice("There was an error during notification authorization request. \(error)")
                        self.status = .granted
                        completion(true)
                    case (false, let error):
                        log.info("Notification permission not granted. \(String(describing: error))")
                        self.status = .rejected
                        completion(false)
                    }
                }
            }
        case .granted:
            completion(true)
        case .rejected:
            completion(false)
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
            categoryId: cliErrorCategoryId,
            title: String(localized: "CLI Error"),
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
        switch response.actionIdentifier {
        case ReportAction.id:
            let meta = NotificationMeta(userInfo: response.notification.request.content.userInfo)
            if let action = ReportAction(from: meta) {
                DispatchQueue.global().async {
                    action.run()
                }
            }
            break
        default:
            break
        }

        completionHandler()
    }
}

struct ReportAction: NotificationAction {
    static let id: String = "REPORT_ACTION"
    static let button: String = String(localized: "Report")

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
