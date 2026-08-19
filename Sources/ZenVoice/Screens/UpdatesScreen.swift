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
import SwiftUI
import ZenVoiceCore

/// Drives the Updates screen.
///
/// The updater is built but inert: public shipping is deferred (ADR 0004), so
/// there is no signed feed to check yet. The screen states that rather than
/// pretending to check and silently finding nothing.
@MainActor
final class UpdatesViewModel: ObservableObject {
    @Published private(set) var automaticEnabled: Bool
    @Published private(set) var channel: UpdateChannel
    @Published private(set) var lastCheck: Date?
    @Published var statusMessage: String?

    /// Whether a signed release feed is configured for this build.
    let isFeedConfigured: Bool
    let installedVersion: String

    init(
        installedVersion: String = UpdatesViewModel.bundleVersion(),
        isFeedConfigured: Bool = false
    ) {
        self.installedVersion = installedVersion
        self.isFeedConfigured = isFeedConfigured
        automaticEnabled = UpdatePreferences.isAutomaticEnabled()
        channel = UpdatePreferences.channel()
        lastCheck = UpdatePreferences.lastCheck()
    }

    nonisolated static func bundleVersion() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "0.0.0"
    }

    func setAutomaticEnabled(_ enabled: Bool) {
        UpdatePreferences.setAutomaticEnabled(enabled)
        automaticEnabled = enabled
    }

    func setChannel(_ channel: UpdateChannel) {
        UpdatePreferences.setChannel(channel)
        self.channel = channel
    }

    func checkNow() {
        guard isFeedConfigured else {
            statusMessage =
                "No signed release feed is configured for this build, so "
                + "there is nothing to check yet."
            return
        }
        let now = Date()
        UpdatePreferences.setLastCheck(now)
        lastCheck = now
        statusMessage = "Checked for updates."
    }

    var lastCheckDescription: String {
        guard let lastCheck else {
            return "Never checked."
        }
        return "Last checked "
            + lastCheck.formatted(date: .abbreviated, time: .shortened)
            + "."
    }
}

struct UpdatesScreen: View {
    @ObservedObject var viewModel: UpdatesViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ZenDesign.Spacing.xl) {
            if !viewModel.isFeedConfigured {
                deferredNotice
            }
            preferencesSection
            trustSection
            if let status = viewModel.statusMessage {
                Text(status)
                    .font(ZenDesign.Typography.caption)
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }


    private var deferredNotice: some View {
        ZenPanel {
            HStack(alignment: .top, spacing: ZenDesign.Spacing.xs) {
                Image(systemName: "clock.badge.questionmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ZenDesign.Semantic.textSecondary)
                Text(
                    "Public distribution is deferred, so no release feed is "
                    + "configured yet. These settings are saved and will apply "
                    + "once ZenVoice ships publicly."
                )
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(ZenDesign.Spacing.md)
        }
    }

    private var preferencesSection: some View {
        ZenSection(
            title: "Checking",
            caption: "Version \(viewModel.installedVersion)"
        ) {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.md) {
                    Toggle(
                        "Check for updates automatically",
                        isOn: Binding(
                            get: { viewModel.automaticEnabled },
                            set: { viewModel.setAutomaticEnabled($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    Picker(
                        "Channel",
                        selection: Binding(
                            get: { viewModel.channel },
                            set: { viewModel.setChannel($0) }
                        )
                    ) {
                        ForEach(UpdateChannel.allCases, id: \.self) { item in
                            Text(item.displayName).tag(item)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    Text(viewModel.channel.detail)
                        .font(ZenDesign.Typography.caption)
                        .foregroundStyle(ZenDesign.Semantic.textTertiary)

                    HStack(spacing: ZenDesign.Spacing.xs) {
                        Button("Check now") { viewModel.checkNow() }
                            .buttonStyle(ZenSecondaryButtonStyle())
                        Text(viewModel.lastCheckDescription)
                            .font(ZenDesign.Typography.caption)
                            .foregroundStyle(ZenDesign.Semantic.textTertiary)
                        Spacer()
                    }
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private var trustSection: some View {
        ZenSection(title: "How updates are trusted") {
            ZenPanel {
                VStack(alignment: .leading, spacing: ZenDesign.Spacing.xs) {
                    bullet(
                        "The release feed is signed with Ed25519 and verified "
                        + "against a key built into this app."
                    )
                    bullet(
                        "The downloaded archive's SHA-256 must match the "
                        + "signed feed before anything is replaced."
                    )
                    bullet(
                        "Verification is fail-closed: any failure rejects the "
                        + "update and leaves ZenVoice untouched. There is no "
                        + "option to install an unverified update."
                    )
                    bullet("Feed and download are HTTPS only.")
                    bullet(
                        "Only newer versions are offered, so a replayed old "
                        + "feed cannot downgrade you."
                    )
                    bullet(
                        "An update check sends no identifier and no user "
                        + "content."
                    )
                }
                .padding(ZenDesign.Spacing.md)
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: ZenDesign.Spacing.xs) {
            Text("•")
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textTertiary)
            Text(text)
                .font(ZenDesign.Typography.caption)
                .foregroundStyle(ZenDesign.Semantic.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
