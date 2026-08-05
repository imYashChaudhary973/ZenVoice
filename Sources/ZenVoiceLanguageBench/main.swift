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

import AVFoundation
import Foundation
import ZenVoiceCore
import ZenVoiceRuntime

private enum BenchmarkError: LocalizedError {
    case invalidArguments(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidArguments(let detail), .unavailable(let detail):
            return detail
        }
    }
}

private enum Suite: String {
    case english
    case multilingual
    case hinglish
}

private struct Options {
    let modelURL: URL
    let suite: Suite
    let cacheURL: URL
    let limit: Int?
    let corpusURL: URL?
    let cleanAudio: Bool
    let preferredVocabulary: [String]

    static func parse(_ arguments: [String]) throws -> Options {
        var modelPath: String?
        var suite: Suite?
        var cachePath = FileManager.default.temporaryDirectory
            .appendingPathComponent("zenvoice-language-bench")
            .path
        var limit: Int?
        var corpusPath: String?
        var cleanAudio = false
        var vocabularyPath: String?
        var index = 1

        while index < arguments.count {
            switch arguments[index] {
            case "--model":
                index += 1
                guard index < arguments.count else {
                    throw BenchmarkError.invalidArguments(
                        "--model requires a file path"
                    )
                }
                modelPath = arguments[index]
            case "--suite":
                index += 1
                guard index < arguments.count,
                      let parsed = Suite(rawValue: arguments[index]) else {
                    throw BenchmarkError.invalidArguments(
                        "--suite must be english, multilingual, or hinglish"
                    )
                }
                suite = parsed
            case "--cache":
                index += 1
                guard index < arguments.count else {
                    throw BenchmarkError.invalidArguments(
                        "--cache requires a directory"
                    )
                }
                cachePath = arguments[index]
            case "--limit":
                index += 1
                guard index < arguments.count,
                      let parsed = Int(arguments[index]),
                      parsed > 0 else {
                    throw BenchmarkError.invalidArguments(
                        "--limit requires a positive integer"
                    )
                }
                limit = parsed
            case "--corpus":
                index += 1
                guard index < arguments.count else {
                    throw BenchmarkError.invalidArguments(
                        "--corpus requires a directory"
                    )
                }
                corpusPath = arguments[index]
            case "--clean":
                cleanAudio = true
            case "--vocabulary":
                index += 1
                guard index < arguments.count else {
                    throw BenchmarkError.invalidArguments(
                        "--vocabulary requires a UTF-8 text file"
                    )
                }
                vocabularyPath = arguments[index]
            case "--help", "-h":
                print(Self.usage)
                exit(0)
            default:
                throw BenchmarkError.invalidArguments(
                    "unknown argument: \(arguments[index])"
                )
            }
            index += 1
        }

        guard let modelPath, let suite else {
            throw BenchmarkError.invalidArguments(Self.usage)
        }
        let modelURL = URL(fileURLWithPath: modelPath)
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw BenchmarkError.invalidArguments(
                "model does not exist: \(modelURL.path)"
            )
        }
        let preferredVocabulary = try vocabularyPath.map {
            try loadVocabulary(at: URL(fileURLWithPath: $0))
        } ?? []
        return Options(
            modelURL: modelURL,
            suite: suite,
            cacheURL: URL(fileURLWithPath: cachePath, isDirectory: true),
            limit: limit,
            corpusURL: corpusPath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            },
            cleanAudio: cleanAudio,
            preferredVocabulary: preferredVocabulary
        )
    }

    static let usage = """
    Usage:
      swift run -c release ZenVoiceLanguageBench \
        --model /path/to/model.bin \
        --suite english|multilingual|hinglish \
        [--corpus /path/to/audio-and-txt-pairs] \
        [--vocabulary /path/to/preferred-terms.txt] \
        [--limit N] [--cache /tmp/zenvoice-language-bench] [--clean]
    """

    private static func loadVocabulary(at url: URL) throws -> [String] {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        let values = try resolved.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey
        ])
        guard values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0,
              fileSize <= 64 * 1_024 else {
            throw BenchmarkError.invalidArguments(
                "vocabulary must be a local UTF-8 file no larger than 64 KB"
            )
        }
        let text = try String(contentsOf: resolved, encoding: .utf8)
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .compactMap { line -> String? in
                let term = line.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                guard !term.isEmpty,
                      term.count <= 120,
                      seen.insert(term.lowercased()).inserted else {
                    return nil
                }
                return term
            }
            .prefix(100)
            .map(\.self)
    }
}

private struct Fixture {
    let id: String
    let language: String
    let voice: String
    let rate: Int
    let spoken: String
    let reference: String
    let profile: LanguageProfile
    let loanwords: [String]
    let source: String
    let segment: Range<Double>?

    init(
        id: String,
        language: String,
        voice: String,
        rate: Int,
        spoken: String,
        reference: String,
        profile: LanguageProfile,
        loanwords: [String],
        source: String,
        segment: Range<Double>? = nil
    ) {
        self.id = id
        self.language = language
        self.voice = voice
        self.rate = rate
        self.spoken = spoken
        self.reference = reference
        self.profile = profile
        self.loanwords = loanwords
        self.source = source
        self.segment = segment
    }

    var cacheName: String {
        let safeVoice = voice
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
        return "\(id)-\(safeVoice)-\(rate)"
    }
}

private struct Measurement {
    let fixture: Fixture
    let hypothesis: String
    let audioSeconds: Double
    let latencySeconds: Double
    let wordError: EditResult
    let characterError: EditResult
    let loanwords: LoanwordResult
    let hasUnexpectedScript: Bool

    var realtimeFactor: Double {
        audioSeconds > 0 ? latencySeconds / audioSeconds : 0
    }
}

private struct EditResult {
    let distance: Int
    let referenceUnits: Int

    var rate: Double {
        referenceUnits > 0
            ? Double(distance) / Double(referenceUnits)
            : 0
    }

    static let zero = EditResult(distance: 0, referenceUnits: 0)

    static func + (lhs: EditResult, rhs: EditResult) -> EditResult {
        EditResult(
            distance: lhs.distance + rhs.distance,
            referenceUnits: lhs.referenceUnits + rhs.referenceUnits
        )
    }
}

private struct LoanwordResult {
    var preserved: Int
    var total: Int
    var lost: [String]

    static let zero = LoanwordResult(preserved: 0, total: 0, lost: [])

    static func + (
        lhs: LoanwordResult,
        rhs: LoanwordResult
    ) -> LoanwordResult {
        LoanwordResult(
            preserved: lhs.preserved + rhs.preserved,
            total: lhs.total + rhs.total,
            lost: lhs.lost + rhs.lost
        )
    }
}

private struct Cohort {
    var wordError = EditResult.zero
    var characterError = EditResult.zero
    var loanwords = LoanwordResult.zero
    var latencies: [Double] = []
    var realtimeFactors: [Double] = []
    var audioSeconds: Double = 0
    var processingSeconds: Double = 0
    var clipCount = 0
    var scriptViolations = 0

    mutating func add(_ measurement: Measurement) {
        wordError = wordError + measurement.wordError
        characterError = characterError + measurement.characterError
        loanwords = loanwords + measurement.loanwords
        latencies.append(measurement.latencySeconds)
        realtimeFactors.append(measurement.realtimeFactor)
        audioSeconds += measurement.audioSeconds
        processingSeconds += measurement.latencySeconds
        clipCount += 1
        if measurement.hasUnexpectedScript {
            scriptViolations += 1
        }
    }
}

private enum FixtureCatalog {
    static func fixtures(for suite: Suite) -> [Fixture] {
        switch suite {
        case .english:
            return english()
        case .multilingual:
            return multilingual()
        case .hinglish:
            return hinglish()
        }
    }

    private static func english() -> [Fixture] {
        let examples = [
            (
                "eng-review",
                "Please review the pull request before merging the release branch."
            ),
            (
                "eng-auth",
                "The authentication service validates every token before querying Postgres."
            )
        ]
        let voices = ["Samantha", "Daniel", "Aman", "Tara"]
        return voices.flatMap { voice in
            [170, 280].flatMap { rate in
                examples.map { id, text in
                    Fixture(
                        id: id,
                        language: "English",
                        voice: voice,
                        rate: rate,
                        spoken: text,
                        reference: text,
                        profile: .english,
                        loanwords: [],
                        source: "synthetic"
                    )
                }
            }
        }
    }

    private struct LanguageExample {
        let id: String
        let language: String
        let code: String
        let voice: String
        let texts: [String]
    }

    private static func multilingual() -> [Fixture] {
        let examples = [
            LanguageExample(
                id: "hin",
                language: "Hindi",
                code: "hi",
                voice: "Lekha",
                texts: [
                    "कृपया रिलीज़ से पहले पुल रिक्वेस्ट की समीक्षा करें।",
                    "सर्वर हर अनुरोध से पहले सुरक्षा टोकन की जाँच करता है।"
                ]
            ),
            LanguageExample(
                id: "spa",
                language: "Spanish",
                code: "es",
                voice: "Mónica",
                texts: [
                    "Por favor revisa la solicitud antes de publicar la versión.",
                    "El servidor valida cada token antes de consultar la base de datos."
                ]
            ),
            LanguageExample(
                id: "fra",
                language: "French",
                code: "fr",
                voice: "Jacques",
                texts: [
                    "Veuillez vérifier la demande avant de publier la version.",
                    "Le serveur valide chaque jeton avant de consulter la base de données."
                ]
            ),
            LanguageExample(
                id: "deu",
                language: "German",
                code: "de",
                voice: "Anna",
                texts: [
                    "Bitte prüfe die Anfrage bevor du die neue Version veröffentlichst.",
                    "Der Server prüft jedes Token bevor er die Datenbank abfragt."
                ]
            ),
            LanguageExample(
                id: "tam",
                language: "Tamil",
                code: "ta",
                voice: "Vani",
                texts: [
                    "புதிய பதிப்பை வெளியிடும் முன் கோரிக்கையை சரிபார்க்கவும்.",
                    "தரவுத்தளத்தை அணுகும் முன் சேவையகம் ஒவ்வொரு குறியீட்டையும் சரிபார்க்கிறது."
                ]
            ),
            LanguageExample(
                id: "ara",
                language: "Arabic",
                code: "ar",
                voice: "Majed",
                texts: [
                    "يرجى مراجعة الطلب قبل نشر الإصدار الجديد.",
                    "يتحقق الخادم من كل رمز قبل الاستعلام عن قاعدة البيانات."
                ]
            ),
            LanguageExample(
                id: "jpn",
                language: "Japanese",
                code: "ja",
                voice: "Kyoko",
                texts: [
                    "新しいバージョンを公開する前にリクエストを確認してください。",
                    "サーバーはデータベースを照会する前に各トークンを検証します。"
                ]
            ),
            LanguageExample(
                id: "zho",
                language: "Mandarin",
                code: "zh",
                voice: "Tingting",
                texts: [
                    "发布新版本之前请检查合并请求。",
                    "服务器查询数据库之前会验证每个令牌。"
                ]
            )
        ]

        return examples.flatMap { example in
            [170, 260].flatMap { rate in
                example.texts.enumerated().map { index, text in
                    Fixture(
                        id: "\(example.id)-\(index + 1)",
                        language: example.language,
                        voice: example.voice,
                        rate: rate,
                        spoken: text,
                        reference: text,
                        profile: LanguageProfile(
                            inputLanguageCode: example.code,
                            outputMode: .spokenLanguage
                        ),
                        loanwords: [],
                        source: "synthetic"
                    )
                }
            }
        }
    }

    private struct HinglishExample {
        let id: String
        let spoken: String
        let reference: String
        let loanwords: [String]
    }

    private static func hinglish() -> [Fixture] {
        let examples = [
            HinglishExample(
                id: "hin-project",
                spoken: "प्रोजेक्ट का स्टेटस क्या है, मैंने ईमेल भेज दिया।",
                reference: "Project ka status kya hai, maine email bhej diya.",
                loanwords: ["project", "status", "email"]
            ),
            HinglishExample(
                id: "hin-server",
                spoken: "सर्वर डाउन है, थोड़ा सा वेट करो।",
                reference: "Server down hai, thoda sa wait karo.",
                loanwords: ["server", "down", "wait"]
            ),
            HinglishExample(
                id: "hin-review",
                spoken: "पुल रिक्वेस्ट रिव्यू करके कंप्यूटर पर टेस्ट चलाओ।",
                reference: "Pull request review karke computer par test chalao.",
                loanwords: ["pull request", "review", "computer", "test"]
            ),
            HinglishExample(
                id: "hin-deploy",
                spoken: "डिप्लॉयमेंट से पहले बिल्ड और यूनिट टेस्ट चेक कर लो।",
                reference: "Deployment se pehle build aur unit test check kar lo.",
                loanwords: ["deployment", "build", "unit test", "check"]
            ),
            HinglishExample(
                id: "hin-database",
                spoken: "डेटाबेस माइग्रेशन के बाद बैकअप वेरिफाई करना।",
                reference: "Database migration ke baad backup verify karna.",
                loanwords: ["database", "migration", "backup", "verify"]
            ),
            HinglishExample(
                id: "hin-meeting",
                spoken: "मीटिंग चार बजे शेड्यूल करो और कैलेंडर अपडेट कर दो।",
                reference: "Meeting chaar baje schedule karo aur calendar update kar do.",
                loanwords: ["meeting", "schedule", "calendar", "update"]
            )
        ]

        return [150, 220, 300].flatMap { rate in
            examples.map { example in
                Fixture(
                    id: example.id,
                    language: "Hinglish",
                    voice: "Lekha",
                    rate: rate,
                    spoken: example.spoken,
                    reference: example.reference,
                    profile: .hinglish,
                    loanwords: example.loanwords,
                    source: "synthetic"
                )
            }
        }
    }
}

private enum Audio {
    static func installedVoices() throws -> String {
        try capture("/usr/bin/say", ["-v", "?"])
    }

    static func render(
        _ fixture: Fixture,
        into directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let wav = directory
            .appendingPathComponent(fixture.cacheName)
            .appendingPathExtension("wav")
        guard !FileManager.default.fileExists(atPath: wav.path) else {
            return wav
        }
        let aiff = wav.deletingPathExtension().appendingPathExtension("aiff")
        defer { try? FileManager.default.removeItem(at: aiff) }
        try run(
            "/usr/bin/say",
            [
                "-v", fixture.voice,
                "-r", String(fixture.rate),
                "-o", aiff.path,
                fixture.spoken,
            ]
        )
        try run(
            "/usr/bin/afconvert",
            [
                "-f", "WAVE",
                "-d", "LEF32@16000",
                "-c", "1",
                aiff.path,
                wav.path,
            ]
        )
        return wav
    }

    static func samples(
        at url: URL,
        segment: Range<Double>? = nil
    ) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let startFrame = segment.map {
            AVAudioFramePosition($0.lowerBound * sourceFormat.sampleRate)
        } ?? 0
        let availableFrames = max(0, file.length - startFrame)
        let requestedFrames = segment.map {
            AVAudioFramePosition(
                ($0.upperBound - $0.lowerBound) * sourceFormat.sampleRate
            )
        } ?? availableFrames
        let sourceFrames = min(availableFrames, requestedFrames)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ),
        let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(sourceFrames)
        ) else {
            return []
        }
        file.framePosition = startFrame
        try file.read(
            into: sourceBuffer,
            frameCount: AVAudioFrameCount(sourceFrames)
        )

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

    static func degraded(_ samples: [Float]) -> [Float] {
        var state: UInt64 = 0x2545_F491_4F6C_DD1D
        return samples.map { sample in
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            let jitter = Float(state % 20_001) / 10_000 - 1
            return sample * 0.35 + jitter * 0.004
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()
        try process.run()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: errorData, encoding: .utf8) ?? ""
            throw BenchmarkError.unavailable(
                "\(tool) exited \(process.terminationStatus): \(detail)"
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
}

private enum Metrics {
    static func words(_ text: String) -> [String] {
        normalizedCharacters(text)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
    }

    static func characters(_ text: String) -> [Character] {
        Array(normalizedCharacters(text).filter { !$0.isWhitespace })
    }

    static func edit<T: Equatable>(
        reference: [T],
        hypothesis: [T]
    ) -> EditResult {
        guard !reference.isEmpty else {
            return EditResult(
                distance: hypothesis.count,
                referenceUnits: 0
            )
        }
        var previous = Array(0...hypothesis.count)
        for (row, referenceUnit) in reference.enumerated() {
            var current = [row + 1]
            for (column, hypothesisUnit) in hypothesis.enumerated() {
                current.append(
                    min(
                        previous[column + 1] + 1,
                        current[column] + 1,
                        previous[column]
                            + (referenceUnit == hypothesisUnit ? 0 : 1)
                    )
                )
            }
            previous = current
        }
        return EditResult(
            distance: previous[hypothesis.count],
            referenceUnits: reference.count
        )
    }

    static func loanwords(
        expected: [String],
        hypothesis: String
    ) -> LoanwordResult {
        let haystack = " " + words(hypothesis).joined(separator: " ") + " "
        var result = LoanwordResult.zero
        for term in expected {
            let needle = " " + words(term).joined(separator: " ") + " "
            result.total += 1
            if haystack.contains(needle) {
                result.preserved += 1
            } else {
                result.lost.append(term)
            }
        }
        return result
    }

    static func percentile(_ values: [Double], _ percentile: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = Int(
            (Double(sorted.count - 1) * percentile).rounded(.up)
        )
        return sorted[min(position, sorted.count - 1)]
    }

    static func containsNonLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            $0.properties.isAlphabetic
                && !$0.isASCII
                && !($0.properties.name ?? "").contains("LATIN")
        }
    }

    private static func normalizedCharacters(_ text: String) -> String {
        String(
            text.lowercased().map { character in
                character.isLetter || character.isNumber
                    ? character
                    : " "
            }
        )
        .split(whereSeparator: \.isWhitespace)
        .joined(separator: " ")
    }
}

private func corpusFixtures(
    at directory: URL,
    limit: Int?
) throws -> [Fixture] {
    let transcriptDirectory = directory.appendingPathComponent("transcripts")
    let segmentsURL = transcriptDirectory.appendingPathComponent("segments")
    let textURL = transcriptDirectory.appendingPathComponent("text")
    let speakersURL = transcriptDirectory.appendingPathComponent("utt2spk")
    if FileManager.default.fileExists(atPath: segmentsURL.path),
       FileManager.default.fileExists(atPath: textURL.path),
       FileManager.default.fileExists(atPath: speakersURL.path) {
        return try kaldiCorpusFixtures(
            at: directory,
            segmentsURL: segmentsURL,
            textURL: textURL,
            speakersURL: speakersURL,
            limit: limit
        )
    }

    let contents = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    )
    let audioExtensions = Set(["wav", "aiff", "m4a", "mp3", "caf", "flac"])
    let fixtures = contents
        .filter { audioExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { audio -> Fixture? in
            let transcriptURL = audio
                .deletingPathExtension()
                .appendingPathExtension("txt")
            guard let transcript = try? String(
                contentsOf: transcriptURL,
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            !transcript.isEmpty else {
                return nil
            }
            let latinTerms = Metrics.words(transcript).filter { token in
                token.count >= 3
                    && token.allSatisfy { $0.isASCII && $0.isLetter }
            }
            return Fixture(
                id: audio.deletingPathExtension().lastPathComponent,
                language: "Hinglish real",
                voice: "public corpus",
                rate: 0,
                spoken: "",
                reference: transcript,
                profile: .hinglish,
                loanwords: latinTerms,
                source: audio.path
            )
        }
    return limit.map { Array(fixtures.prefix($0)) } ?? fixtures
}

private func kaldiCorpusFixtures(
    at directory: URL,
    segmentsURL: URL,
    textURL: URL,
    speakersURL: URL,
    limit: Int?
) throws -> [Fixture] {
    func keyedLines(at url: URL) throws -> [String: String] {
        var result: [String: String] = [:]
        for line in try String(contentsOf: url, encoding: .utf8)
            .split(whereSeparator: \.isNewline) {
            let pieces = line.split(
                maxSplits: 1,
                whereSeparator: \.isWhitespace
            )
            if pieces.count == 2 {
                result[String(pieces[0])] = String(pieces[1])
            }
        }
        return result
    }

    let transcripts = try keyedLines(at: textURL)
    let speakers = try keyedLines(at: speakersURL)
    var candidates: [Fixture] = []
    for line in try String(contentsOf: segmentsURL, encoding: .utf8)
        .split(whereSeparator: \.isNewline) {
        let pieces = line.split(whereSeparator: \.isWhitespace)
        guard pieces.count == 4,
              let start = Double(pieces[2]),
              let end = Double(pieces[3]),
              start >= 0,
              end > start,
              end - start >= 2,
              end - start <= 20 else {
            continue
        }
        let utteranceID = String(pieces[0])
        let recordingID = String(pieces[1])
        guard let transcript = transcripts[utteranceID],
              let speaker = speakers[utteranceID] else {
            continue
        }
        let latinTerms = Metrics.words(transcript).filter { token in
            token.count >= 3
                && token.allSatisfy { $0.isASCII && $0.isLetter }
        }
        guard !latinTerms.isEmpty else {
            continue
        }
        let audioURL = directory
            .appendingPathComponent(recordingID)
            .appendingPathExtension("wav")
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let corpusRoot = directory
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path + "/"
        guard audioURL.path.hasPrefix(corpusRoot),
              FileManager.default.fileExists(atPath: audioURL.path) else {
            continue
        }
        candidates.append(
            Fixture(
                id: utteranceID,
                language: "Hinglish real",
                voice: speaker,
                rate: 0,
                spoken: "",
                reference: transcript,
                profile: .hinglish,
                loanwords: latinTerms,
                source: audioURL.path,
                segment: start..<end
            )
        )
    }

    candidates.sort {
        ($0.voice, $0.id) < ($1.voice, $1.id)
    }
    let targetCount = limit ?? candidates.count
    var selected: [Fixture] = []
    var selectedIDs = Set<String>()
    var seenSpeakers = Set<String>()
    for fixture in candidates where !seenSpeakers.contains(fixture.voice) {
        selected.append(fixture)
        selectedIDs.insert(fixture.id)
        seenSpeakers.insert(fixture.voice)
        if selected.count == targetCount {
            return selected
        }
    }
    for fixture in candidates where !selectedIDs.contains(fixture.id) {
        selected.append(fixture)
        if selected.count == targetCount {
            break
        }
    }
    return selected
}

private func formattedPercent(_ result: EditResult) -> String {
    let value = result.referenceUnits > 0
        ? String(format: "%.1f%%", result.rate * 100)
        : "n/a"
    return String(repeating: " ", count: max(0, 9 - value.count)) + value
}

private func report(
    modelID: String,
    suite: Suite,
    measurements: [Measurement],
    modelLoadSeconds: Double,
    cleanAudio: Bool
) {
    print()
    print("ZenVoice language benchmark")
    print("model: \(modelID)")
    print("suite: \(suite.rawValue)")
    print("input: \(cleanAudio ? "studio clean" : "gain 0.35 + noise 0.004")")
    print(String(format: "model warm-up/load: %.3f s", modelLoadSeconds))
    print()
    print(
        "language / voice                  clips      WER      CER"
            + "   p50 ms   p95 ms     RTF  loanwords  script"
    )
    print(String(repeating: "-", count: 94))

    let grouped = Dictionary(grouping: measurements) {
        "\($0.fixture.language) / \($0.fixture.voice)"
    }
    for key in grouped.keys.sorted() {
        var cohort = Cohort()
        for measurement in grouped[key] ?? [] {
            cohort.add(measurement)
        }
        let loanwordSummary = cohort.loanwords.total > 0
            ? "\(cohort.loanwords.preserved)/\(cohort.loanwords.total)"
            : "-"
        print(
            key.padding(toLength: 34, withPad: " ", startingAt: 0)
                + String(format: "%5d", cohort.clipCount)
                + formattedPercent(cohort.wordError)
                + formattedPercent(cohort.characterError)
                + String(
                    format: "%9.0f",
                    Metrics.percentile(cohort.latencies, 0.50) * 1_000
                )
                + String(
                    format: "%9.0f",
                    Metrics.percentile(cohort.latencies, 0.95) * 1_000
                )
                + String(
                    format: "%8.3f",
                    cohort.audioSeconds > 0
                        ? cohort.processingSeconds / cohort.audioSeconds
                        : 0
                )
                + "  \(loanwordSummary)"
                + String(format: "%8d", cohort.scriptViolations)
        )
    }

    let rateGroups = Dictionary(
        grouping: measurements.filter { $0.fixture.rate > 0 },
        by: { $0.fixture.rate }
    )
    if rateGroups.count > 1 {
        print()
        print("by speaking rate")
        print(
            "rate                 clips      WER      CER"
                + "   p50 ms   p95 ms     RTF  loanwords  script"
        )
        print(String(repeating: "-", count: 82))
        for rate in rateGroups.keys.sorted() {
            var cohort = Cohort()
            for measurement in rateGroups[rate] ?? [] {
                cohort.add(measurement)
            }
            let loanwordSummary = cohort.loanwords.total > 0
                ? "\(cohort.loanwords.preserved)/\(cohort.loanwords.total)"
                : "-"
            print(
                "\(rate) wpm".padding(
                    toLength: 21,
                    withPad: " ",
                    startingAt: 0
                    )
                    + String(format: "%5d", cohort.clipCount)
                    + formattedPercent(cohort.wordError)
                    + formattedPercent(cohort.characterError)
                    + String(
                        format: "%9.0f",
                        Metrics.percentile(cohort.latencies, 0.50) * 1_000
                    )
                    + String(
                        format: "%9.0f",
                        Metrics.percentile(cohort.latencies, 0.95) * 1_000
                    )
                    + String(
                        format: "%8.3f",
                        cohort.audioSeconds > 0
                            ? cohort.processingSeconds / cohort.audioSeconds
                            : 0
                    )
                    + "  \(loanwordSummary)"
                    + String(format: "%8d", cohort.scriptViolations)
            )
        }
    }

    var overall = Cohort()
    for measurement in measurements {
        overall.add(measurement)
    }
    print(String(repeating: "-", count: 94))
    let overallLoanwords = overall.loanwords.total > 0
        ? "\(overall.loanwords.preserved)/\(overall.loanwords.total)"
        : "-"
    print(
        "OVERALL".padding(toLength: 34, withPad: " ", startingAt: 0)
            + String(format: "%5d", overall.clipCount)
            + formattedPercent(overall.wordError)
            + formattedPercent(overall.characterError)
            + String(
                format: "%9.0f",
                Metrics.percentile(overall.latencies, 0.50) * 1_000
            )
            + String(
                format: "%9.0f",
                Metrics.percentile(overall.latencies, 0.95) * 1_000
            )
            + String(
                format: "%8.3f",
                overall.audioSeconds > 0
                    ? overall.processingSeconds / overall.audioSeconds
                    : 0
            )
            + "  \(overallLoanwords)"
            + String(format: "%8d", overall.scriptViolations)
    )
    print(
        String(
            format: "audio %.1f s, decode %.1f s, %.0fx real time",
            overall.audioSeconds,
            overall.processingSeconds,
            overall.processingSeconds > 0
                ? overall.audioSeconds / overall.processingSeconds
                : 0
        )
    )

    let failures = measurements.filter {
        $0.hypothesis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    if !failures.isEmpty {
        print("empty transcripts: \(failures.map(\.fixture.id).joined(separator: ", "))")
    }
    let lost = overall.loanwords.lost
    if !lost.isEmpty {
        print("lost loanwords: \(lost.joined(separator: ", "))")
    }
}

private func run() throws {
    let options = try Options.parse(CommandLine.arguments)
    if let catalogModel = VerifiedModelCatalog.model(
        filename: options.modelURL.lastPathComponent
    ) {
        guard try VerifiedModelCatalog.verify(
            options.modelURL,
            for: catalogModel
        ) else {
            throw BenchmarkError.invalidArguments(
                "model size or SHA-256 does not match the verified catalogue"
            )
        }
    } else {
        throw BenchmarkError.invalidArguments(
            "model is not in the verified ZenVoice catalogue"
        )
    }

    let voices = try Audio.installedVoices()
    var fixtures = FixtureCatalog.fixtures(for: options.suite)
    fixtures = fixtures.filter { voices.contains($0.voice) }
    if options.suite == .hinglish, let corpusURL = options.corpusURL {
        fixtures = try corpusFixtures(at: corpusURL, limit: options.limit)
    } else if let limit = options.limit {
        fixtures = Array(fixtures.prefix(limit))
    }
    guard !fixtures.isEmpty else {
        throw BenchmarkError.unavailable("no benchmark fixtures are available")
    }

    let configuration = ZenVoiceConfiguration(
        modelURL: options.modelURL,
        languageProfile: fixtures[0].profile
    )
    let vocabularyPrompt = NextDictationContext.combined(
        context: "",
        preferredVocabulary: options.preferredVocabulary
    )
    if !options.preferredVocabulary.isEmpty {
        print(
            "preferred vocabulary: "
                + "\(options.preferredVocabulary.count) local terms"
        )
    }
    let transcriber = WhisperTranscriber(
        configuration: configuration,
        isReproducible: true
    )
    let warmupStart = Date()
    do {
        _ = try transcriber.transcribe(
            samples: Array(repeating: 0, count: 16_000),
            languageProfile: fixtures[0].profile
        )
    } catch WhisperTranscriber.TranscriptionError.noSpeech {
        // Reaching the no-speech decision means the model is loaded.
    }
    let modelLoadSeconds = Date().timeIntervalSince(warmupStart)

    var measurements: [Measurement] = []
    for fixture in fixtures {
        let audioURL: URL
        if fixture.source == "synthetic" {
            audioURL = try Audio.render(fixture, into: options.cacheURL)
        } else {
            audioURL = URL(fileURLWithPath: fixture.source)
        }
        let loaded = try Audio.samples(
            at: audioURL,
            segment: fixture.segment
        )
        guard !loaded.isEmpty else {
            throw BenchmarkError.unavailable(
                "could not read audio: \(audioURL.path)"
            )
        }
        let samples = options.cleanAudio ? loaded : Audio.degraded(loaded)
        let result = try transcriber.transcribe(
            samples: samples,
            languageProfile: fixture.profile,
            initialPrompt: vocabularyPrompt
        )
        let hypothesis = result.finalTranscript
        let isMixedScriptReference =
            fixture.source != "synthetic" && fixture.profile == .hinglish
        let measurement = Measurement(
            fixture: fixture,
            hypothesis: hypothesis,
            audioSeconds: Double(samples.count) / 16_000,
            latencySeconds: result.processingDurationSeconds,
            wordError:
                isMixedScriptReference
                ? .zero
                : Metrics.edit(
                    reference: Metrics.words(fixture.reference),
                    hypothesis: Metrics.words(hypothesis)
                ),
            characterError:
                isMixedScriptReference
                ? .zero
                : Metrics.edit(
                    reference: Metrics.characters(fixture.reference),
                    hypothesis: Metrics.characters(hypothesis)
                ),
            loanwords: Metrics.loanwords(
                expected: fixture.loanwords,
                hypothesis: hypothesis
            ),
            hasUnexpectedScript:
                fixture.profile == .hinglish
                && Metrics.containsNonLatinLetter(hypothesis)
        )
        measurements.append(measurement)
        let label = "\(fixture.id)/\(fixture.voice)@\(fixture.rate)"
        print(
            label.padding(toLength: 34, withPad: " ", startingAt: 0)
                +
            String(
                format: "%6.0f ms  RTF %.3f  %@",
                measurement.latencySeconds * 1_000,
                measurement.realtimeFactor,
                hypothesis
            )
        )
    }
    report(
        modelID: configuration.modelID,
        suite: options.suite,
        measurements: measurements,
        modelLoadSeconds: modelLoadSeconds,
        cleanAudio: options.cleanAudio
    )
}

do {
    try run()
} catch {
    FileHandle.standardError.write(
        Data("ZenVoiceLanguageBench failed: \(error.localizedDescription)\n".utf8)
    )
    exit(1)
}
