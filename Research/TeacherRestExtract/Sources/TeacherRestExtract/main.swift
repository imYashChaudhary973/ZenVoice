import AVFoundation
import CoreML
import FluidAudio
import Foundation

struct CandidateFile: Codable {
    let durationSeconds: Double
    let processingTimeSeconds: Double
    let segments: [CandidateSegment]
}

struct CandidateSegment: Codable {
    let embedding: [Double]
    let endTimeSeconds: Double
    let qualityScore: Double
    let speakerId: String
    let startTimeSeconds: Double
    let speechProbability: Double
    let overlapProbability: Double
    let snrDb: Double
}

struct FrameDump: Codable {
    let backend: String
    let durationSeconds: Double
    let frameSeconds: Double
    let frames: [String]
    let overlapFrameCount: Int
    let speechFrameCount: Int
    let silenceFrameCount: Int
}

private let powerset: [[Int]] = [
    [], [0], [1], [2], [0, 1], [0, 2], [1, 2], [0, 1, 2],
]

@main
struct TeacherRestExtract {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            guard args.count >= 1 else { usage() }
            switch args[0] {
            case "powerset":
                guard args.count == 4 else { usage() }
                try await extractPowerset(
                    audio: URL(fileURLWithPath: args[1]),
                    candidate: URL(fileURLWithPath: args[2]),
                    frames: URL(fileURLWithPath: args[3])
                )
            case "lseend":
                guard args.count == 3 else { usage() }
                try await extractLSEEND(
                    audio: URL(fileURLWithPath: args[1]),
                    frames: URL(fileURLWithPath: args[2])
                )
            default:
                usage()
            }
        } catch {
            FileHandle.standardError.write(Data("teacher-rest-extract: \(error)\n".utf8))
            exit(1)
        }
    }
}

private func usage() -> Never {
    FileHandle.standardError.write(Data("""
    Usage:
      teacher-rest-extract powerset <audio.wav> <candidate.json> <frames.json>
      teacher-rest-extract lseend <audio.wav> <frames.json>

    """.utf8))
    exit(2)
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}

private func loadMono16k(_ url: URL) throws -> ([Float], Double) {
    let samples = try AudioConverter().resampleAudioFile(url)
    return (samples, Double(samples.count) / 16_000)
}

private func rmsFrames(_ samples: [Float], frameSamples: Int) -> [Float] {
    stride(from: 0, to: samples.count, by: frameSamples).map { start in
        let end = min(samples.count, start + frameSamples)
        var sum: Float = 0
        for index in start..<end {
            sum += samples[index] * samples[index]
        }
        return sqrt(sum / Float(max(1, end - start)))
    }
}

private func noiseFloor(_ rms: [Float]) -> Float {
    let sorted = rms.filter { $0 > 0 }.sorted()
    guard !sorted.isEmpty else { return 1e-6 }
    return max(1e-6, sorted[sorted.count / 5])
}

private func softmax(_ logits: [Float]) -> [Float] {
    let maximum = logits.max() ?? 0
    let exp = logits.map { Darwin.exp($0 - maximum) }
    let total = exp.reduce(0, +)
    return exp.map { $0 / max(total, 1e-9) }
}

private func runPowerset(
    model: MLModel,
    samples: [Float],
    duration: Double
) async throws -> ([String], [Float], [Float], Double) {
    let window = 160_000
    let step = 32_000
    var chunks: [(Double, [[Float]])] = []
    var offset = 0
    while offset < samples.count {
        let array = try MLMultiArray(shape: [1, 1, window as NSNumber], dataType: .float32)
        let pointer = array.dataPointer.bindMemory(to: Float.self, capacity: window)
        for index in 0..<window {
            let sampleIndex = offset + index
            pointer[index] = sampleIndex < samples.count ? samples[sampleIndex] : 0
        }
        let input = try MLDictionaryFeatureProvider(
            dictionary: ["audio": MLFeatureValue(multiArray: array)]
        )
        let output = try await model.prediction(from: input)
        let logits = output.featureValue(for: "segments")?.multiArrayValue
            ?? output.featureValue(for: "log_probs")?.multiArrayValue
        guard let logits else {
            throw NSError(
                domain: "TeacherRestExtract",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "segmentation model missing logits"]
            )
        }
        let shape = logits.shape.map(\.intValue)
        let frames = shape.count == 3 ? shape[1] : shape[0]
        let classes = shape.count == 3 ? shape[2] : shape[1]
        var rows: [[Float]] = []
        for frame in 0..<frames {
            var row = Array(repeating: Float(0), count: classes)
            for classIndex in 0..<classes {
                let key: [NSNumber] = shape.count == 3
                    ? [0, frame as NSNumber, classIndex as NSNumber]
                    : [frame as NSNumber, classIndex as NSNumber]
                row[classIndex] = logits[key].floatValue
            }
            rows.append(row)
        }
        chunks.append((Double(offset) / 16_000, rows))
        offset += step
    }
    let frameSeconds = chunks.first.map { 10.0 / Double(max(1, $0.1.count)) } ?? 0.017
    let count = max(1, Int(ceil(duration / frameSeconds)))
    var speech = Array(repeating: Float(0), count: count)
    var overlap = Array(repeating: Float(0), count: count)
    var labels = Array(repeating: "silence", count: count)
    var votes = Array(repeating: 0, count: count)
    for (start, logits) in chunks {
        for frame in logits.indices {
            let probs = softmax(logits[frame])
            var speechP: Float = 0
            var overlapP: Float = 0
            var best = 0
            var bestP: Float = -1
            for classIndex in probs.indices {
                let speakers = classIndex < powerset.count ? powerset[classIndex].count : 0
                if speakers >= 1 { speechP += probs[classIndex] }
                if speakers >= 2 { overlapP += probs[classIndex] }
                if probs[classIndex] > bestP {
                    bestP = probs[classIndex]
                    best = classIndex
                }
            }
            let index = min(
                count - 1,
                max(0, Int(((start + Double(frame) * frameSeconds) / frameSeconds).rounded()))
            )
            speech[index] += speechP
            overlap[index] += overlapP
            votes[index] += 1
            let speakers = best < powerset.count ? powerset[best].count : 0
            if speakers >= 2 {
                labels[index] = "overlap"
            } else if speakers == 1 && labels[index] != "overlap" {
                labels[index] = "speech"
            }
        }
    }
    for index in speech.indices where votes[index] > 0 {
        speech[index] /= Float(votes[index])
        overlap[index] /= Float(votes[index])
        if speech[index] < 0.35 && labels[index] != "overlap" {
            labels[index] = "silence"
        }
    }
    return (labels, speech, overlap, frameSeconds)
}

private func meanRange(_ values: [Float], start: Double, end: Double, step: Double) -> Double {
    let lower = max(0, Int(floor(start / step)))
    let upper = min(values.count, max(lower + 1, Int(ceil(end / step))))
    guard lower < upper else { return 0 }
    return Double(values[lower..<upper].reduce(0, +)) / Double(upper - lower)
}

private func extractPowerset(audio: URL, candidate: URL, frames: URL) async throws {
    let started = Date()
    let (samples, duration) = try loadMono16k(audio)
    let rms = rmsFrames(samples, frameSamples: 160)
    let floor = noiseFloor(rms)
    let config = OfflineDiarizerConfig(
        embeddingExcludeOverlap: false,
        minSegmentDuration: 1.0,
        exclusiveSegments: false
    )
    let manager = OfflineDiarizerManager(config: config)
    let modelRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("models")
    let loaded = try await OfflineDiarizerModels.load(from: modelRoot)
    manager.initialize(models: loaded)
    let result = try await manager.process(audio: samples)
    let (labels, speech, overlap, frameSeconds) = try await runPowerset(
        model: loaded.segmentationModel,
        samples: samples,
        duration: duration
    )
    let segments = result.segments.map { segment in
        let start = Double(segment.startTimeSeconds)
        let end = Double(segment.endTimeSeconds)
        let speechP = meanRange(speech, start: start, end: end, step: frameSeconds)
        let overlapP = meanRange(overlap, start: start, end: end, step: frameSeconds)
        let energy = meanRange(rms, start: start, end: end, step: 0.01)
        let snr = 20 * log10(max(energy, 1e-9) / Double(floor))
        return CandidateSegment(
            embedding: segment.embedding.map(Double.init),
            endTimeSeconds: end,
            qualityScore: Double(segment.qualityScore),
            speakerId: segment.speakerId,
            startTimeSeconds: start,
            speechProbability: speechP,
            overlapProbability: overlapP,
            snrDb: snr
        )
    }
    try writeJSON(
        CandidateFile(
            durationSeconds: duration,
            processingTimeSeconds: Date().timeIntervalSince(started),
            segments: segments
        ),
        to: candidate
    )
    try writeJSON(
        FrameDump(
            backend: "pyannote-powerset",
            durationSeconds: duration,
            frameSeconds: frameSeconds,
            frames: labels,
            overlapFrameCount: labels.filter { $0 == "overlap" }.count,
            speechFrameCount: labels.filter { $0 == "speech" }.count,
            silenceFrameCount: labels.filter { $0 == "silence" }.count
        ),
        to: frames
    )
    print("teacher-rest-extract: powerset wrote \(segments.count) turns")
}

private func extractLSEEND(audio: URL, frames: URL) async throws {
    let diarizer = try await LSEENDDiarizer(variant: .ami)
    let timeline = try diarizer.processComplete(audioFileURL: audio)
    let frameSeconds = 0.1
    let duration = Double(timeline.numFinalizedFrames) * frameSeconds
    let count = max(1, timeline.numFinalizedFrames)
    var active = Array(repeating: 0, count: count)
    for speaker in timeline.speakers.values {
        for segment in speaker.finalizedSegments {
            let lower = max(0, Int(floor(Double(segment.startTime) / frameSeconds)))
            let upper = min(count, Int(ceil(Double(segment.endTime) / frameSeconds)))
            if lower < upper {
                for index in lower..<upper { active[index] += 1 }
            }
        }
    }
    let labels = active.map { count -> String in
        if count >= 2 { return "overlap" }
        if count == 1 { return "speech" }
        return "silence"
    }
    try writeJSON(
        FrameDump(
            backend: "ls-eend-ami",
            durationSeconds: duration,
            frameSeconds: frameSeconds,
            frames: labels,
            overlapFrameCount: labels.filter { $0 == "overlap" }.count,
            speechFrameCount: labels.filter { $0 == "speech" }.count,
            silenceFrameCount: labels.filter { $0 == "silence" }.count
        ),
        to: frames
    )
    print("teacher-rest-extract: lseend wrote \(labels.count) frames")
}
