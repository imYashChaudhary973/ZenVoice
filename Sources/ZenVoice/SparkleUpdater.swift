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
@MainActor
final class SparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
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

    private var updater: SPUUpdater?

    private override init() {
        automaticallyCheckForUpdates = UpdatePreferences.isAutomaticEnabled()
        super.init()
    }

    /// Starts the Sparkle updater on the main thread.
    func start() {
        guard updater == nil else { return }

        let updateDriver = SPUStandardUserDriver(hostBundle: Bundle.main, delegate: nil)
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
        updateInProgress = true
        updater?.checkForUpdates()
    }

    // MARK: - SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        // Return the feed URL from Info.plist when present. A nil value here
        // falls back to any feed URL Sparkle was initialized with.
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
