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

/// Encrypted speaker gallery. Sidecar JSON next to Meetings; caller passes
/// the `Speakers/` directory. Display names sealed with TranscriptCipher.
public struct SpeakerRegistry {
    public struct Speaker: Equatable, Identifiable, Sendable {
        public var id: UUID
        public var displayName: String
        public var enrolledAt: Date
        public var embedding: [Float]?

        public init(
            id: UUID,
            displayName: String,
            enrolledAt: Date,
            embedding: [Float]? = nil
        ) {
            self.id = id
            self.displayName = displayName
            self.enrolledAt = enrolledAt
            self.embedding = embedding
        }
    }

    public enum RegistryError: LocalizedError {
        case escapedDirectory
        case missingSpeaker
        case io(String)

        public var errorDescription: String? {
            switch self {
            case .escapedDirectory:
                return "Speaker path left the Speakers folder."
            case .missingSpeaker:
                return "That speaker is not in the gallery."
            case .io(let message):
                return message
            }
        }
    }

    public let directoryURL: URL
    private let keyProvider: VaultKeyProviding
    private let fileManager: FileManager

    public init(
        directoryURL: URL,
        keyProvider: VaultKeyProviding,
        fileManager: FileManager = .default
    ) {
        self.directoryURL = directoryURL
        self.keyProvider = keyProvider
        self.fileManager = fileManager
    }

    public static func displayNameContext(_ id: UUID) -> String {
        "speaker.displayName.\(id.uuidString.lowercased())"
    }

    public func enroll(name: String, embedding: [Float]? = nil) throws -> Speaker {
        let speaker = Speaker(
            id: UUID(),
            displayName: name,
            enrolledAt: Date(),
            embedding: embedding.flatMap { $0.isEmpty ? nil : $0 }
        )
        try write(speaker)
        return speaker
    }

    public func match(embedding: [Float]) throws -> Speaker? {
        guard embedding.count >= 1 else { return nil }
        let enrolled = try all().filter { ($0.embedding?.count ?? 0) >= 1 }
        guard enrolled.count >= 1 else { return nil }
        var best: Speaker?
        var bestScore: Float = -.greatestFiniteMagnitude
        for speaker in enrolled {
            guard let vector = speaker.embedding,
                  let score = Self.cosine(embedding, vector)
            else { continue }
            if score > bestScore {
                bestScore = score
                best = speaker
            }
        }
        return best
    }

    public func rename(id: UUID, name: String) throws {
        var speaker = try load(id: id)
        speaker.displayName = name
        try write(speaker)
    }

    public func all() throws -> [Speaker] {
        try ensureDirectory()
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        return try contents
            .filter { $0.pathExtension == "json" }
            .map { try load(url: $0) }
            .sorted { $0.enrolledAt > $1.enrolledAt }
    }

    public func delete(id: UUID) throws {
        let url = sidecarURL(for: id)
        try confirmInsideDirectory(url)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private struct Sidecar: Codable {
        var id: UUID
        var enrolledAt: Date
        var displayNameCiphertext: Data
        var embedding: Data?
    }

    private func write(_ speaker: Speaker) throws {
        try ensureDirectory()
        let url = sidecarURL(for: speaker.id)
        try confirmInsideDirectory(url)
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        let sidecar = Sidecar(
            id: speaker.id,
            enrolledAt: speaker.enrolledAt,
            displayNameCiphertext: try cipher.seal(
                speaker.displayName,
                context: Self.displayNameContext(speaker.id)
            ),
            embedding: Self.data(from: speaker.embedding)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(sidecar).write(to: url, options: .atomic)
    }

    private func load(id: UUID) throws -> Speaker {
        let url = sidecarURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw RegistryError.missingSpeaker
        }
        return try load(url: url)
    }

    private func load(url: URL) throws -> Speaker {
        try confirmInsideDirectory(url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sidecar = try decoder.decode(Sidecar.self, from: Data(contentsOf: url))
        let cipher = try TranscriptCipher(keyProvider: keyProvider)
        let name = try cipher.open(
            sidecar.displayNameCiphertext,
            context: Self.displayNameContext(sidecar.id)
        )
        return Speaker(
            id: sidecar.id,
            displayName: name,
            enrolledAt: sidecar.enrolledAt,
            embedding: Self.floats(from: sidecar.embedding)
        )
    }

    private func sidecarURL(for id: UUID) -> URL {
        directoryURL
            .appendingPathComponent(id.uuidString.lowercased())
            .appendingPathExtension("json")
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let resolved = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        let parent = directoryURL.deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(parent.path + "/") else {
            throw RegistryError.escapedDirectory
        }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: resolved.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw RegistryError.io("Speakers folder is missing.")
        }
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: resolved.path
        )
    }

    private func confirmInsideDirectory(_ url: URL) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let root = directoryURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw RegistryError.escapedDirectory
        }
    }

    private static func data(from embedding: [Float]?) -> Data? {
        guard let embedding, !embedding.isEmpty else { return nil }
        return embedding.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    private static func floats(from data: Data?) -> [Float]? {
        guard let data, !data.isEmpty,
              data.count % MemoryLayout<Float>.size == 0
        else { return nil }
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }

    // ponytail: O(n) scan, ANN if the gallery is large
    private static func cosine(_ a: [Float], _ b: [Float]) -> Float? {
        guard a.count == b.count, !a.isEmpty else { return nil }
        var dot: Float = 0
        var na: Float = 0
        var nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        let denom = na.squareRoot() * nb.squareRoot()
        guard denom > 0 else { return nil }
        return dot / denom
    }
}
