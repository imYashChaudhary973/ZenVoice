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

import Foundation
import ZenVoiceMCP
import ZenVoiceStorage

/// Test-only key for invented MCP rows. Not the production vault key.
private final class SmokeVaultKey: VaultKeyProviding {
    private let keyData = Data(repeating: 0x51, count: 32)

    func loadOrCreateKeyData() throws -> Data { keyData }

    func deleteKey() throws {}
}

private let titles = [
    "MCP Test Alpha",
    "MCP Test Bravo",
    "MCP Test Charlie",
]

@main
enum ZenVoiceMCPSmoke {
    static func main() async {
        do {
            let store = MeetingStore(
                directoryURL: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(
                        "Library/Application Support/com.zenvoice.app/Meetings",
                        isDirectory: true
                    )
            )
            let key = SmokeVaultKey()
            try seed(store: store, key: key)
            let source = MeetingStoreMCPSource(store: store, keyProvider: key)
            let listed = try source.listReady().filter {
                $0.title.hasPrefix("MCP Test")
            }
            print("seeded \(listed.count) MCP Test meetings")
            for row in listed {
                print("  \(row.title) \(row.id)")
            }
            if CommandLine.arguments.contains("--pull") {
                try await pull(source: source)
            }
        } catch {
            FileHandle.standardError.write(
                Data("FAIL: \(error.localizedDescription)\n".utf8)
            )
            exit(1)
        }
    }

    private static func seed(
        store: MeetingStore,
        key: VaultKeyProviding
    ) throws {
        let byTitle = Dictionary(
            uniqueKeysWithValues: (try store.all()).compactMap { record -> (String, MeetingStore.Record)? in
                guard let title = record.title else { return nil }
                return (title, record)
            }
        )
        for (offset, title) in titles.enumerated() {
            var record: MeetingStore.Record
            if let existing = byTitle[title] {
                record = existing
            } else {
                record = try store.createRecording(
                    now: Date().addingTimeInterval(
                        TimeInterval(-3600 * (3 - offset))
                    ),
                    availableBytes: MeetingStore.reservedAudioBytes
                )
                record.title = title
                record.status = .complete
                record.elapsedSeconds = 180
                record.captureSource = "local"
                try store.save(record)
            }
            if record.originalTranscriptCiphertext == nil {
                try store.setOriginalTranscript(
                    "You: invented transcript for \(title).\nThem: copy that.",
                    for: record.id,
                    keyProvider: key
                )
            }
            if record.summaryCiphertext == nil {
                try store.setSummary(
                    "Recap: \(title) is fake seed data.",
                    for: record.id,
                    keyProvider: key
                )
            }
        }
    }

    private static func pull(source: MeetingMCPDataSource) async throws {
        guard let origin = MeetingMCPPreferences.origin() else {
            throw MeetingMCPDeviceError.missingOrigin
        }
        let devices = InMemoryMeetingMCPDeviceStore()
        let client = MeetingMCPClient(
            origin: origin,
            source: source,
            devices: devices
        )
        let record = try await client.register()
        print("pairing \(record.pairing)")
        print("origin \(origin.absoluteString)")
        print("pulling")
        while true {
            try await client.pullOnce()
        }
    }
}
