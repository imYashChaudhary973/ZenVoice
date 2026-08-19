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
import Security

/// What ZenVoice costs, in one place.
///
/// One payment, no subscription, no account, no server to ask. The price is
/// stated in the currency it is charged in rather than localised, because a
/// converted figure that does not match the checkout total is worse than an
/// unfamiliar symbol.
public enum ZenVoicePricing {
    public static let oneTimePrice = "$9.99"
    public static let summary = "$9.99 once. No subscription, no account."
    public static let purchaseURL = URL(string: "https://zenvoice.app/buy")!
}

/// A verified licence.
public struct Licence: Equatable, Sendable {
    /// Order number from the checkout that issued this licence.
    public let orderID: UInt32
    /// Day the licence was signed. Whole days: a licence is not a session, and
    /// storing the minute invites a false sense of precision.
    public let issuedAt: Date
    /// The token exactly as the user pasted it, so About can show it back and
    /// the user can copy it to another Mac.
    public let token: String

    public init(orderID: UInt32, issuedAt: Date, token: String) {
        self.orderID = orderID
        self.issuedAt = issuedAt
        self.token = token
    }
}

public enum LicenceStatus: Equatable, Sendable {
    /// No licence stored. ZenVoice stays fully functional: locking someone out
    /// of a dictation tool they are mid-sentence in would be a worse product
    /// than asking them to pay for it.
    case unlicensed
    case licensed(Licence)

    public var isLicensed: Bool {
        if case .licensed = self { return true }
        return false
    }
}

public enum LicenceError: LocalizedError, Equatable {
    case malformed
    case unsupportedVersion(UInt8)
    case signatureRejected
    case keychain(OSStatus)

    public var errorDescription: String? {
        switch self {
        case .malformed:
            return "That does not look like a ZenVoice licence key. "
                + "Paste the whole key from your receipt, starting with ZV1-."
        case .unsupportedVersion(let version):
            return "This licence key was issued for a newer version of "
                + "ZenVoice (format \(version)). Update ZenVoice and try again."
        case .signatureRejected:
            return "This licence key is not valid. Check it was pasted "
                + "completely, or reply to your receipt to have it reissued."
        case .keychain(let status):
            return "ZenVoice could not store the licence key in your "
                + "Keychain (\(status))."
        }
    }
}

/// Offline licence verification.
///
/// The token carries its own proof: a detached Ed25519 signature over the
/// payload, checked against a public key compiled into the app. There is no
/// licence server, no phone-home, and no account — which is the only design
/// consistent with an app that promises nothing leaves the Mac.
///
/// The matching private key never exists in this repository. It lives on the
/// machine that issues receipts, and `Scripts/sign-licence.swift` is the only
/// thing that touches it.
public enum LicenceVerifier {
    /// Format version this build issues and understands.
    public static let currentVersion: UInt8 = 1

    /// Prefix so a key is recognisable in a receipt, a support email, or a
    /// screenshot, and so a pasted paragraph can be trimmed to the key.
    public static let tokenPrefix = "ZV1-"

    /// Ed25519 public key. Rotating it invalidates every previously issued
    /// licence, so it is a release-blocking change, not a routine one.
    private static let publicKeyBytes: [UInt8] = [
        218, 33, 252, 106, 162, 28, 2, 0, 253, 37, 253, 130, 5, 11, 161, 151,
        78, 28, 49, 205, 40, 242, 245, 47, 24, 47, 43, 213, 15, 56, 38, 255
    ]

    private static let payloadLength = 9
    private static let signatureLength = 64

    /// Verifies a pasted token and returns the licence it carries.
    ///
    /// Whitespace and surrounding quotes are tolerated because the key arrives
    /// in an email and gets pasted with whatever came near it. Nothing else is
    /// forgiven: the signature either covers these exact bytes or it does not.
    public static func verify(_ pasted: String) throws -> Licence {
        let token = normalized(pasted)
        guard token.hasPrefix(tokenPrefix) else {
            throw LicenceError.malformed
        }
        let encoded = String(token.dropFirst(tokenPrefix.count))
        guard let blob = decodeBase64URL(encoded),
              blob.count == payloadLength + signatureLength
        else {
            throw LicenceError.malformed
        }

        let payload = blob.prefix(payloadLength)
        let signature = blob.suffix(signatureLength)
        let version = payload[payload.startIndex]
        guard version == currentVersion else {
            throw LicenceError.unsupportedVersion(version)
        }

        guard let publicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: Data(publicKeyBytes)
        ),
            publicKey.isValidSignature(Data(signature), for: Data(payload))
        else {
            throw LicenceError.signatureRejected
        }

        let bytes = [UInt8](payload)
        let orderID = UInt32(bytes[1]) << 24 | UInt32(bytes[2]) << 16
            | UInt32(bytes[3]) << 8 | UInt32(bytes[4])
        let issuedDays = UInt32(bytes[5]) << 24 | UInt32(bytes[6]) << 16
            | UInt32(bytes[7]) << 8 | UInt32(bytes[8])
        return Licence(
            orderID: orderID,
            issuedAt: Date(timeIntervalSince1970: Double(issuedDays) * 86_400),
            token: token
        )
    }

    /// Builds the signed payload for a licence. Used by the signing script and
    /// by the checks; the app itself only ever verifies.
    public static func payload(orderID: UInt32, issuedAt: Date) -> Data {
        let days = UInt32(max(0, issuedAt.timeIntervalSince1970 / 86_400))
        var bytes: [UInt8] = [currentVersion]
        for shift in [24, 16, 8, 0] {
            bytes.append(UInt8((orderID >> UInt32(shift)) & 0xFF))
        }
        for shift in [24, 16, 8, 0] {
            bytes.append(UInt8((days >> UInt32(shift)) & 0xFF))
        }
        return Data(bytes)
    }

    /// Assembles a pasteable token from a payload and its signature.
    public static func token(payload: Data, signature: Data) -> String {
        tokenPrefix + encodeBase64URL(payload + signature)
    }

    private static func normalized(_ pasted: String) -> String {
        String(
            pasted
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'<>"))
                .filter { !$0.isWhitespace }
        )
    }

    /// Base64URL, so a licence survives an email client, a URL, and a
    /// double-click selection without acquiring `+` or `/`.
    public static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func decodeBase64URL(_ string: String) -> Data? {
        var standard = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = standard.count % 4
        if remainder > 0 {
            standard.append(String(repeating: "=", count: 4 - remainder))
        }
        return Data(base64Encoded: standard)
    }
}

/// Where the licence token is kept.
public protocol LicenceStoring: Sendable {
    func load() throws -> String?
    func save(_ token: String) throws
    func clear() throws
}

/// Keychain-backed store, matching the transcript key and the Cloud AI key:
/// `WhenUnlockedThisDeviceOnly`, so a licence does not travel in a backup to a
/// machine it was not bought for.
public struct LicenceKeychainStore: LicenceStoring {
    private let service: String
    private let account: String

    public init(
        policy: BundleIdentifierPolicy,
        account: String = "licence-token"
    ) {
        self.service = RuntimeIdentity.keychainServiceName(policy: policy)
        self.account = account
    }

    public func load() throws -> String? {
        let query = baseQuery.merging([
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]) { _, new in new } as CFDictionary
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw LicenceError.keychain(status)
        }
        guard let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return token
    }

    public func save(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw LicenceError.malformed
        }
        let update = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw LicenceError.keychain(update)
        }
        let add = baseQuery.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]) { _, new in new } as CFDictionary
        let status = SecItemAdd(add, nil)
        guard status == errSecSuccess else {
            throw LicenceError.keychain(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenceError.keychain(status)
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

/// In-memory store for checks and previews.
public final class InMemoryLicenceStore: LicenceStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func load() throws -> String? {
        lock.withLock { token }
    }

    public func save(_ token: String) throws {
        lock.withLock { self.token = token }
    }

    public func clear() throws {
        lock.withLock { token = nil }
    }
}

/// Resolves stored bytes into a status.
///
/// A stored token that no longer verifies resolves to `.unlicensed` rather than
/// to an error: the app must still open, and About is where the user is told
/// why.
public enum LicenceResolver {
    public static func status(from store: any LicenceStoring) -> LicenceStatus {
        guard let token = ((try? store.load()) ?? nil), !token.isEmpty else {
            return .unlicensed
        }
        guard let licence = try? LicenceVerifier.verify(token) else {
            return .unlicensed
        }
        return .licensed(licence)
    }
}
