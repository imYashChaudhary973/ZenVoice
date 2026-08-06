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
import Security

public enum CloudAIKeyStoreError: LocalizedError {
    case keychain(OSStatus)
    case invalidKey

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "Keychain error \(status)."
        case .invalidKey:
            return "The stored API key could not be read."
        }
    }
}

/// Stores the user's provider API key in the macOS Keychain.
///
/// Deliberately not `UserDefaults` and not the SQLite vault: a provider key is
/// a live credential for a third-party account, so it gets the same
/// generic-password treatment as the transcript encryption key, including
/// `WhenUnlockedThisDeviceOnly` so it never leaves this machine via a backup.
public protocol CloudAIKeyStoring: Sendable {
    func loadKey() throws -> String?
    func saveKey(_ key: String) throws
    func deleteKey() throws
}

public struct CloudAIKeychainKeyStore: CloudAIKeyStoring {
    private let service: String
    private let account: String

    public init(
        policy: BundleIdentifierPolicy,
        account: String = "cloud-ai-api-key"
    ) {
        service = RuntimeIdentity.keychainServiceName(policy: policy)
        self.account = account
    }

    public func loadKey() throws -> String? {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new } as CFDictionary

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CloudAIKeyStoreError.keychain(status)
        }
        guard let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw CloudAIKeyStoreError.invalidKey
        }
        return key
    }

    public func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try deleteKey()
            return
        }
        let data = Data(trimmed.utf8)

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CloudAIKeyStoreError.keychain(updateStatus)
        }

        let addQuery = baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new } as CFDictionary
        let addStatus = SecItemAdd(addQuery, nil)
        guard addStatus == errSecSuccess else {
            throw CloudAIKeyStoreError.keychain(addStatus)
        }
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CloudAIKeyStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

/// In-memory key store for checks and previews.
public final class InMemoryCloudAIKeyStore: CloudAIKeyStoring, @unchecked Sendable {
    private var key: String?
    private let lock = NSLock()

    public init(key: String? = nil) {
        self.key = key
    }

    public func loadKey() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return key
    }

    public func saveKey(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        self.key = trimmed.isEmpty ? nil : trimmed
    }

    public func deleteKey() throws {
        lock.lock(); defer { lock.unlock() }
        key = nil
    }
}

/// Persisted Cloud AI configuration. The API key is never stored here.
public enum CloudAIPreferences {
    private static let configurationKey = "ZenVoice.cloudAI.configuration"

    public static func load(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> CloudAIConfiguration {
        guard let data = defaults.data(forKey: configurationKey),
              let configuration = try? JSONDecoder().decode(
                CloudAIConfiguration.self,
                from: data
              ) else {
            return CloudAIConfiguration()
        }
        return configuration
    }

    public static func save(
        _ configuration: CloudAIConfiguration,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        guard let data = try? JSONEncoder().encode(configuration) else {
            return
        }
        defaults.set(data, forKey: configurationKey)
    }
}
