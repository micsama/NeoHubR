import Combine
import Foundation

public enum AppSettings {
    public enum Key {
        public static let forwardCLIErrors = "ForwardCLIErrorToGUI"
        public static let useGlassSwitcherUI = "UseGlassSwitcherUI"
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

    public static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.forwardCLIErrors: true,
            Key.useGlassSwitcherUI: defaultUseGlassSwitcherUI
        ])
    }

    public static var forwardCLIErrors: Bool {
        UserDefaults.standard.bool(forKey: Key.forwardCLIErrors)
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

    public init() {
        AppSettings.registerDefaults()
        self.forwardCLIErrors = UserDefaults.standard.bool(forKey: AppSettings.Key.forwardCLIErrors)
        self.useGlassSwitcherUI = UserDefaults.standard.bool(forKey: AppSettings.Key.useGlassSwitcherUI)
    }
}
