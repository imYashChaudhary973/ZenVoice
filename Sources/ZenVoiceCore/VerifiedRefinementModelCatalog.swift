import Foundation

public enum RefinementModelTier: String, Codable, CaseIterable, Sendable {
    case fast
    case balanced

    public var displayName: String {
        switch self {
        case .fast:
            "Fast"
        case .balanced:
            "Balanced"
        }
    }
}

public struct VerifiedRefinementModel:
    Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let filename: String
    public let tier: RefinementModelTier
    public let publisher: String
    public let sourceRepository: String
    public let sourceRevision: String
    public let upstreamRepository: String
    public let sha256: String
    public let fileSizeBytes: Int64
    public let minimumMemoryBytes: Int64
    public let format: String
    public let license: String
    public let licenseURL: String
    public let attribution: String
    public let languageSummary: String

    public var downloadURL: URL {
        URL(
            string:
                "\(sourceRepository)/resolve/\(sourceRevision)/\(filename)"
                + "?download=true"
        )!
    }

    public var formattedFileSize: String {
        ByteCountFormatter.string(
            fromByteCount: fileSizeBytes,
            countStyle: .file
        )
    }

    public var formattedMinimumMemory: String {
        ByteCountFormatter.string(
            fromByteCount: minimumMemoryBytes,
            countStyle: .memory
        )
    }

    public var licenseDocumentURL: URL {
        URL(string: licenseURL)!
    }
}

public enum VerifiedRefinementModelCatalog {
    public static let models: [VerifiedRefinementModel] = [
        VerifiedRefinementModel(
            id: "qwen2.5-0.5b-instruct-q4-k-m",
            displayName: "Qwen 2.5 0.5B",
            filename: "qwen2.5-0.5b-instruct-q4_k_m.gguf",
            tier: .fast,
            publisher: "Qwen",
            sourceRepository:
                "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            sourceRevision:
                "9217f5db79a29953eb74d5343926648285ec7e67",
            upstreamRepository:
                "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct",
            sha256:
                "74a4da8c9fdbcd15bd1f6d01d621410d31c6fc00986f5eb687824e7b93d7a9db",
            fileSizeBytes: 491_400_032,
            minimumMemoryBytes: 8_000_000_000,
            format: "GGUF Q4_K_M",
            license: "Apache-2.0",
            licenseURL:
                "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/blob/9217f5db79a29953eb74d5343926648285ec7e67/LICENSE",
            attribution:
                "Qwen2.5 0.5B Instruct, published and quantized by Qwen.",
            languageSummary:
                "Multilingual; upstream documents support for more than 29 languages."
        ),
        VerifiedRefinementModel(
            id: "qwen2.5-1.5b-instruct-q4-k-m",
            displayName: "Qwen 2.5 1.5B",
            filename: "qwen2.5-1.5b-instruct-q4_k_m.gguf",
            tier: .balanced,
            publisher: "Qwen",
            sourceRepository:
                "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF",
            sourceRevision:
                "91cad51170dc346986eccefdc2dd33a9da36ead9",
            upstreamRepository:
                "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct",
            sha256:
                "6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e",
            fileSizeBytes: 1_117_320_736,
            minimumMemoryBytes: 16_000_000_000,
            format: "GGUF Q4_K_M",
            license: "Apache-2.0",
            licenseURL:
                "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/blob/91cad51170dc346986eccefdc2dd33a9da36ead9/LICENSE",
            attribution:
                "Qwen2.5 1.5B Instruct, published and quantized by Qwen.",
            languageSummary:
                "Multilingual; upstream documents support for more than 29 languages."
        )
    ]

    public static func model(id: String) -> VerifiedRefinementModel? {
        models.first { $0.id == id }
    }

    public static func modelsDirectory(
        fileManager: FileManager = .default
    ) throws -> URL {
        let supportDirectory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return supportDirectory
            .appendingPathComponent("ZenVoice", isDirectory: true)
            .appendingPathComponent(
                "RefinementModels",
                isDirectory: true
            )
    }

    public static func installedURL(
        for model: VerifiedRefinementModel,
        fileManager: FileManager = .default
    ) throws -> URL {
        try modelsDirectory(fileManager: fileManager)
            .appendingPathComponent(model.filename)
    }

    public static func verify(
        _ fileURL: URL,
        for model: VerifiedRefinementModel,
        fileManager: FileManager = .default
    ) throws -> Bool {
        let values = try fileURL.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              Int64(values.fileSize ?? -1) == model.fileSizeBytes else {
            return false
        }
        return try VerifiedModelCatalog.sha256Hex(of: fileURL)
            == model.sha256
    }
}

public enum RefinementModelSelectionPreferences {
    public static let preferenceKey =
        "ZenVoice.selectedRefinementModelID"

    public static func load(
        defaults: UserDefaults = .standard
    ) -> VerifiedRefinementModel? {
        guard let id = defaults.string(forKey: preferenceKey) else {
            return nil
        }
        return VerifiedRefinementModelCatalog.model(id: id)
    }

    public static func save(
        _ model: VerifiedRefinementModel,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(model.id, forKey: preferenceKey)
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
    }
}

public enum LocalRefinementPrompt {
    /// The instruction block, which is identical for every dictation that
    /// shares a context string.
    ///
    /// Split out from the transcript so the runtime can prefill it once and
    /// reuse its KV cache. It is the definition of a stable prefix — byte for
    /// byte the same on every call when no next-dictation context is set — and
    /// recomputing it per dictation was most of the measured refinement
    /// latency.
    ///
    /// Ends with a special-token boundary, so tokenizing prefix and tail
    /// separately cannot merge tokens across the join.
    public static func systemPrefix(context: String = "") -> String {
        let safeContext = NextDictationContext.sanitized(context)
        let contextLine = safeContext.isEmpty
            ? "No additional context."
            : "Relevant spelling and topic context: \(safeContext)"
        return """
        <|im_start|>system
        You clean speech transcripts. Keep the original language and meaning. Do not add, replace, translate, or invent words. You may remove filler words and immediate repetitions, fix capitalization and punctuation, and format explicit line-break commands. \(contextLine) Return exactly one JSON object with one string field named text. No markdown or explanation.<|im_end|>

        """
    }

    /// The per-dictation half: the transcript and the assistant handoff.
    public static func tail(transcript: String) -> String {
        """
        <|im_start|>user
        \(transcript)<|im_end|>
        <|im_start|>assistant
        """
    }

    public static func make(
        transcript: String,
        context: String = ""
    ) -> String {
        systemPrefix(context: context) + tail(transcript: transcript)
    }
}

public enum LocalRefinementGuard {
    private struct Envelope: Decodable {
        let text: String
    }

    public static func validatedCandidate(
        output: String,
        original: String
    ) -> String? {
        guard let data = output.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(
                Envelope.self,
                from: data
              ) else {
            return nil
        }

        let candidate = envelope.text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !candidate.isEmpty else {
            return nil
        }

        // Deterministic Clean runs before the local model. The model may then
        // improve punctuation and capitalization, but it must preserve every
        // normalized token in the same order. A vocabulary-only comparison
        // would allow meaning-changing edits such as dropping "not" or
        // reordering "the app deletes the file."
        guard tokens(in: candidate) == tokens(in: original) else {
            return nil
        }
        return candidate
    }

    private static func tokens(in text: String) -> [String] {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        .components(
            separatedBy: CharacterSet.alphanumerics.inverted
        )
        .filter { !$0.isEmpty }
    }
}
