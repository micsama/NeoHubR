import Foundation
import SwiftUI

@MainActor
final class WindowCounter {
    private var counter: UInt8

    init() {
        self.counter = 0
    }

    var now: UInt8 { self.counter }

    func inc() {
        self.counter += 1
    }

    func dec() {
        if self.counter > 0 {
            self.counter -= 1
        }
    }
}

@MainActor
final class RegularWindow<Content: View>: NSObject {
    var window: NSWindow?

    let title: String?
    let width: CGFloat
    let level: NSWindow.Level?
    let content: () -> Content
    let windowCounter: WindowCounter

    init(
        title: String? = nil,
        width: CGFloat,
        level: NSWindow.Level? = nil,
        content: @escaping () -> Content,
        windowCounter: WindowCounter
    ) {
        self.window = nil
        self.title = title
        self.width = width
        self.level = level
        self.content = content
        self.windowCounter = windowCounter
        super.init()
    }

    func open() {
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hostingView = NSHostingView(rootView: self.content())
        let fittingSize = hostingView.fittingSize
        let fixedHeight: CGFloat? = {
            if Content.self == SettingsView.self {
                return SettingsView.defaultHeight
            }
            return nil
        }()
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: self.width,
                height: fixedHeight ?? fittingSize.height
            ),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        if let title = self.title {
            window.title = title
        }

        if let level = self.level {
            window.level = level
        }

        window.contentView = hostingView

        window.isReleasedWhenClosed = false

        // We want Settigs and other non-Switcher windows to be Cmd+Tab'able, so temporarily making app regular
        NSApp.setActivationPolicy(.regular)

        window.styleMask.remove(.resizable)

        // Ensuring that the window gets activated
        WindowPlacement.centerOnCurrentScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        // When window gets closed, reverting the app to the accessory type
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        self.window = window

        self.windowCounter.inc()
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        self.window == window
    }

    func close() {
        window?.close()
    }

    @objc private func handleWindowClose(_ notification: Notification) {
        if windowCounter.now == 1 {
            NSApp.setActivationPolicy(.accessory)
        }
        windowCounter.dec()
        self.cleanUp()
    }

    private func cleanUp() {
        if let window = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        self.window = nil
    }

}

@MainActor
final class RegularWindowRef<Content: View> {
    private var window: RegularWindow<Content>?

    func set(_ window: RegularWindow<Content>) {
        self.window = window
    }

    func isSameWindow(_ window: NSWindow) -> Bool {
        self.window?.isSameWindow(window) ?? false
    }

    func close() {
        window?.close()
    }
}
