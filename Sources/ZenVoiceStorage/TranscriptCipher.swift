import CryptoKit
import Foundation
import Security

public protocol VaultKeyProviding {
    func loadOrCreateKeyData() throws -> Data
    func deleteKey() throws
}

public enum VaultKeyError: LocalizedError {
    case keychain(OSStatus)
    case invalidKey

    public var errorDescription: String? {
        switch self {
        case .keychain(let status):
            return "ZenVoice could not access its history encryption key (\(status))."
        case .invalidKey:
            return "ZenVoice history has an invalid encryption key."
        }
    }
}

public final class KeychainVaultKeyProvider: VaultKeyProviding {
    private let service: String
    private let account: String

    public init(
        service: String = "dev.yashchaudhary.ZenVoice.vault",
        account: String = "transcript-encryption-key"
    ) {
        self.service = service
        self.account = account
    }

    public func loadOrCreateKeyData() throws -> Data {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new } as CFDictionary

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecSuccess {
            guard let data = item as? Data, data.count == 32 else {
                throw VaultKeyError.invalidKey
            }
            return data
        }
        guard status == errSecItemNotFound else {
            throw VaultKeyError.keychain(status)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let addQuery = baseQuery.merging([
            kSecValueData as String: keyData,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new } as CFDictionary
        let addStatus = SecItemAdd(addQuery, nil)

        if addStatus == errSecDuplicateItem {
            return try loadOrCreateKeyData()
        }
        guard addStatus == errSecSuccess else {
            throw VaultKeyError.keychain(addStatus)
        }
        return keyData
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw VaultKeyError.keychain(status)
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

struct TranscriptCipher {
    private static let contextualHeader = Data("ZV2".utf8)
    private let key: SymmetricKey

    init(keyProvider: VaultKeyProviding) throws {
        let keyData = try keyProvider.loadOrCreateKeyData()
        guard keyData.count == 32 else {
            throw VaultKeyError.invalidKey
        }
        key = SymmetricKey(data: keyData)
    }

    func seal(_ text: String, context: String) throws -> Data {
        let sealedBox = try AES.GCM.seal(
            Data(text.utf8),
            using: key,
            authenticating: Data(context.utf8)
        )
        guard let combined = sealedBox.combined else {
            throw VaultKeyError.invalidKey
        }
        return Self.contextualHeader + combined
    }

    func open(_ data: Data, context: String) throws -> String {
        let clearData: Data
        if data.starts(with: Self.contextualHeader) {
            let sealedBox = try AES.GCM.SealedBox(
                combined: data.dropFirst(Self.contextualHeader.count)
            )
            clearData = try AES.GCM.open(
                sealedBox,
                using: key,
                authenticating: Data(context.utf8)
            )
        } else {
            // Version 1 records predate authenticated field binding.
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            clearData = try AES.GCM.open(sealedBox, using: key)
        }
        guard let text = String(data: clearData, encoding: .utf8) else {
            throw VaultKeyError.invalidKey
        }
        return text
    }
}
