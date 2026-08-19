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
import ZenVoiceCore

/// Licence state for the About pane.
///
/// Activation is deliberately undramatic: paste, activate, done. Nothing is
/// gated on it — the app a user has already started dictating into does not
/// stop working because a receipt has not arrived yet — so this view model has
/// no locked state to manage, only a licence to record and show back.
@MainActor
final class LicenceViewModel: ObservableObject {
    @Published private(set) var status: LicenceStatus = .unlicensed
    @Published var pastedKey = ""
    /// Set when a paste is rejected. Cleared as soon as the field changes, so
    /// the error describes the current attempt and not the last one.
    @Published private(set) var activationError: String?
    @Published private(set) var justActivated = false

    private let store: any LicenceStoring

    init(store: any LicenceStoring) {
        self.store = store
        status = LicenceResolver.status(from: store)
    }

    var isLicensed: Bool {
        status.isLicensed
    }

    var licence: Licence? {
        if case .licensed(let licence) = status { return licence }
        return nil
    }

    /// Short, factual summary for the About row and the menu bar.
    var summary: String {
        switch status {
        case .licensed(let licence):
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return "Licensed · order \(licence.orderID) · "
                + formatter.string(from: licence.issuedAt)
        case .unlicensed:
            return "Not activated · \(ZenVoicePricing.summary)"
        }
    }

    func activate() {
        let candidate = pastedKey
        guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            activationError = "Paste the licence key from your receipt first."
            return
        }
        do {
            let licence = try LicenceVerifier.verify(candidate)
            try store.save(licence.token)
            status = .licensed(licence)
            pastedKey = ""
            activationError = nil
            justActivated = true
        } catch {
            activationError = error.localizedDescription
        }
    }

    func clearError() {
        guard activationError != nil else { return }
        activationError = nil
    }

    /// Removes the licence from this Mac. Used when moving to another machine,
    /// and the only reason it exists: a licence the user cannot get back out is
    /// a licence they cannot move.
    func deactivate() {
        try? store.clear()
        status = .unlicensed
        justActivated = false
    }

    func openPurchasePage() {
        NSWorkspace.shared.open(ZenVoicePricing.purchaseURL)
    }
}
