import NeoHubRLib

private let defaultLevel: LogLevel = {
    #if DEBUG
        return .debug
    #else
        return .info
    #endif
}()

let log = Logger.bootstrap(subsystem: APP_BUNDLE_ID, category: "app", defaultLevel: defaultLevel)
