import Foundation

enum MainThread {
    static func assert() {
#if DEBUG
        dispatchPrecondition(condition: .onQueue(.main))
#endif
    }

    static func run(_ action: @MainActor @escaping () -> Void) {
        Task { @MainActor in action() }
    }

    static func after(_ delay: TimeInterval, _ action: @MainActor @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            Task { @MainActor in action() }
        }
    }
}
