import AppKit
import SwiftUI

@MainActor
final class ZenBarPanelController {
    private let panel: NSPanel

    init(state: AppState, toggleRecording: @escaping () -> Void) {
        let frame = NSRect(x: 0, y: 0, width: 250, height: 54)
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.contentView = NSHostingView(
            rootView: ZenBarView(
                state: state,
                toggleRecording: toggleRecording
            )
        )
    }

    func show() {
        positionAtBottomCenter()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func positionAtBottomCenter() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = visibleFrame.minY + 28
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
