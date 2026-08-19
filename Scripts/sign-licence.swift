#!/usr/bin/env swift
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
//
// Issues a ZenVoice licence key.
//
//     ./Scripts/sign-licence.swift <order-number>
//
// The signing key is read from ~/.zenvoice-licence-signing-key and never from
// the repository. Losing that file means no new licences can be issued;
// leaking it means anyone can. Back it up somewhere a password manager would
// be proud of.
//
// The app only ever verifies, using the public key compiled into
// Sources/ZenVoiceCore/Licence.swift. Rotating the pair invalidates every key
// already sold, so it is a release-blocking change.

import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 2, let orderID = UInt32(arguments[1]) else {
    FileHandle.standardError.write(
        Data("usage: sign-licence.swift <order-number>\n".utf8)
    )
    exit(64)
}

let keyURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".zenvoice-licence-signing-key")
guard let stored = try? String(contentsOf: keyURL, encoding: .utf8),
      let keyData = Data(
        base64Encoded: stored.trimmingCharacters(in: .whitespacesAndNewlines)
      ),
      let signingKey = try? Curve25519.Signing.PrivateKey(
        rawRepresentation: keyData
      )
else {
    FileHandle.standardError.write(
        Data("no usable signing key at \(keyURL.path)\n".utf8)
    )
    exit(66)
}

// Payload layout must match LicenceVerifier.payload: version, order (UInt32
// big-endian), issue day (UInt32 big-endian, days since 1970).
let version: UInt8 = 1
let issuedDays = UInt32(Date().timeIntervalSince1970 / 86_400)
var payload: [UInt8] = [version]
for shift in [24, 16, 8, 0] {
    payload.append(UInt8((orderID >> UInt32(shift)) & 0xFF))
}
for shift in [24, 16, 8, 0] {
    payload.append(UInt8((issuedDays >> UInt32(shift)) & 0xFF))
}

let payloadData = Data(payload)
let signature = try signingKey.signature(for: payloadData)
let token = "ZV1-" + (payloadData + signature)
    .base64EncodedString()
    .replacingOccurrences(of: "+", with: "-")
    .replacingOccurrences(of: "/", with: "_")
    .replacingOccurrences(of: "=", with: "")

let issued = ISO8601DateFormatter()
issued.formatOptions = [.withFullDate]
print("order:  \(orderID)")
print("issued: \(issued.string(from: Date()))")
print("key:    \(token)")
