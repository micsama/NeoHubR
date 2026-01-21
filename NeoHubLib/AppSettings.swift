import Combine
import Foundation

public enum AppSettings {
    public enum Key {
        public static let forwardCLIErrors = "ForwardCLIErrorToGUI"
        public static let useGlassSwitcherUI = "UseGlassSwitcherUI"
        public static let switcherMaxItems = "SwitcherMaxItems"
    }

    public static var isGlassAvailable: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    public static var defaultUseGlassSwitcherUI: Bool {
        isGlassAvailable
    }

    public static let minSwitcherItems = 3
    public static let maxSwitcherItems = 10
    public static let defaultSwitcherMaxItems = 9

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.forwardCLIErrors: true,
            Key.useGlassSwitcherUI: defaultUseGlassSwitcherUI,
            Key.switcherMaxItems: defaultSwitcherMaxItems
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
public final class AppSettingsStore: ObservableObject {
    @Published public var forwardCLIErrors: Bool {
        didSet {
            UserDefaults.standard.set(forwardCLIErrors, forKey: AppSettings.Key.forwardCLIErrors)
        }
    }

    @Published public var useGlassSwitcherUI: Bool {
        didSet {
            UserDefaults.standard.set(useGlassSwitcherUI, forKey: AppSettings.Key.useGlassSwitcherUI)
        }
    }

    @Published public var switcherMaxItems: Int {
        didSet {
            let value = AppSettings.clampSwitcherMaxItems(switcherMaxItems)
            if value != switcherMaxItems {
                switcherMaxItems = value
                return
            }
            UserDefaults.standard.set(value, forKey: AppSettings.Key.switcherMaxItems)
        }
    }

    public init() {
        AppSettings.registerDefaults()
        self.forwardCLIErrors = UserDefaults.standard.bool(forKey: AppSettings.Key.forwardCLIErrors)
        self.useGlassSwitcherUI = UserDefaults.standard.bool(forKey: AppSettings.Key.useGlassSwitcherUI)
        self.switcherMaxItems = AppSettings.clampSwitcherMaxItems(
            UserDefaults.standard.integer(forKey: AppSettings.Key.switcherMaxItems)
        )
    }
}
