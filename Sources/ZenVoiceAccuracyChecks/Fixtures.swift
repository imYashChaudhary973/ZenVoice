import AVFoundation
import Foundation

/// Deterministic speech fixtures.
///
/// Sentences are chosen to be hostile to dictation: technical vocabulary,
/// proper nouns, and minimal pairs that small models reliably confuse
/// (bearer/barrier, pull request/full request, middleware/middle where).
enum Fixtures {
    struct Sentence {
        let id: String
        let label: String
        /// Clauses a speaker would naturally pause between.
        let phrases: [String]
        /// What is actually voiced, when it differs from the reference.
        ///
        /// Used for disfluency fixtures: the speaker says "um, I think we
        /// should, we should ship it", the reference is what they meant. That
        /// gap is precisely what refinement claims to close, so it is the only
        /// way to measure whether refinement earns its place.
        var spokenPhrases: [String]?

        /// The reference transcript, without any pause markup.
        var text: String { phrases.joined(separator: " ") }

        /// What is handed to the synthesiser. The silences matter: without
        /// them the fixture is one unbroken utterance, live dictation never
        /// finds a pause to cut at, and segmented decoding is indistinguishable
        /// from whole-recording decoding. Real dictation has pauses, so the
        /// fixtures must too.
        var spoken: String {
            (spokenPhrases ?? phrases)
                .joined(separator: " [[slnc \(pauseMilliseconds)]] ")
        }
    }

    /// Live dictation only asks whether a phrase has ended on a 0.35 s timer,
    /// and needs 0.70 s of silence to say yes. A pause barely over 0.70 s
    /// leaves a detection window narrower than the polling interval, so
    /// boundaries get missed at random. 1.4 s leaves a 0.70 s window — twice
    /// the poll interval — which makes segmentation deterministic without
    /// being an unrealistic pause for dictation.
    static let pauseMilliseconds = 1_400

    struct Clip {
        let sentence: Sentence
        let wordsPerMinute: Int
        let url: URL

        var name: String {
            wordsPerMinute > 0
                ? "\(sentence.id)@\(wordsPerMinute)wpm"
                : sentence.id
        }
    }

    static let sentences: [Sentence] = [
        Sentence(
            id: "auth",
            label: "authentication middleware",
            phrases: [
                "Please refactor the authentication middleware",
                "so it validates the bearer token before it queries the "
                    + "Postgres replica",
                "and returns unauthorized instead of a server error."
            ]
        ),
        Sentence(
            id: "k8s",
            label: "Kubernetes sidecar",
            phrases: [
                "The Kubernetes cluster is throttling",
                "because the sidecar proxy keeps retrying idempotent requests",
                "against a stale endpoint slice in the staging namespace."
            ]
        ),
        Sentence(
            id: "beta",
            label: "beta ship criteria",
            phrases: [
                "Ship the beta on Thursday",
                "only if the crash rate stays low",
                "and the onboarding flow is fully localized for Hindi Tamil "
                    + "and Marathi speakers."
            ]
        ),
        Sentence(
            id: "migration",
            label: "migration review",
            phrases: [
                "I asked Priya to review the pull request",
                "but she said the migration script drops the index before "
                    + "the backfill completes",
                "which would lock the whole table."
            ]
        )
    ]

    /// Relaxed, brisk, and genuinely fast dictation.
    static let speakingRates = [170, 280, 380]

    /// A single dictation long enough to cross Whisper's 30-second window
    /// boundary, where it starts a fresh decode conditioned on what it produced
    /// for the previous window. That carry-over is the same mechanism that
    /// fabricated an entire clause when previous transcript text was fed in as
    /// an initial prompt, so long-form output needs checking for invented and
    /// repeated content — not just word error rate.
    static let longFormSentence = Sentence(
        id: "longform",
        label: "multi-paragraph dictation",
        phrases: sentences.flatMap(\.phrases)
    )

    static let longFormRates = [170, 280]

    /// Hindi, in Devanagari. Renders with the `Lekha` voice when it is
    /// installed; skipped otherwise.
    ///
    /// Worth its own coverage because it exercises two things English never
    /// touches: multilingual decoding, and ``LocalTransliterator`` when the
    /// user picks Hinglish output.
    static let hindiSentences: [Sentence] = [
        Sentence(
            id: "hi-meeting",
            label: "meeting note",
            phrases: [
                "कल की बैठक में हमने बजट पर चर्चा की",
                "और अगले महीने की योजना तय की।"
            ]
        ),
        Sentence(
            id: "hi-review",
            label: "code review note",
            phrases: [
                "प्रिया ने कहा कि यह बदलाव ठीक है",
                "लेकिन परीक्षण पहले चलाना होगा।"
            ]
        )
    ]

    /// Dictation as people actually speak it — hesitations, doubled words, and
    /// a mid-sentence restart. The reference is what the speaker meant.
    ///
    /// Refinement should move the transcript *towards* these references. If it
    /// moves away, it is costing accuracy for the sake of tidiness.
    static let disfluentSentences: [Sentence] = [
        Sentence(
            id: "dis-filler",
            label: "hesitations",
            phrases: [
                "I think we should ship the beta on Thursday."
            ],
            spokenPhrases: [
                "Um, I think we should, um, ship the beta on Thursday."
            ]
        ),
        Sentence(
            id: "dis-doubled",
            label: "doubled words",
            phrases: [
                "Please review the migration script before the release."
            ],
            spokenPhrases: [
                "Please review the the migration script before the release."
            ]
        ),
        Sentence(
            id: "dis-restart",
            label: "spoken restart",
            phrases: [
                "Create a sign-up page using Swift."
            ],
            spokenPhrases: [
                "Create a login page, no wait, a sign-up page using Swift."
            ]
        )
    ]

    static let disfluentRates = [170]

    static func renderDisfluent(
        into directory: URL
    ) throws -> [Clip] {
        try render(
            disfluentSentences.map { ($0, disfluentRates) },
            into: directory
        )
    }

    static let hindiVoice = "Lekha"
    static let hindiRates = [170, 260]

    static func isHindiVoiceInstalled() -> Bool {
        guard let listing = try? capture(
            "/usr/bin/say",
            ["-v", "?"]
        ) else {
            return false
        }
        return listing.contains(hindiVoice)
    }

    static func renderHindi(
        into directory: URL
    ) throws -> [Clip] {
        try render(
            hindiSentences.map { ($0, hindiRates) },
            into: directory,
            voice: hindiVoice
        )
    }

    enum FixtureError: LocalizedError {
        case synthesisUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .synthesisUnavailable(let detail):
                return "Speech synthesis is unavailable: \(detail)"
            }
        }
    }

    /// Renders every sentence at every speaking rate into 16 kHz mono float32
    /// WAV files — the exact format the recorder produces. Results are cached
    /// on disk so repeat runs skip synthesis.
    static func render(
        into directory: URL
    ) throws -> [Clip] {
        try render(
            sentences.map { ($0, speakingRates) },
            into: directory
        )
    }

    static func renderLongForm(
        into directory: URL
    ) throws -> [Clip] {
        try render([(longFormSentence, longFormRates)], into: directory)
    }

    private static func render(
        _ plan: [(Sentence, [Int])],
        into directory: URL,
        voice: String? = nil
    ) throws -> [Clip] {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        var clips: [Clip] = []
        for (sentence, rates) in plan {
            for rate in rates {
                let wav = directory.appendingPathComponent(
                    "\(sentence.id)-\(rate).wav"
                )
                if !FileManager.default.fileExists(atPath: wav.path) {
                    try synthesize(
                        sentence.spoken,
                        rate: rate,
                        voice: voice,
                        to: wav
                    )
                }
                clips.append(
                    Clip(sentence: sentence, wordsPerMinute: rate, url: wav)
                )
            }
        }
        return clips
    }

    private static func synthesize(
        _ text: String,
        rate: Int,
        voice: String? = nil,
        to wav: URL
    ) throws {
        let aiff = wav.deletingPathExtension().appendingPathExtension("aiff")
        defer { try? FileManager.default.removeItem(at: aiff) }

        var arguments = ["-r", String(rate), "-o", aiff.path]
        if let voice {
            arguments.insert(contentsOf: ["-v", voice], at: 0)
        }
        arguments.append(text)
        try run("/usr/bin/say", arguments)
        // The recorder writes 16 kHz mono float32; match it exactly so the
        // harness measures the decoder rather than a resampler.
        try run(
            "/usr/bin/afconvert",
            ["-f", "WAVE", "-d", "LEF32@16000", "-c", "1", aiff.path, wav.path]
        )
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw FixtureError.synthesisUnavailable(
                "\(tool) could not be launched: \(error.localizedDescription)"
            )
        }
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            throw FixtureError.synthesisUnavailable(
                "\(tool) exited \(process.terminationStatus). \(detail)"
            )
        }
    }

    private static func capture(
        _ tool: String,
        _ arguments: [String]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Reads audio as 16 kHz mono float32, converting if necessary.
    ///
    /// Fixtures are already in that format, but recordings supplied by a person
    /// will not be — phones and interfaces produce 44.1 or 48 kHz stereo, and
    /// silently decoding those at the wrong rate would produce nonsense that
    /// looks like a transcription failure.
    static func samples(at url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else {
            return []
        }

        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            return []
        }
        try file.read(into: sourceBuffer)

        if sourceFormat.sampleRate == targetFormat.sampleRate,
           sourceFormat.channelCount == 1,
           sourceFormat.commonFormat == .pcmFormatFloat32 {
            guard let channel = sourceBuffer.floatChannelData?.pointee else {
                return []
            }
            return Array(
                UnsafeBufferPointer(
                    start: channel,
                    count: Int(sourceBuffer.frameLength)
                )
            )
        }

        guard let converter = AVAudioConverter(
            from: sourceFormat,
            to: targetFormat
        ) else {
            return []
        }
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(
            (Double(sourceBuffer.frameLength) * ratio).rounded(.up) + 4_096
        )
        guard let targetBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: capacity
        ) else {
            return []
        }

        var supplied = false
        var conversionError: NSError?
        converter.convert(to: targetBuffer, error: &conversionError) { _, status in
            if supplied {
                status.pointee = .endOfStream
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return sourceBuffer
        }
        guard conversionError == nil,
              let channel = targetBuffer.floatChannelData?.pointee else {
            return []
        }
        return Array(
            UnsafeBufferPointer(
                start: channel,
                count: Int(targetBuffer.frameLength)
            )
        )
    }

    /// Loads human recordings supplied by the operator: each `name.wav` paired
    /// with a `name.txt` holding what was actually said.
    ///
    /// Synthetic speech is evenly paced and free of breath, hesitation and room
    /// tone, so every number the harness produces from it is optimistic. This
    /// is the escape hatch from that.
    static func corpus(at directory: URL) throws -> [Clip] {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        return contents
            .filter { ["wav", "aiff", "m4a", "mp3", "caf"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { audio in
                let reference = audio
                    .deletingPathExtension()
                    .appendingPathExtension("txt")
                guard let text = try? String(
                    contentsOf: reference,
                    encoding: .utf8
                ) else {
                    return nil
                }
                let name = audio.deletingPathExtension().lastPathComponent
                return Clip(
                    sentence: Sentence(
                        id: name,
                        label: name,
                        phrases: [
                            text.trimmingCharacters(in: .whitespacesAndNewlines)
                        ]
                    ),
                    wordsPerMinute: 0,
                    url: audio
                )
            }
    }

    /// Approximates a laptop microphone across a desk: quiet input with a
    /// light noise floor. Studio-clean audio flatters every configuration and
    /// hides the differences worth measuring.
    static func degraded(
        _ samples: [Float],
        gain: Float,
        noise: Float
    ) -> [Float] {
        guard gain != 1 || noise != 0 else {
            return samples
        }
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        return samples.map { sample in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let jitter = Float(state % 20_001) / 10_000 - 1
            return sample * gain + jitter * noise
        }
    }
}
