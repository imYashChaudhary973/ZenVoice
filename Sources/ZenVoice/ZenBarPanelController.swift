// Copyright 2026 Yash Chaudhary
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import AppKit
import SwiftUI

@MainActor
final class ZenBarPanelController {
    private static let overlayCollectionBehavior:
        NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

    /// Entering a native full-screen space animates for roughly three quarters
    /// of a second, and `activeSpaceDidChangeNotification` fires while that is
    /// still running — early enough that the outgoing space is often still the
    /// one in front. Re-asserting once at that instant puts the panel back on
    /// the space being left behind, so the checks are spread across the
    /// animation and stop as soon as the panel is confirmed to have made it.
    private static let reassertDelays: [TimeInterval] = [0.15, 0.4, 0.9, 1.6]

    private let panel: NSPanel
    private var isShowing = false
    private var spaceObserver: NSObjectProtocol?
    private var reassertWorkItems: [DispatchWorkItem] = []

    init(
        state: AppState,
        toggleRecording: @escaping () -> Void,
        cancelRecording: @escaping () -> Void,
        finishRecording: @escaping () -> Void,
        dismissError: @escaping () -> Void
    ) {
        // Sized to hold the widest bar state plus the margin its shadow needs.
        // The panel clips its hosting view, so at the old 550x68 the shadow —
        // 18pt of blur pushed 8pt downward, against 12pt of margin — was simply
        // cut off along the bottom edge.
        let frame = NSRect(
            x: 0,
            y: 0,
            width: ZenBarView.maximumBarWidth
                + (ZenBarView.shadowInset * 2),
            height: ZenBarView.barHeight
                + (ZenBarView.shadowInset * 2)
        )
        panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // `.statusBar` (25) sits below the levels some apps use for their
        // full-screen and presentation windows. `.screenSaver` clears those
        // with room to spare while still staying under the shielding level,
        // so the bar never covers system alerts or the menu bar.
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = Self.overlayCollectionBehavior
        panel.contentView = NSHostingView(
            rootView: ZenBarView(
                state: state,
                toggleRecording: toggleRecording,
                cancelRecording: cancelRecording,
                finishRecording: finishRecording,
                dismissError: dismissError
            )
        )

        observeActiveSpaceChanges()
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        for item in reassertWorkItems {
            item.cancel()
        }
    }

    func show() {
        isShowing = true
        // Re-ordering is what moves the panel between spaces, but it blinks
        // the bar out for a frame. show() runs on every phase change of a
        // dictation, so pay that cost only when the panel is not already on
        // the space in front.
        if isPanelOnActiveSpace() {
            positionAtBottomCenter()
            panel.orderFrontRegardless()
        } else {
            presentOnActiveSpace()
        }
        scheduleSpaceReassertions()
    }

    func hide() {
        isShowing = false
        cancelPendingReassertions()
        panel.orderOut(nil)
    }

    /// The window server binds a window to a space when the window is ordered
    /// in, and `orderFrontRegardless()` on a panel it still considers ordered
    /// in is a no-op — the binding is never reconsidered. That is why the bar
    /// stayed stranded on the desktop space once a browser or terminal moved
    /// to its own full-screen space. Ordering the panel out first is what
    /// forces the decision to be made again, against the space in front now.
    private func presentOnActiveSpace() {
        panel.orderOut(nil)
        panel.collectionBehavior = Self.overlayCollectionBehavior
        positionAtBottomCenter()
        panel.orderFrontRegardless()
    }

    /// Switching spaces — including entering or leaving another app's
    /// full-screen space — can leave the panel behind on the space it was
    /// ordered into. Re-assert it against the space that is now active.
    private func observeActiveSpaceChanges() {
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSpaceReassertions()
            }
        }
    }

    /// Re-orders the panel only when it is genuinely missing from the space in
    /// front, so an ordinary desktop switch does not flicker the bar.
    private func scheduleSpaceReassertions() {
        cancelPendingReassertions()
        guard isShowing else {
            return
        }

        for delay in Self.reassertDelays {
            let item = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isShowing else {
                        return
                    }
                    guard !self.isPanelOnActiveSpace() else {
                        return
                    }
                    self.presentOnActiveSpace()
                }
            }
            reassertWorkItems.append(item)
            DispatchQueue.main.asyncAfter(
                deadline: .now() + delay,
                execute: item
            )
        }
    }

    private func cancelPendingReassertions() {
        for item in reassertWorkItems {
            item.cancel()
        }
        reassertWorkItems.removeAll()
    }

    /// `CGWindowListCopyWindowInfo` with `.optionOnScreenOnly` reports only the
    /// windows on the space that is currently in front, so matching the panel's
    /// window number against that list is the one dependable way to tell
    /// whether the bar actually followed the user across.
    private func isPanelOnActiveSpace() -> Bool {
        let windowNumber = panel.windowNumber
        guard windowNumber > 0 else {
            return false
        }
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return false
        }

        return windows.contains { window in
            let number = window[kCGWindowNumber as String] as? NSNumber
            return number?.intValue == windowNumber
        }
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
        // The bar itself stays where it has always sat, 18pt above the visible
        // frame. Only the panel around it grew, to give the shadow room, so the
        // origin drops by that margin — and is then clamped so the panel never
        // leaves the display when the Dock is hidden and `visibleFrame` already
        // reaches the bottom edge.
        let barBottomMargin: CGFloat = 18
        let y = max(
            screen.frame.minY,
            visibleFrame.minY + barBottomMargin - ZenBarView.shadowInset
        )
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// `CGWindowListCopyWindowInfo` reports bounds in Core Graphics global
    /// coordinates (origin top-left of the primary display, y growing down),
    /// while `NSScreen.frame` is AppKit global coordinates (origin bottom-left,
    /// y growing up). Comparing the two directly only appears to work on a
    /// single display, where both ranges happen to coincide; with a second
    /// display attached it picks the wrong screen.
    private func convertToAppKit(_ rect: CGRect) -> CGRect {
        guard let primary = NSScreen.screens.first else {
            return rect
        }
        return CGRect(
            x: rect.minX,
            y: primary.frame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
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

            let bounds = convertToAppKit(
                CGRect(
                    x: x.doubleValue,
                    y: y.doubleValue,
                    width: width.doubleValue,
                    height: height.doubleValue
                )
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
