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
        // Worked examples rather than a longer instruction. At this parameter
        // count a model follows a demonstrated pattern far more reliably than
        // a described one, and the first attempt without them had Qwen 1.5B
        // answering {"drop":[1,2,3,4,5,6]} — delete the whole sentence — for a
        // transcript that needed no edits at all.
        //
        // Ordered filler, repetition, self-correction, then two no-ops. The
        // no-ops are load-bearing and go last: without a demonstrated "change
        // nothing" the model treats replying with *something* as the goal, and
        // most real dictation needs nothing removed. Adding the first one took
        // the rejection rate on clean speech from 67% to 42%.
        //
        // The self-correction example is the only one teaching a judgement
        // the deterministic rules cannot make — "Tuesday actually Wednesday"
        // needs to know which date survives, which no regex can decide.
        //
        // These sit inside the cached prefix, so they cost prefill once per
        // session and nothing per dictation.
        return """
        <|im_start|>system
        You find filler words in speech transcripts. The user sends numbered words. Reply with the numbers of the words to delete, as a JSON object with one array field named drop. Delete only hesitations, filler words such as um, uh, you know and like, stuttered or repeated restarts, and abandoned false starts. Keep every word that carries meaning. Never delete a negation or a number. Most transcripts need nothing deleted. \(contextLine) No markdown or explanation.<|im_end|>
        <|im_start|>user
        1 Um, 2 I 3 think 4 we 5 should 6 ship 7 it<|im_end|>
        <|im_start|>assistant
        {"drop":[1]}<|im_end|>
        <|im_start|>user
        1 We 2 should 3 we 4 should 5 revert 6 it<|im_end|>
        <|im_start|>assistant
        {"drop":[3,4]}<|im_end|>
        <|im_start|>user
        1 Send 2 it 3 on 4 Tuesday 5 actually 6 Wednesday<|im_end|>
        <|im_start|>assistant
        {"drop":[4,5]}<|im_end|>
        <|im_start|>user
        1 Ship 2 the 3 beta 4 on 5 Thursday<|im_end|>
        <|im_start|>assistant
        {"drop":[]}<|im_end|>
        <|im_start|>user
        1 The 2 migration 3 script 4 drops 5 the 6 index 7 before 8 the 9 backfill<|im_end|>
        <|im_start|>assistant
        {"drop":[]}<|im_end|>

        """
    }

    /// Splits a transcript into the words the model will index.
    ///
    /// Punctuation stays attached to its word, so deleting "Um," takes the
    /// comma with it.
    public static func words(in transcript: String) -> [String] {
        transcript
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    /// The per-dictation half: the transcript, plain.
    ///
    /// The reply is a list of phrases to delete rather than a rewritten
    /// transcript, which is the whole point. Generation costs 25-40 ms per
    /// token, so a reply that restates the transcript makes latency linear in
    /// dictation length and puts anything past ~120 words beyond the deadline.
    /// A drop list costs the same handful of tokens whether the dictation is
    /// twenty words or three hundred.
    ///
    /// Indices rather than quoted phrases, which was measured. Letting the
    /// model quote the span to delete made it more capable and more dangerous
    /// at once: it began removing meaningful text, taking clean speech from
    /// 4.0% to 4.4% word error rate, because a verbatim span holding no
    /// protected token can still be content the user wanted. Indices cannot
    /// express anything the guard cannot bound.
    public static func tail(transcript: String) -> String {
        let numbered = words(in: transcript)
            .enumerated()
            .map { "\($0.offset + 1) \($0.element)" }
            .joined(separator: " ")
        return """
        <|im_start|>user
        \(numbered)<|im_end|>
        <|im_start|>assistant
        """
    }

    public static func make(
        transcript: String,
        context: String = ""
    ) -> String {
        systemPrefix(context: context) + tail(transcript: transcript)
    }

    /// Constrains the reply to a JSON object holding one array of integers.
    ///
    /// The decoder is therefore incapable of emitting a word at all, which is
    /// a stronger safety property than inspecting a rewritten string after the
    /// fact: the previous design let the model write anything and then threw
    /// away 67% of it.
    public static let dropGrammar = #"""
    root ::= "{" ws "\"drop\"" ws ":" ws "[" ws list? ws "]" ws "}" ws
    list ::= int (ws "," ws int)*
    int ::= [0-9]+
    ws ::= [ \t\n]*
    """#
}

public enum LocalRefinementGuard {
    private struct Envelope: Decodable {
        let drop: [Int]
    }

    /// The most of a transcript the model may delete.
    ///
    /// Real dictation is not 40% filler. A model asking to remove more than
    /// that has misunderstood the task rather than found an unusually messy
    /// sentence, and the deterministic baseline is the better answer.
    public static let maximumDropFraction = 0.4

    /// Validates a drop list against the words it refers to.
    ///
    /// Returns the indices to delete, or nil to fall back. Deletion-only means
    /// the result is always a subsequence of what the user said, so the model
    /// cannot invent a word, substitute one, or reorder the sentence — those
    /// failures are unreachable by construction rather than caught after the
    /// fact, which is what the previous full-rewrite design had to attempt.
    /// What remains to check is that it deletes sensibly.
    public static func validatedDrops(
        output: String,
        words: [String]
    ) -> [Int]? {
        guard let data = output.data(using: .utf8),
              let envelope = try? JSONDecoder().decode(
                Envelope.self,
                from: data
              ) else {
            return nil
        }

        // One-based on the wire, because the prompt numbers from one.
        let indices = Set(envelope.drop.map { $0 - 1 })
        guard indices.allSatisfy({ $0 >= 0 && $0 < words.count }) else {
            return nil
        }
        guard !indices.isEmpty else {
            // The model agreeing there is nothing to remove is a valid answer,
            // and the commonest correct one.
            return []
        }
        guard Double(indices.count)
                <= Double(words.count) * maximumDropFraction else {
            return nil
        }
        // A negation or a quantity is never filler. This is the one rule
        // protecting meaning rather than tidiness, so it refuses the whole
        // edit rather than silently keeping the word — a model reaching for
        // "not" has misread the sentence, and its other choices are suspect.
        guard indices.allSatisfy({ !ProtectedTokens.isProtected(words[$0]) })
        else {
            return nil
        }
        return indices.sorted()
    }

    /// Rebuilds the transcript without the dropped words.
    public static func applying(
        drops: [Int],
        to words: [String]
    ) -> String {
        let dropped = Set(drops)
        return words.enumerated()
            .filter { !dropped.contains($0.offset) }
            .map(\.element)
            .joined(separator: " ")
    }
}
