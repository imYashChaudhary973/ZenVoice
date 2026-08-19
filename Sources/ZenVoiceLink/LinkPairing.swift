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

import CryptoKit
import Foundation
import Network
import Security

/// The shared secret that makes the link trustworthy.
///
/// The link uses TLS with a pre-shared key rather than certificates: for a
/// personal Mac-to-phone link there is no certificate authority worth
/// inventing, and a PSK authenticates *both* ends by construction — an
/// unpaired peer cannot complete the handshake, so there is no
/// application-level auth check to forget. The user transfers the key once, as
/// a short code, and it never leaves either Keychain afterwards.
public struct LinkPairingKey: Equatable, Sendable {
    public static let byteCount = 32

    public let material: Data

    public init(material: Data) throws {
        guard material.count == Self.byteCount else {
            throw LinkPairingError.invalidKey
        }
        self.material = material
    }

    public static func generate() -> LinkPairingKey {
        var bytes = Data(count: byteCount)
        _ = bytes.withUnsafeMutableBytes { raw in
            SecRandomCopyBytes(kSecRandomDefault, byteCount, raw.baseAddress!)
        }
        // `try!` is honest here: the length is a compile-time constant.
        return try! LinkPairingKey(material: bytes)
    }

    /// Human-transferable form: Crockford-style base32 in groups of four, so it
    /// can be read aloud or typed on a phone without `0`/`O` confusion.
    public var pairingCode: String {
        let encoded = Base32Crockford.encode(material)
        return stride(from: 0, to: encoded.count, by: 4).map { offset in
            let start = encoded.index(encoded.startIndex, offsetBy: offset)
            let end = encoded.index(
                start,
                offsetBy: min(4, encoded.count - offset)
            )
            return String(encoded[start..<end])
        }.joined(separator: "-")
    }

    public init(pairingCode: String) throws {
        let material = try Base32Crockford.decode(pairingCode)
        try self.init(material: material)
    }

    /// Short, stable fingerprint shown on both devices so the user can confirm
    /// they paired with the Mac they meant.
    public var fingerprint: String {
        let digest = SHA256.hash(data: material)
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        return stride(from: 0, to: 8, by: 4).map { offset in
            String(hex.dropFirst(offset).prefix(4))
        }.joined(separator: " ")
    }
}

public enum LinkPairingError: LocalizedError, Equatable {
    case invalidKey
    case invalidPairingCode
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The pairing key is not a valid 32-byte key."
        case .invalidPairingCode:
            return "That pairing code is not valid."
        case .keychain(let status):
            return "Keychain error \(status)."
        }
    }
}

public protocol LinkPairingKeyStoring: Sendable {
    func loadKey() throws -> LinkPairingKey?
    func saveKey(_ key: LinkPairingKey) throws
    func deleteKey() throws
}

/// Keychain-backed store. `WhenUnlockedThisDeviceOnly` matches the vault key:
/// the pairing secret must not travel in a backup to another machine.
public struct LinkPairingKeychainStore: LinkPairingKeyStoring {
    private let service: String
    private let account: String

    public init(service: String, account: String = "cross-device-link-key") {
        self.service = service
        self.account = account
    }

    public func loadKey() throws -> LinkPairingKey? {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]) { _, new in new } as CFDictionary
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw LinkPairingError.keychain(status)
        }
        guard let data = item as? Data else {
            throw LinkPairingError.invalidKey
        }
        return try LinkPairingKey(material: data)
    }

    public func saveKey(_ key: LinkPairingKey) throws {
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: key.material] as CFDictionary
        )
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw LinkPairingError.keychain(updateStatus)
        }
        let addQuery = baseQuery.merging([
            kSecValueData as String: key.material,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { _, new in new } as CFDictionary
        let addStatus = SecItemAdd(addQuery, nil)
        guard addStatus == errSecSuccess else {
            throw LinkPairingError.keychain(addStatus)
        }
    }

    public func deleteKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LinkPairingError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// In-memory store for checks and previews.
public final class InMemoryLinkPairingKeyStore: LinkPairingKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: LinkPairingKey?

    public init(key: LinkPairingKey? = nil) {
        self.key = key
    }

    public func loadKey() throws -> LinkPairingKey? {
        lock.lock()
        defer { lock.unlock() }
        return key
    }

    public func saveKey(_ key: LinkPairingKey) throws {
        lock.lock()
        defer { lock.unlock() }
        self.key = key
    }

    public func deleteKey() throws {
        lock.lock()
        defer { lock.unlock() }
        key = nil
    }
}

/// Builds the identical TLS-PSK parameters used by the listener and the client.
/// Both ends must derive them the same way or the handshake fails closed.
public enum LinkParameters {
    public static func make(key: LinkPairingKey) -> NWParameters {
        let options = NWProtocolTLS.Options()
        let identityHint = Data("ZenVoiceLink".utf8)
        key.material.withUnsafeBytes { raw in
            let secret = DispatchData(bytes: raw)
            identityHint.withUnsafeBytes { hintRaw in
                let hint = DispatchData(bytes: hintRaw)
                sec_protocol_options_add_pre_shared_key(
                    options.securityProtocolOptions,
                    secret as __DispatchData,
                    hint as __DispatchData
                )
            }
        }
        sec_protocol_options_append_tls_ciphersuite(
            options.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: UInt16(TLS_PSK_WITH_AES_128_GCM_SHA256))!
        )
        sec_protocol_options_set_min_tls_protocol_version(
            options.securityProtocolOptions,
            .TLSv12
        )

        let tcp = NWProtocolTCP.Options()
        tcp.connectionTimeout = 10
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30

        let parameters = NWParameters(tls: options, tcp: tcp)
        parameters.includePeerToPeer = true
        return parameters
    }
}

/// Crockford base32 without checksum: unambiguous to read aloud, and rejects
/// the characters people mistype (`I`, `L`, `O`, `U`) rather than guessing.
enum Base32Crockford {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    static func encode(_ data: Data) -> String {
        var output = ""
        var buffer = 0
        var bitsLeft = 0
        for byte in data {
            buffer = (buffer << 8) | Int(byte)
            bitsLeft += 8
            while bitsLeft >= 5 {
                let index = (buffer >> (bitsLeft - 5)) & 31
                bitsLeft -= 5
                output.append(alphabet[index])
            }
        }
        if bitsLeft > 0 {
            let index = (buffer << (5 - bitsLeft)) & 31
            output.append(alphabet[index])
        }
        return output
    }

    static func decode(_ text: String) throws -> Data {
        var buffer = 0
        var bitsLeft = 0
        var output = Data()
        for character in text.uppercased() {
            if character == "-" || character == " " { continue }
            let normalized: Character
            switch character {
            case "O": normalized = "0"
            case "I", "L": normalized = "1"
            default: normalized = character
            }
            guard let index = alphabet.firstIndex(of: normalized) else {
                throw LinkPairingError.invalidPairingCode
            }
            buffer = (buffer << 5) | index
            bitsLeft += 5
            if bitsLeft >= 8 {
                output.append(UInt8((buffer >> (bitsLeft - 8)) & 0xFF))
                bitsLeft -= 8
            }
        }
        return output
    }
}
