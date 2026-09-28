import AppKit

final class WidgetWindow: NSPanel {

    init(canvas: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = true
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        applyLevel()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func applyLevel() {
        level = Preferences.alwaysOnTop
            ? .floating
            : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func resize(to canvas: CGSize) {
        setFrame(NSRect(origin: frame.origin, size: canvas), display: true)
    }

    func placeAtDefaultPosition() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        let margin: CGFloat = 48
        setFrameOrigin(NSPoint(x: visible.minX + margin, y: visible.minY + margin))
    }

    func restore(_ saved: CGPoint?) {
        if let saved, NSScreen.screens.contains(where: {
            $0.frame.intersects(NSRect(origin: saved, size: frame.size))
        }) {
            setFrameOrigin(saved)
        } else {
            placeAtDefaultPosition()
        }
    }

    func restorePosition() {
        if let saved = Preferences.origin, NSScreen.screens.contains(where: {
            $0.frame.intersects(NSRect(origin: saved, size: frame.size))
        }) {
            setFrameOrigin(saved)
        } else {
            placeAtDefaultPosition()
        }
    }
}
