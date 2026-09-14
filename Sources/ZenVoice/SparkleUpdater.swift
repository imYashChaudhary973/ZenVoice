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
import Combine
import Foundation
import os
import Sparkle
import SwiftUI
import ZenVoiceCore

/// Wrapper around Sparkle's `SPUUpdater`.
///
/// Started automatically on launch from `AppDelegate`. Feed URL and public
/// key are read from `Info.plist` so release tooling can inject them without
/// recompiling; placeholders are committed to keep real secrets out of the
/// repository.
///
/// `SPUStandardUserDriver` presents "up to date" / error UI with
/// `NSAlert.runModal()`. A nested modal session against BuilderHelm Voice's SwiftUI
/// settings window locks the main thread, so those alerts are shown as
/// sheets instead. User-initiated checks are also scheduled in the default
/// run-loop mode so they do not start during SwiftUI event tracking.
@MainActor
final class SparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate,
    @preconcurrency SPUStandardUserDriverDelegate
{
    static let shared = SparkleUpdater()

    /// Mirrors `SPUUpdater.automaticallyChecksForUpdates` and persists the
    /// user's preference.
    @Published var automaticallyCheckForUpdates: Bool {
        didSet {
            updater?.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            UpdatePreferences.setAutomaticEnabled(automaticallyCheckForUpdates)
        }
    }

    /// True while Sparkle is actively checking or downloading an update.
    @Published private(set) var updateInProgress: Bool = false

    /// Date of the last completed background check, if any.
    @Published private(set) var lastUpdateCheckDate: Date?

    fileprivate weak var sheetHostWindow: NSWindow?

    private var updater: SPUUpdater?
    private var windowsHiddenForModal: [NSWindow] = []

    private override init() {
        automaticallyCheckForUpdates = UpdatePreferences.isAutomaticEnabled()
        super.init()
    }

    /// Starts the Sparkle updater on the main thread.
    func start() {
        guard updater == nil else { return }

        let updateDriver = ZenSparkleUserDriver(
            hostBundle: Bundle.main,
            delegate: self
        )
        let newUpdater = SPUUpdater(
            hostBundle: Bundle.main,
            applicationBundle: Bundle.main,
            userDriver: updateDriver,
            delegate: self
        )

        do {
            try newUpdater.start()
            newUpdater.automaticallyChecksForUpdates = automaticallyCheckForUpdates
            lastUpdateCheckDate = newUpdater.lastUpdateCheckDate
            updater = newUpdater
        } catch {
            os_log(
                "Failed to start Sparkle updater: %{public}@",
                type: .error,
                error.localizedDescription
            )
        }
    }

    /// Triggers an explicit "Check for Updates" from UI (e.g. Settings).
    func checkForUpdates() {
        if updater == nil {
            start()
        }
        guard updater?.canCheckForUpdates == true else {
            return
        }
        updateInProgress = true
        sheetHostWindow = NSApp.keyWindow
        // Default-mode delay waits out SwiftUI/AppKit tracking. GCD main
        // async still runs in common modes and can nest inside the click.
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(presentUserInitiatedCheck),
            object: nil
        )
        perform(
            #selector(presentUserInitiatedCheck),
            with: nil,
            afterDelay: 0,
            inModes: [RunLoop.Mode.default]
        )
    }

    @objc private func presentUserInitiatedCheck() {
        guard let updater, updater.canCheckForUpdates else {
            updateInProgress = false
            return
        }
        bringZenVoiceForward()
        updater.checkForUpdates()
    }

    fileprivate func presentSparkleAlert(
        _ alert: NSAlert,
        acknowledgement: @escaping () -> Void
    ) {
        bringZenVoiceForward()
        closeSparkleProgressWindows()
        let host = sheetHostWindow?.isVisible == true
            ? sheetHostWindow
            : NSApp.keyWindow ?? NSApp.mainWindow
        if let host {
            alert.beginSheetModal(for: host) { _ in
                acknowledgement()
            }
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        alert.beginSheetModal(for: panel) { _ in
            panel.orderOut(nil)
            acknowledgement()
        }
    }

    private func bringZenVoiceForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - SPUStandardUserDriverDelegate

    func standardUserDriverWillShowModalAlert() {
        bringZenVoiceForward()
        // Fallback if any Sparkle path still calls runModal: a SwiftUI
        // hosting window as the key window deadlocks the nested session.
        windowsHiddenForModal = NSApp.windows.filter(\.isVisible)
        windowsHiddenForModal.forEach { $0.orderOut(nil) }
    }

    func standardUserDriverDidShowModalAlert() {
        windowsHiddenForModal.forEach { $0.makeKeyAndOrderFront(nil) }
        windowsHiddenForModal.removeAll()
        if let sheetHostWindow, sheetHostWindow.isVisible {
            sheetHostWindow.makeKeyAndOrderFront(nil)
        }
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        bringZenVoiceForward()
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        Bundle.main.infoDictionary?["SUFeedURL"] as? String
    }

    func updaterMayCheck(forUpdates updater: SPUUpdater) -> Bool {
        true
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: Error?
    ) {
        updateInProgress = false
        lastUpdateCheckDate = updater.lastUpdateCheckDate
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        updateInProgress = false
    }
}

/// Standard Sparkle UI, except "up to date" / error alerts are sheets.
///
/// The stock driver uses `NSAlert.runModal()`, which freezes BuilderHelm Voice's
/// SwiftUI settings window.
private final class ZenSparkleUserDriver: SPUStandardUserDriver {
    override func showUpdateNotFoundWithError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        let alert = NSAlert(error: error)
        alert.alertStyle = .informational
        SparkleUpdater.shared.presentSparkleAlert(
            alert,
            acknowledgement: acknowledgement
        )
    }

    override func showUpdaterError(
        _ error: Error,
        acknowledgement: @escaping () -> Void
    ) {
        let alert = NSAlert()
        let nsError = error as NSError
        if let recovery = nsError.localizedRecoverySuggestion, !recovery.isEmpty {
            alert.messageText = error.localizedDescription
            alert.informativeText = recovery
        } else {
            alert.messageText = "Update Error!"
            alert.informativeText = error.localizedDescription
        }
        alert.addButton(withTitle: "OK")
        SparkleUpdater.shared.presentSparkleAlert(
            alert,
            acknowledgement: acknowledgement
        )
    }

    override func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        guard !relaunched else {
            acknowledgement()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Update Installed"
        alert.informativeText = "BuilderHelm Voice has been updated."
        alert.addButton(withTitle: "OK")
        SparkleUpdater.shared.presentSparkleAlert(
            alert,
            acknowledgement: acknowledgement
        )
    }
}

private func closeSparkleProgressWindows() {
    for window in NSApp.windows {
        let controller = window.windowController
            .map { String(describing: type(of: $0)) } ?? ""
        if controller.contains("SUStatusController") {
            window.close()
        }
    }
}
