import AppKit
import SwiftUI

@MainActor
final class ZenBarPanelController {
    private let panel: NSPanel

    init(
        state: AppState,
        toggleRecording: @escaping () -> Void,
        cancelRecording: @escaping () -> Void,
        finishRecording: @escaping () -> Void
    ) {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 96)
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
                toggleRecording: toggleRecording,
                cancelRecording: cancelRecording,
                finishRecording: finishRecording
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
        guard let screen = screenForFrontmostApplication()
            ?? screenContainingMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let y = visibleFrame.minY + 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func screenForFrontmostApplication() -> NSScreen? {
        guard let processIdentifier =
            NSWorkspace.shared.frontmostApplication?.processIdentifier,
            let windowInfo = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] else {
            return nil
        }

        let applicationWindows = windowInfo.filter { window in
            let owner = window[kCGWindowOwnerPID as String] as? NSNumber
            let layer = window[kCGWindowLayer as String] as? NSNumber
            return owner?.int32Value == processIdentifier &&
                layer?.intValue == 0
        }

        for window in applicationWindows {
            guard let values =
                window[kCGWindowBounds as String] as? [String: NSNumber],
                let x = values["X"],
                let y = values["Y"],
                let width = values["Width"],
                let height = values["Height"] else {
                continue
            }

            let bounds = CGRect(
                x: x.doubleValue,
                y: y.doubleValue,
                width: width.doubleValue,
                height: height.doubleValue
            )
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            if let screen = NSScreen.screens.first(where: {
                $0.frame.contains(center)
            }) {
                return screen
            }
        }

        return nil
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            $0.frame.contains(mouseLocation)
        }
    }
}
