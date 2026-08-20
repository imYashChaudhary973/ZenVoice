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
import ApplicationServices
import SwiftUI
import ZenVoiceCore

/// A generic container for any ZenVoice overlay.
///
/// Phase 4 extends the original ZenBar panel into a family of overlays:
/// ZenBar (bottom-center), and live-preview variants sized for the notch or
/// top-center. This controller keeps the existing ZenBar behavior intact and
/// adds the ability to host other overlay kinds.
@MainActor
final class OverlayPanelController {
    private static let overlayCollectionBehavior:
        NSWindow.CollectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

    private static let reassertDelays: [TimeInterval] = [0.15, 0.4, 0.9, 1.6]

    private let kind: OverlayKind
    /// The Reduce Motion value this panel's content was built with. The value
    /// is baked into the hosted view's environment, so a change means the
    /// panel has to be rebuilt.
    private let reduceMotion: Bool
    private let panel: NSPanel
    private var isShowing = false
    private var spaceObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var reassertWorkItems: [DispatchWorkItem] = []
    private var hostingView: NSHostingView<AnyView>?

    /// Creates a panel controller for the given overlay kind. The closures are
    /// forwarded to the overlay content view.
    init(
        kind: OverlayKind,
        state: AppState,
        toggleRecording: @escaping () -> Void,
        cancelRecording: @escaping () -> Void,
        finishRecording: @escaping () -> Void,
        dismissError: @escaping () -> Void,
        setMode: @escaping (ZenBarMode) -> Void,
        cancelAgenticGoal: @escaping () -> Void
    ) {
        self.kind = kind
        reduceMotion = OverlayPreferences.loadReduceMotion()

        let frame = NSRect(
            x: 0,
            y: 0,
            width: kind.defaultSize.width,
            height: kind.defaultSize.height
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
        panel.level = .screenSaver
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = Self.overlayCollectionBehavior

        let content = AnyView(
            overlayContent(
                kind: kind,
                state: state,
                toggleRecording: toggleRecording,
                cancelRecording: cancelRecording,
                finishRecording: finishRecording,
                dismissError: dismissError,
                setMode: setMode,
                cancelAgenticGoal: cancelAgenticGoal
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let host = NSHostingView(rootView: content)
        hostingView = host
        panel.contentView = host

        observeActiveSpaceChanges()
        observeApplicationActivation()
    }

    deinit {
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter
                .removeObserver(activationObserver)
        }
        for item in reassertWorkItems {
            item.cancel()
        }
    }

    var overlayKind: OverlayKind { kind }

    /// Whether the panel already matches the given presentation preferences.
    func matches(kind: OverlayKind, reduceMotion: Bool) -> Bool {
        self.kind == kind && self.reduceMotion == reduceMotion
    }

    func show() {
        isShowing = true
        if isPanelOnActiveSpace() {
            positionOverlay()
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

    /// Repositions the overlay without changing its visibility.
    func reposition() {
        guard isShowing else { return }
        positionOverlay()
    }

    /// Rebuilds the panel size to match the current overlay kind's default.
    func resizeToDefault() {
        let size = kind.defaultSize
        var frame = panel.frame
        frame.size.width = size.width
        frame.size.height = size.height
        panel.setFrame(frame, display: true, animate: false)
        if isShowing {
            positionOverlay()
        }
    }

    private func overlayContent(
        kind: OverlayKind,
        state: AppState,
        toggleRecording: @escaping () -> Void,
        cancelRecording: @escaping () -> Void,
        finishRecording: @escaping () -> Void,
        dismissError: @escaping () -> Void,
        setMode: @escaping (ZenBarMode) -> Void,
        cancelAgenticGoal: @escaping () -> Void
    ) -> some View {
        switch kind {
        case .zenBar:
            return AnyView(
                ZenBarView(
                    state: state,
                    toggleRecording: toggleRecording,
                    cancelRecording: cancelRecording,
                    finishRecording: finishRecording,
                    dismissError: dismissError,
                    setMode: setMode,
                    cancelAgenticGoal: cancelAgenticGoal
                )
            )
        case .livePreviewPill,
             .livePreviewMedium,
             .livePreviewLarge:
            return AnyView(
                LivePreviewOverlayView(
                    kind: kind,
                    state: state,
                    reduceMotion: reduceMotion,
                    cancelRecording: cancelRecording,
                    finishRecording: finishRecording
                )
            )
        }
    }

    private func presentOnActiveSpace() {
        panel.orderOut(nil)
        panel.collectionBehavior = Self.overlayCollectionBehavior
        positionOverlay()
        panel.orderFrontRegardless()
    }

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

    /// Follows the user between displays as they switch applications.
    ///
    /// Without this the overlay is positioned once, when it is first shown, and
    /// then stays on that display for the rest of the session — so picking the
    /// right screen at launch fixes only the launch. Dictation is aimed at
    /// whatever app is in front, so the bar belongs on whatever display that
    /// app is on.
    private func observeApplicationActivation() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // A newly activated app has not necessarily finished making a
                // window key, and the focused-window query is only as good as
                // the answer Accessibility gives at the moment it is asked.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    MainActor.assumeIsolated {
                        self?.reposition()
                    }
                }
            }
        }
    }

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

    /// Positions the overlay based on its kind.
    ///
    /// The chain is ordered by how directly each signal answers "which display
    /// is the user working on": the focused window of the app they are typing
    /// into, then where their pointer is, then the screen holding keyboard
    /// focus, then the primary.
    private func positionOverlay() {
        guard let screen = screenForFocusedWindow()
            ?? screenContainingMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
        }

        let adaptiveSize = kind.size(fitting: screen.visibleFrame.size)
        if panel.frame.size != adaptiveSize {
            var frame = panel.frame
            frame.size = adaptiveSize
            panel.setFrame(frame, display: true, animate: false)
        }

        switch kind {
        case .zenBar:
            positionAtBottomCenter(screen: screen)
        case .livePreviewPill,
             .livePreviewMedium,
             .livePreviewLarge:
            positionAtTopCenterOrNotch(screen: screen)
        }
    }

    private func positionAtBottomCenter(screen: NSScreen) {
        let visibleFrame = screen.visibleFrame
        let x = visibleFrame.midX - panel.frame.width / 2
        let barBottomMargin: CGFloat = 18
        let y = visibleFrame.minY + barBottomMargin - ZenBarView.shadowInset
        panel.setFrameOrigin(
            clampedOrigin(NSPoint(x: x, y: y), on: screen)
        )
    }

    /// Positions the panel near the notch when present, otherwise top-center.
    ///
    /// A notched display reports a non-zero `safeAreaInsets.top` and exposes the
    /// usable strips beside the camera housing as `auxiliaryTopLeftArea` and
    /// `auxiliaryTopRightArea`. The pill is small enough to sit in one of those
    /// strips; the taller variants clear the housing entirely and sit below it.
    private func positionAtTopCenterOrNotch(screen: NSScreen) {
        let frame = screen.frame
        let panelWidth = panel.frame.width
        let panelHeight = panel.frame.height
        let topMargin: CGFloat = 8

        guard let notch = notchMetrics(for: screen) else {
            // No notch: center at the top of the display, below the menu bar.
            let y = screen.visibleFrame.maxY - panelHeight - topMargin
            panel.setFrameOrigin(
                clampedOrigin(
                    NSPoint(x: frame.midX - panelWidth / 2, y: y),
                    on: screen
                )
            )
            return
        }

        // Below the camera housing for anything taller than the menu bar strip.
        let belowNotchY = frame.maxY - notch.safeAreaTop - panelHeight
            - topMargin

        if kind == .livePreviewPill,
           let strip = widestAuxiliaryArea(for: screen),
           strip.width >= panelWidth {
            // The pill fits beside the notch, vertically centered in the strip.
            let x = min(
                max(strip.minX, strip.midX - panelWidth / 2),
                strip.maxX - panelWidth
            )
            let y = strip.midY - panelHeight / 2
            panel.setFrameOrigin(
                clampedOrigin(NSPoint(x: x, y: y), on: screen)
            )
            return
        }

        panel.setFrameOrigin(
            clampedOrigin(
                NSPoint(x: frame.midX - panelWidth / 2, y: belowNotchY),
                on: screen
            )
        )
    }

    /// Safe-area facts for a screen, or nil when the screen has no notch.
    private func notchMetrics(
        for screen: NSScreen
    ) -> (safeAreaTop: CGFloat, hasAuxiliaryAreas: Bool)? {
        let safeAreaTop = screen.safeAreaInsets.top
        guard safeAreaTop > 0 else {
            return nil
        }
        let hasAuxiliaryAreas = screen.auxiliaryTopLeftArea != nil
            || screen.auxiliaryTopRightArea != nil
        return (safeAreaTop, hasAuxiliaryAreas)
    }

    /// The larger of the two strips flanking the camera housing.
    private func widestAuxiliaryArea(for screen: NSScreen) -> NSRect? {
        let areas = [
            screen.auxiliaryTopLeftArea,
            screen.auxiliaryTopRightArea
        ].compactMap { $0 }
        return areas.max { $0.width < $1.width }
    }

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

    /// The screen holding the frontmost application's **focused** window.
    ///
    /// This replaces a scan of `CGWindowListCopyWindowInfo` that took the
    /// frontmost app's first layer-0 window in list order. That order is
    /// front-to-back across *every* display, so on a multi-display desktop it
    /// routinely resolved to a window the user was not looking at: with three
    /// displays attached, the bar was placed at the bottom-centre of a screen
    /// to the left of the primary and was, for practical purposes, missing.
    /// The list order also cannot distinguish an app's focused window from any
    /// other window it happens to have open.
    ///
    /// The Accessibility API answers the question directly. ZenVoice already
    /// requires that permission in order to type into other applications, so
    /// this costs no new prompt; when it is not granted the call simply fails
    /// and the caller falls through to the pointer.
    private func screenForFocusedWindow() -> NSScreen? {
        guard let processIdentifier =
            NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }

        let application = AXUIElementCreateApplication(processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            application,
            kAXFocusedWindowAttribute as CFString,
            &focused
        ) == .success else {
            return nil
        }
        // CFTypeRef is only known to be an AXUIElement by contract, so this is
        // checked rather than forced: a malformed reply must fall through to
        // the next signal, not trap.
        guard let windowValue = focused,
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let window = windowValue as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            window,
            kAXPositionAttribute as CFString,
            &positionValue
        ) == .success,
            AXUIElementCopyAttributeValue(
                window,
                kAXSizeAttribute as CFString,
                &sizeValue
            ) == .success,
            let rawPosition = positionValue,
            let rawSize = sizeValue,
            CFGetTypeID(rawPosition) == AXValueGetTypeID(),
            CFGetTypeID(rawSize) == AXValueGetTypeID() else {
            return nil
        }

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &origin),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              size.width > 0,
              size.height > 0 else {
            return nil
        }

        // Accessibility reports the same top-left-origin global space as
        // CGWindowList, so the existing flip still applies.
        return screen(
            bestMatching: convertToAppKit(
                CGRect(origin: origin, size: size)
            )
        )
    }

    private func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first {
            $0.frame.contains(mouseLocation)
        }
    }

    /// The screen showing the most of `rect`.
    ///
    /// Area of overlap rather than a centre-point containment test: a window
    /// straddling two displays belongs to the one showing more of it, and a
    /// window dragged mostly off-screen has a centre that lands on no display
    /// at all — in which case the old test returned nothing and the caller
    /// silently fell through to the pointer.
    private func screen(bestMatching rect: CGRect) -> NSScreen? {
        let best = NSScreen.screens.max { first, second in
            overlapArea(first, rect) < overlapArea(second, rect)
        }
        guard let best, overlapArea(best, rect) > 0 else {
            return nil
        }
        return best
    }

    private func overlapArea(_ screen: NSScreen, _ rect: CGRect) -> CGFloat {
        let intersection = screen.frame.intersection(rect)
        guard !intersection.isNull, !intersection.isEmpty else {
            return 0
        }
        return intersection.width * intersection.height
    }

    /// Keeps the panel wholly inside a screen.
    ///
    /// A backstop rather than a positioning rule: every caller already aims for
    /// a sensible spot, and this only catches the case where the arithmetic and
    /// the display geometry disagree. The bar is clamped to `frame` rather than
    /// `visibleFrame` because sitting over the Dock is intended.
    private func clampedOrigin(
        _ origin: NSPoint,
        on screen: NSScreen
    ) -> NSPoint {
        let bounds = screen.frame
        let size = panel.frame.size
        let maximumX = max(bounds.minX, bounds.maxX - size.width)
        let maximumY = max(bounds.minY, bounds.maxY - size.height)
        return NSPoint(
            x: min(max(origin.x, bounds.minX), maximumX),
            y: min(max(origin.y, bounds.minY), maximumY)
        )
    }
}
