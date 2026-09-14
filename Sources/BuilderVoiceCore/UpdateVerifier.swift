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

public enum UpdateVerificationError: LocalizedError, Equatable {
    case updatesDisabled
    case malformedFeed
    case malformedSignature
    case invalidPublicKey
    case signatureRejected
    case insecureURL(String)
    case channelMismatch(expected: UpdateChannel, found: UpdateChannel)
    case notAnUpgrade(installed: String, offered: String)
    case unreadableVersion(String)
    case hashMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .updatesDisabled:
            return "Automatic updates are turned off."
        case .malformedFeed:
            return "The update feed could not be read."
        case .malformedSignature:
            return "The update feed's signature could not be read."
        case .invalidPublicKey:
            return "The bundled update signing key is not usable."
        case .signatureRejected:
            return "The update feed's signature did not verify."
        case .insecureURL:
            return "The update feed points at a non-HTTPS URL."
        case .channelMismatch(let expected, let found):
            return "That update is for the \(found.displayName) channel; "
                + "this install follows \(expected.displayName)."
        case .notAnUpgrade(let installed, let offered):
            return "Version \(offered) is not newer than the installed "
                + "\(installed)."
        case .unreadableVersion(let value):
            return "Could not read the version \"\(value)\"."
        case .hashMismatch:
            return "The downloaded update did not match the signed checksum."
        }
    }
}

/// Verifies update feeds. Every path here is fail-closed: any doubt rejects.
///
/// There is intentionally no "warn and continue" and no user override. An
/// updater that can be talked into installing something it could not verify is
/// worse than no updater, because it carries the authority to replace the app
/// binary (ADR 0012).
public struct UpdateVerifier: Sendable {
    private let publicKey: Curve25519.Signing.PublicKey

    /// - Parameter publicKeyBase64: the release signing public key compiled
    ///   into the app.
    public init(publicKeyBase64: String) throws {
        guard let raw = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
        else {
            throw UpdateVerificationError.invalidPublicKey
        }
        publicKey = key
    }

    public init(publicKey: Curve25519.Signing.PublicKey) {
        self.publicKey = publicKey
    }

    /// Verifies the signature and returns the manifest it covers.
    ///
    /// The manifest is decoded from the *same bytes* that were verified, never
    /// re-encoded from a parsed object — re-encoding would let a mismatch
    /// between the signed bytes and the used bytes go unnoticed.
    public func verifiedManifest(
        in feed: SignedUpdateFeed
    ) throws -> UpdateManifest {
        guard let payload = Data(base64Encoded: feed.manifest) else {
            throw UpdateVerificationError.malformedFeed
        }
        guard let signature = Data(base64Encoded: feed.signature),
              !signature.isEmpty else {
            throw UpdateVerificationError.malformedSignature
        }
        guard publicKey.isValidSignature(signature, for: payload) else {
            throw UpdateVerificationError.signatureRejected
        }
        guard let manifest = try? UpdateManifest.decode(from: payload) else {
            throw UpdateVerificationError.malformedFeed
        }
        return manifest
    }

    /// Full acceptance check: signature, transport, channel, and version.
    ///
    /// Returns the manifest only when every gate passes.
    public func acceptableUpdate(
        in feed: SignedUpdateFeed,
        installedVersion: String,
        channel: UpdateChannel,
        updatesEnabled: Bool = true
    ) throws -> UpdateManifest {
        guard updatesEnabled else {
            throw UpdateVerificationError.updatesDisabled
        }
        let manifest = try verifiedManifest(in: feed)

        try Self.requireHTTPS(manifest.archiveURL)
        if let notes = manifest.releaseNotesURL {
            try Self.requireHTTPS(notes)
        }

        guard manifest.channel == channel else {
            throw UpdateVerificationError.channelMismatch(
                expected: channel,
                found: manifest.channel
            )
        }

        guard let installed = AppVersion(installedVersion) else {
            throw UpdateVerificationError.unreadableVersion(installedVersion)
        }
        guard let offered = AppVersion(manifest.version) else {
            throw UpdateVerificationError.unreadableVersion(manifest.version)
        }
        // Strictly greater: a replayed older feed must not walk the user back.
        guard installed < offered else {
            throw UpdateVerificationError.notAnUpgrade(
                installed: installed.description,
                offered: offered.description
            )
        }
        return manifest
    }

    /// Binds the signed manifest to the bytes actually downloaded.
    ///
    /// The signature proves the feed is ours; this proves the archive is the
    /// one that feed described. Both are required before anything is replaced.
    public func verifyArchive(
        _ data: Data,
        matches manifest: UpdateManifest
    ) throws {
        let digest = SHA256.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        let expected = manifest.sha256
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard actual == expected else {
            throw UpdateVerificationError.hashMismatch(
                expected: expected,
                actual: actual
            )
        }
    }

    private static func requireHTTPS(_ string: String) throws {
        guard let components = URLComponents(string: string),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false else {
            throw UpdateVerificationError.insecureURL(string)
        }
    }
}
