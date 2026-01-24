import Foundation
import Observation

public enum AppSettings {
    public enum Key {
        public static let forwardCLIErrors = "ForwardCLIErrorToGUI"
        public static let switcherMaxItems = "SwitcherMaxItems"
        public static let settingsAlwaysOnTop = "SettingsAlwaysOnTop"
    }

    public static let minSwitcherItems = 3
    public static let maxSwitcherItems = 10
    public static let defaultSwitcherMaxItems = 9

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.forwardCLIErrors: true,
            Key.switcherMaxItems: defaultSwitcherMaxItems,
            Key.settingsAlwaysOnTop: false,
        ])
    }

    public static var forwardCLIErrors: Bool {
        UserDefaults.standard.bool(forKey: Key.forwardCLIErrors)
    }

    public static func clampSwitcherMaxItems(_ value: Int) -> Int {
        min(max(value, minSwitcherItems), maxSwitcherItems)
    }
}

@MainActor
@Observable
public final class AppSettingsStore {
    public var forwardCLIErrors: Bool {
        didSet {
            UserDefaults.standard.set(forwardCLIErrors, forKey: AppSettings.Key.forwardCLIErrors)
        }
    }

    public var switcherMaxItems: Int {
        didSet {
            let value = AppSettings.clampSwitcherMaxItems(switcherMaxItems)
            if value != switcherMaxItems {
                switcherMaxItems = value
                return
            }
            UserDefaults.standard.set(value, forKey: AppSettings.Key.switcherMaxItems)
        }
    }

    public var settingsAlwaysOnTop: Bool {
        didSet {
            UserDefaults.standard.set(settingsAlwaysOnTop, forKey: AppSettings.Key.settingsAlwaysOnTop)
        }
    }

    public init() {
        AppSettings.registerDefaults()
        self.forwardCLIErrors = UserDefaults.standard.bool(forKey: AppSettings.Key.forwardCLIErrors)
        self.switcherMaxItems = AppSettings.clampSwitcherMaxItems(
            UserDefaults.standard.integer(forKey: AppSettings.Key.switcherMaxItems)
        )
        self.settingsAlwaysOnTop = UserDefaults.standard.bool(forKey: AppSettings.Key.settingsAlwaysOnTop)
    }
}
