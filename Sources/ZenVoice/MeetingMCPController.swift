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
import ZenVoiceCore
import ZenVoiceMCP
import ZenVoiceStorage

@MainActor
final class MeetingMCPController: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var pairing: String?
    @Published private(set) var errorMessage: String?

    var displayedPairing: String {
        guard let pairing, pairing.count == 6 else { return pairing ?? "" }
        let mid = pairing.index(pairing.startIndex, offsetBy: 3)
        return "\(pairing[..<mid])-\(pairing[mid...])"
    }

    private let client: MeetingMCPClient?
    private var pullTask: Task<Void, Never>?

    init(
        store: MeetingStore,
        keyProvider: VaultKeyProviding?,
        devices: MeetingMCPDeviceStoring
    ) {
        isEnabled = MeetingMCPPreferences.isEnabled()
        guard let origin = MeetingMCPPreferences.origin(),
              let keyProvider
        else {
            client = nil
            pairing = nil
            return
        }
        client = MeetingMCPClient(
            origin: origin,
            source: MeetingStoreMCPSource(
                store: store,
                keyProvider: keyProvider
            ),
            devices: devices
        )
        pairing = try? devices.load()?.pairing
        if isEnabled {
            startPull()
        }
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        MeetingMCPPreferences.setEnabled(enabled)
        if enabled {
            startPull()
        } else {
            stopPull()
        }
    }

    func stopPull() {
        pullTask?.cancel()
        pullTask = nil
        Task { await client?.revoke() }
    }

    private func startPull() {
        guard let client else {
            errorMessage = MeetingMCPDeviceError.missingOrigin.localizedDescription
            isEnabled = false
            MeetingMCPPreferences.setEnabled(false)
            return
        }
        pullTask?.cancel()
        pullTask = Task { [weak self] in
            do {
                let record = try await client.register()
                await MainActor.run {
                    self?.pairing = record.pairing
                    self?.errorMessage = nil
                }
                while !Task.isCancelled {
                    try await client.pullOnce()
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    self?.errorMessage = error.localizedDescription
                    self?.isEnabled = false
                    MeetingMCPPreferences.setEnabled(false)
                }
            }
        }
    }
}
