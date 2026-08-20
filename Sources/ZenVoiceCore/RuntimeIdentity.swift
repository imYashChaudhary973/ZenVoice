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

/// Errors thrown when the runtime identity cannot be resolved safely.
public enum RuntimeIdentityError: LocalizedError {
    case missingBundleIdentifier
    case foreignBundleIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .missingBundleIdentifier:
            return "ZenVoice could not find a bundle identifier for this process."
        case .foreignBundleIdentifier(let identifier):
            return "ZenVoice is running with an unrecognized bundle identifier: \(identifier)."
        }
    }
}

/// A resolved bundle-identifier policy.
///
/// Only the production identifier or an explicitly allowed QA identifier is
/// accepted. The initializer is internal so callers outside `ZenVoiceCore`
/// cannot manufacture a production policy; they must obtain one through
/// ``RuntimeIdentity/policy(from:allowedQAIdentifiers:)``.
public struct BundleIdentifierPolicy: Sendable {
    internal enum Kind: Sendable {
        case production
        case qa(identifier: String)
    }

    internal let kind: Kind

    internal init(kind: Kind) {
        self.kind = kind
    }
}

/// Resolves the runtime identity of ZenVoice so that tests, unsigned hosts,
/// and foreign bundles cannot accidentally use the production Application
/// Support path, UserDefaults suite, or Keychain namespace.
///
/// The production identifier is `dev.yashchaudhary.ZenVoice`. Any other
/// identifier is rejected unless it is listed in `allowedQAIdentifiers`.
public enum RuntimeIdentity {
    /// The canonical production bundle identifier.
    public static let productionBundleID = "dev.yashchaudhary.ZenVoice"

    /// Resolves the bundle-identifier policy for the given bundle.
    ///
    /// - Parameters:
    ///   - bundle: The bundle to inspect. Defaults to `Bundle.main`.
    ///   - allowedQAIdentifiers: Additional bundle identifiers that are
    ///     accepted as QA/test identities. The production identifier is always
    ///     accepted.
    /// - Throws: ``RuntimeIdentityError`` if the bundle identifier is missing,
    ///   empty, or neither the production identifier nor an allowed QA
    ///   identifier.
    public static func policy(
        from bundle: Bundle = .main,
        allowedQAIdentifiers: [String] = []
    ) throws -> BundleIdentifierPolicy {
        guard let raw = bundle.bundleIdentifier, !raw.isEmpty else {
            throw RuntimeIdentityError.missingBundleIdentifier
        }
        if raw == productionBundleID {
            return BundleIdentifierPolicy(kind: .production)
        }
        if allowedQAIdentifiers.contains(raw) {
            return BundleIdentifierPolicy(kind: .qa(identifier: raw))
        }
        throw RuntimeIdentityError.foreignBundleIdentifier(raw)
    }

    /// Returns the resolved bundle identifier for the given policy.
    public static func resolvedBundleID(
        policy: BundleIdentifierPolicy
    ) -> String {
        switch policy.kind {
        case .production:
            return productionBundleID
        case .qa(let identifier):
            return identifier
        }
    }

    /// Returns the UserDefaults suite name for the resolved identity.
    public static func defaultsSuiteName(
        policy: BundleIdentifierPolicy
    ) -> String {
        resolvedBundleID(policy: policy)
    }

    /// Returns the Keychain service name for the vault key.
    public static func keychainServiceName(
        policy: BundleIdentifierPolicy
    ) -> String {
        "\(resolvedBundleID(policy: policy)).vault"
    }

    /// Returns the base directory under Application Support for the resolved
    /// identity. The directory is not created by this call.
    public static func applicationSupportRoot(
        fileManager: FileManager = .default,
        policy: BundleIdentifierPolicy
    ) throws -> URL {
        let parent = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        return parent
            .appendingPathComponent(
                resolvedBundleID(policy: policy),
                isDirectory: true
            )
    }

    /// Returns a `UserDefaults` instance tied to the resolved identity.
    ///
    /// The production app already owns the standard defaults domain for its
    /// bundle identifier. Re-opening that same identifier as a suite is
    /// rejected by Foundation and falls back unpredictably. QA identities use
    /// an explicit suite so their preferences remain isolated.
    public static func userDefaults(
        for policy: BundleIdentifierPolicy
    ) -> UserDefaults {
        switch policy.kind {
        case .production:
            return .standard
        case .qa(let identifier):
            return UserDefaults(suiteName: identifier) ?? .standard
        }
    }

    /// Convenience accessor that resolves the policy for the current process.
    ///
    /// When the bundle identifier is the production identifier or an allowed QA
    /// identifier, this returns a `UserDefaults` instance backed by the resolved
    /// suite name. Otherwise it falls back to `.standard`. Callers that must fail
    /// closed should call ``policy(from:allowedQAIdentifiers:)`` directly and
    /// handle the error.
    public static func userDefaults() -> UserDefaults {
        guard let policy = try? RuntimeIdentity.policy() else {
            return .standard
        }
        return userDefaults(for: policy)
    }
}
