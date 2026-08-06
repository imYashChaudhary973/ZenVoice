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

/// Which stream of builds an install follows.
///
/// Stable installs never see beta builds. A beta feed is signed with the same
/// key and verified identically — the channel selects what you are offered, it
/// does not relax any check.
public enum UpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta

    public var displayName: String {
        switch self {
        case .stable:
            return "Stable"
        case .beta:
            return "Beta"
        }
    }

    public var detail: String {
        switch self {
        case .stable:
            return "Released builds only."
        case .beta:
            return "Earlier access, with a higher chance of rough edges."
        }
    }
}

/// A dotted numeric version, compared component-wise.
///
/// Kept deliberately strict: anything that is not a run of dot-separated
/// integers fails to parse rather than being coerced, because a version that
/// silently compares wrong is how a downgrade slips through.
public struct AppVersion: Comparable, Equatable, CustomStringConvertible, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v")
            ? String(trimmed.dropFirst())
            : trimmed
        guard !withoutPrefix.isEmpty else { return nil }
        let parts = withoutPrefix.split(separator: ".", omittingEmptySubsequences: false)
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy(\.isNumber),
                  let value = Int(part) else {
                return nil
            }
            parsed.append(value)
        }
        guard !parsed.isEmpty else { return nil }
        components = parsed
    }

    public var description: String {
        components.map(String.init).joined(separator: ".")
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right {
                return left < right
            }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// The signed payload describing an available build.
///
/// This is the object the Ed25519 signature covers. It carries the archive's
/// SHA-256 so the signature transitively binds the actual bytes: the signature
/// proves the feed is ours, the hash proves the download matches the feed.
public struct UpdateManifest: Codable, Equatable, Sendable {
    public let version: String
    public let channel: UpdateChannel
    public let archiveURL: String
    public let sha256: String
    public let publishedAt: Date
    public let releaseNotesURL: String?
    public let minimumMacOSVersion: String?

    public init(
        version: String,
        channel: UpdateChannel,
        archiveURL: String,
        sha256: String,
        publishedAt: Date,
        releaseNotesURL: String? = nil,
        minimumMacOSVersion: String? = nil
    ) {
        self.version = version
        self.channel = channel
        self.archiveURL = archiveURL
        self.sha256 = sha256
        self.publishedAt = publishedAt
        self.releaseNotesURL = releaseNotesURL
        self.minimumMacOSVersion = minimumMacOSVersion
    }

    /// Canonical bytes for signing and verification.
    ///
    /// Sorted keys and a fixed date strategy so the producer and the verifier
    /// agree byte-for-byte; otherwise a valid signature could fail purely
    /// because two encoders ordered the JSON differently.
    public func canonicalPayload() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    public static func decode(from data: Data) throws -> UpdateManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UpdateManifest.self, from: data)
    }
}

/// A manifest plus its detached signature, as served by the update feed.
public struct SignedUpdateFeed: Codable, Equatable, Sendable {
    /// Base64 of the canonical manifest payload.
    public let manifest: String
    /// Base64 Ed25519 signature over the decoded manifest bytes.
    public let signature: String

    public init(manifest: String, signature: String) {
        self.manifest = manifest
        self.signature = signature
    }

    /// Builds a signed feed from a manifest and a signing closure.
    /// Used by release tooling and by checks; the app only ever verifies.
    public static func make(
        manifest: UpdateManifest,
        sign: (Data) throws -> Data
    ) throws -> SignedUpdateFeed {
        let payload = try manifest.canonicalPayload()
        let signature = try sign(payload)
        return SignedUpdateFeed(
            manifest: payload.base64EncodedString(),
            signature: signature.base64EncodedString()
        )
    }
}

/// Persisted updater settings. Disabled by default per ADR 0012.
public enum UpdatePreferences {
    private enum Key {
        static let automatic = "ZenVoice.updates.automatic"
        static let channel = "ZenVoice.updates.channel"
        static let lastCheck = "ZenVoice.updates.lastCheck"
    }

    public static func isAutomaticEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        guard defaults.object(forKey: Key.automatic) != nil else {
            return false
        }
        return defaults.bool(forKey: Key.automatic)
    }

    public static func setAutomaticEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: Key.automatic)
    }

    public static func channel(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> UpdateChannel {
        guard let raw = defaults.string(forKey: Key.channel),
              let channel = UpdateChannel(rawValue: raw) else {
            return .stable
        }
        return channel
    }

    public static func setChannel(
        _ channel: UpdateChannel,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(channel.rawValue, forKey: Key.channel)
    }

    public static func lastCheck(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Date? {
        let value = defaults.double(forKey: Key.lastCheck)
        return value > 0 ? Date(timeIntervalSince1970: value) : nil
    }

    public static func setLastCheck(
        _ date: Date,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastCheck)
    }
}
