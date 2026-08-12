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
import ZenVoiceStorage

@MainActor
final class InsightsViewModel: ObservableObject {
    @Published private(set) var snapshot = LocalInsightsSnapshot.empty
    @Published var errorMessage: String?

    private let vaultProvider: () async throws -> DictationVault

    init(vaultProvider: @escaping () async throws -> DictationVault) {
        self.vaultProvider = vaultProvider
        refresh()
    }

    func refresh() {
        Task { await refreshNow() }
    }

    private func refreshNow() async {
        do {
            snapshot = try await vaultProvider().insights()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
