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
        setMode: @escaping (ZenBarMode) -> Void
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
                setMode: setMode
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        )
        let host = NSHostingView(rootView: content)
        hostingView = host
        panel.contentView = host

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
        setMode: @escaping (ZenBarMode) -> Void
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
                    setMode: setMode
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
    private func positionOverlay() {
        guard let screen = screenForFrontmostApplication()
            ?? screenContainingMouse()
            ?? NSScreen.main
            ?? NSScreen.screens.first else {
            return
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
        let y = max(
            screen.frame.minY,
            visibleFrame.minY + barBottomMargin - ZenBarView.shadowInset
        )
        panel.setFrameOrigin(NSPoint(x: x, y: y))
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
                NSPoint(x: frame.midX - panelWidth / 2, y: y)
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
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            return
        }

        panel.setFrameOrigin(
            NSPoint(x: frame.midX - panelWidth / 2, y: belowNotchY)
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
