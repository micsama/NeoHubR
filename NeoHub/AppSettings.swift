import Combine
import Foundation

enum AppSettings {
    enum Key {
        static let forwardCLIErrors = "ForwardCLIErrorToGUI"
        static let useGlassSwitcherUI = "UseGlassSwitcherUI"
    }

    static var isGlassAvailable: Bool {
        if #available(macOS 26, *) {
            return true
        }
        return false
    }

    static var defaultUseGlassSwitcherUI: Bool {
        isGlassAvailable
    }

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            Key.forwardCLIErrors: true,
            Key.useGlassSwitcherUI: defaultUseGlassSwitcherUI
        ])
    }

    static var forwardCLIErrors: Bool {
        UserDefaults.standard.bool(forKey: Key.forwardCLIErrors)
    }
}

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var forwardCLIErrors: Bool {
        didSet {
            UserDefaults.standard.set(forwardCLIErrors, forKey: AppSettings.Key.forwardCLIErrors)
        }
    }

    @Published var useGlassSwitcherUI: Bool {
        didSet {
            UserDefaults.standard.set(useGlassSwitcherUI, forKey: AppSettings.Key.useGlassSwitcherUI)
        }
    }

    init() {
        AppSettings.registerDefaults()
        self.forwardCLIErrors = UserDefaults.standard.bool(forKey: AppSettings.Key.forwardCLIErrors)
        self.useGlassSwitcherUI = UserDefaults.standard.bool(forKey: AppSettings.Key.useGlassSwitcherUI)
    }
}
