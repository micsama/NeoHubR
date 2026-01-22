import NeoHubLib

private let defaultLevel: LogLevel = {
    #if DEBUG
        return .debug
    #else
        return .info
    #endif
}()

let log = bootstrapAppLogger(subsystem: APP_BUNDLE_ID, category: "app", defaultLevel: defaultLevel)
