import AppKit

enum WindowPlacement {
    @MainActor
    static func centerOnCurrentScreen(_ window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            window.center()
            return
        }

        let frame = screen.visibleFrame
        let size = window.frame.size
        let origin = CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
        window.setFrameOrigin(origin)
    }
}
