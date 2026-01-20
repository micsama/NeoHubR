import NeoHubLib

private let defaultLevel: LogLevel = {
    #if DEBUG
        return .debug
    #else
        return .info
    #endif
}()

let log = AppLogger(subsystem: APP_BUNDLE_ID, category: "app", level: defaultLevel)
