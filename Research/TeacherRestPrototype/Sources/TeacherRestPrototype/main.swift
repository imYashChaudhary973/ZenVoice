import Foundation

private enum Role: UInt8, Codable {
    case silence = 0
    case teacher = 1
    case others = 2
    case unknown = 3
}

private struct Gate: Decodable {
    struct Metrics: Decodable {
        let teacherPrecisionMinimum: Double
        let teacherRecallMinimum: Double
        let mainSuggestionAccuracyMinimum: Double
        let studentQuestionAttributionMinimum: Double
        let silenceFalsePositiveMaximum: Double
        let unsafeOverlapAssignmentMaximum: Double
        let minimumRealTimeFactor: Double
        let maximumPeakMemoryBytes: Int64
        let preferredMaximumModelBytes: Int64
    }
    struct Dominance: Decodable {
        let minimumTopShare: Double
        let minimumTopToSecondRatio: Double
    }
    struct Filtering: Decodable {
        let minimumDurationSeconds: Double
        let minimumQuality: Double
    }
    struct Selection: Decodable {
        let teacherSimilarityGrid: [Double]
        let unknownWidthGrid: [Double]
    }
    struct Classroom: Decodable {
        let required: Bool
        let consentRequired: Bool
        let minimumEvaluationLectures: Int
        let minimumEvaluationTeachers: Int
        let minimumEvaluationRooms: Int
        let minimumEvaluationHours: Double
        let minimumEvaluationStudentQuestions: Int
        let teacherDisjointCalibrationAndEvaluation: Bool
        let roomDisjointCalibrationAndEvaluation: Bool
        let requiredDurationsMinutes: [Int]
    }
    struct LongForm: Decodable {
        let durationsMinutes: [Int]
        let mustCompleteLocally: Bool
        let mustLeaveNoTemporaryArtifacts: Bool
    }
    struct Privacy: Decodable {
        let networkRequestsAllowed: Int
        let crossLectureEmbeddingComparisonsAllowed: Int
        let persistentVoiceprintsAllowed: Int
        let embeddingCacheEncryptedIfPersisted: Bool
        let deleteMustRemoveTurnsEmbeddingsAndCaches: Bool
    }
    let metrics: Metrics
    let dominanceSuggestion: Dominance
    let turnFiltering: Filtering
    let thresholdSelection: Selection
    let classroom: Classroom
    let longForm: LongForm
    let privacy: Privacy
}

private struct CandidateFile: Codable {
    let durationSeconds: Double
    let processingTimeSeconds: Double
    let segments: [CandidateSegment]
}

private struct CandidateSegment: Codable {
    let embedding: [Double]
    let endTimeSeconds: Double
    let qualityScore: Double
    let speakerId: String
    let startTimeSeconds: Double
    let speechProbability: Double?
    let overlapProbability: Double?
    let snrDb: Double?

    var duration: Double { endTimeSeconds - startTimeSeconds }
    var speech: Double { speechProbability ?? qualityScore }
    var overlapP: Double { overlapProbability ?? 0 }
    var snr: Double { snrDb ?? 40 }

    init(
        embedding: [Double],
        endTimeSeconds: Double,
        qualityScore: Double,
        speakerId: String,
        startTimeSeconds: Double,
        speechProbability: Double? = nil,
        overlapProbability: Double? = nil,
        snrDb: Double? = nil
    ) {
        self.embedding = embedding
        self.endTimeSeconds = endTimeSeconds
        self.qualityScore = qualityScore
        self.speakerId = speakerId
        self.startTimeSeconds = startTimeSeconds
        self.speechProbability = speechProbability
        self.overlapProbability = overlapProbability
        self.snrDb = snrDb
    }
}

private struct ReferenceSegment {
    let start: Double
    let end: Double
    let speaker: String
}

private struct Metadata: Decodable {
    struct Question: Decodable {
        let start: Double
        let end: Double
        let speaker: String
        let referenceRole: String
        let text: String
    }
    let meeting: String
    let teacherSpeaker: String
    let questions: [Question]
}

private struct Manifest: Decodable {
    struct Entry: Decodable {
        let id: String
        let split: String
        let candidatePath: String
        let referencePath: String
        let metadataPath: String
        let peakMemoryBytes: Int64?
        let modelBytes: Int64?
        let source: String?
    }
    let entries: [Entry]
}

private struct CorpusStatus: Decodable {
    struct Classroom: Decodable {
        let ready: Bool
        let manifest: String?
        let evaluationLectures: Int
        let evaluationTeachers: Int
        let evaluationRooms: Int
        let evaluationHours: Double
        let evaluationStudentQuestions: Int
        let teacherDisjoint: Bool
        let roomDisjoint: Bool
    }
    let classroom: Classroom
}

private struct ClassroomRecord: Codable {
    let lectureID: String
    let split: String
    let teacherID: String
    let roomID: String
    let audioPath: String
    let rttmPath: String
    let questionsPath: String
    let candidatePath: String
    let durationSeconds: Double
    let studentQuestionCount: Int
    let teacherConsent: Bool
    let participantConsent: Bool
}

private struct ClassroomQuestion: Codable {
    let start: Double
    let end: Double
    let text: String
    let referenceRole: String
}

private struct GateEvidence: Decodable {
    struct Run: Decodable {
        let minutes: Int
        let realTimeFactor: Double
        let maximumResidentBytes: Int64
        let peakFootprintBytes: Int64
        let networkDeniedSandbox: Bool
    }
    let modelBytes: Int64
    let runs: [Run]
    let networkRequestsObserved: Int
    let temporaryArtifactsRemaining: Int
    let embeddingArtifactsRemaining: Int
    let modelCacheArtifactsRemaining: Int
    let crossLectureEmbeddingComparisons: Int
    let persistentVoiceprints: Int
    let persistedEmbeddingArtifactsEncrypted: Bool
    let deleteBehaviorVerified: Bool
}

private struct Thresholds: Codable {
    let teacherSimilarity: Double
    let othersSimilarity: Double
    let selectionStatus: String
    let calibrationMetrics: AggregateMetrics
}

private struct Counts: Codable {
    var teacherTruePositive = 0
    var teacherFalsePositive = 0
    var teacherFalseNegative = 0
    var othersCorrect = 0
    var othersTotal = 0
    var unknownSpeechFrames = 0
    var speechFrames = 0
    var silenceFalsePositive = 0
    var silenceFrames = 0
    var unsafeOverlapFrames = 0
    var overlapFrames = 0
    var studentQuestionsCorrect = 0
    var studentQuestionsTotal = 0
    var suggestionsCorrect = 0
    var suggestionsTotal = 0

    mutating func add(_ other: Counts) {
        teacherTruePositive += other.teacherTruePositive
        teacherFalsePositive += other.teacherFalsePositive
        teacherFalseNegative += other.teacherFalseNegative
        othersCorrect += other.othersCorrect
        othersTotal += other.othersTotal
        unknownSpeechFrames += other.unknownSpeechFrames
        speechFrames += other.speechFrames
        silenceFalsePositive += other.silenceFalsePositive
        silenceFrames += other.silenceFrames
        unsafeOverlapFrames += other.unsafeOverlapFrames
        overlapFrames += other.overlapFrames
        studentQuestionsCorrect += other.studentQuestionsCorrect
        studentQuestionsTotal += other.studentQuestionsTotal
        suggestionsCorrect += other.suggestionsCorrect
        suggestionsTotal += other.suggestionsTotal
    }
}

private struct AggregateMetrics: Codable {
    let teacherPrecision: Double
    let teacherRecall: Double
    let mainSuggestionAccuracy: Double
    let studentQuestionAttribution: Double
    let silenceFalsePositiveRate: Double
    let unsafeOverlapAssignmentRate: Double
    let unknownSpeechRate: Double
    let minimumRealTimeFactor: Double
    let maximumPeakMemoryBytes: Int64
    let maximumModelBytes: Int64
    let counts: Counts
}

private struct FileResult: Codable {
    let id: String
    let teacherPrecision: Double
    let teacherRecall: Double
    let mainSuggestionCorrect: Bool
    let studentQuestionAttribution: Double
    let silenceFalsePositiveRate: Double
    let unsafeOverlapAssignmentRate: Double
    let unknownSpeechRate: Double
    let realTimeFactor: Double
    let suggestedCluster: String?
    let confirmedCluster: String?
    let teacherSimilarity: Double
    let othersSimilarity: Double
    let counts: Counts
}

private struct EvaluationReport: Codable {
    struct Check: Codable {
        let name: String
        let passed: Bool
        let actual: Double
        let required: Double
    }
    let decision: String
    let thresholds: Thresholds
    let aggregate: AggregateMetrics
    let classroomAggregate: AggregateMetrics?
    let files: [FileResult]
    let checks: [Check]
    let classroomReady: Bool
    let missingPrerequisites: [String]
}

private struct Dataset {
    let entry: Manifest.Entry
    let candidate: CandidateFile
    let reference: [ReferenceSegment]
    let metadata: Metadata
}

private func ratio(_ numerator: Int, _ denominator: Int, empty: Double = 0) -> Double {
    denominator == 0 ? empty : Double(numerator) / Double(denominator)
}

private func normalize(_ vector: [Double]) -> [Double]? {
    let norm = sqrt(vector.reduce(0) { $0 + $1 * $1 })
    guard norm.isFinite, norm > 1e-9 else { return nil }
    return vector.map { $0 / norm }
}

private func mean(_ vectors: [[Double]]) -> [Double]? {
    guard let first = vectors.first, !first.isEmpty,
          vectors.allSatisfy({ $0.count == first.count }) else { return nil }
    var result = Array(repeating: 0.0, count: first.count)
    for vector in vectors {
        for index in result.indices { result[index] += vector[index] }
    }
    return normalize(result.map { $0 / Double(vectors.count) })
}

private func cosine(_ lhs: [Double], _ rhs: [Double]) -> Double {
    guard lhs.count == rhs.count else { return -1 }
    return zip(lhs, rhs).reduce(0) { $0 + $1.0 * $1.1 }
}

private func overlap(_ aStart: Double, _ aEnd: Double, _ bStart: Double, _ bEnd: Double) -> Double {
    max(0, min(aEnd, bEnd) - max(aStart, bStart))
}

private func readRTTM(_ url: URL) throws -> [ReferenceSegment] {
    var result: [ReferenceSegment] = []
    for (index, raw) in try String(contentsOf: url, encoding: .utf8)
        .split(whereSeparator: \.isNewline)
        .enumerated() {
        let fields = raw.split(whereSeparator: \.isWhitespace)
        guard fields.count >= 8, fields[0] == "SPEAKER",
              let start = Double(fields[3]), let duration = Double(fields[4]),
              start.isFinite, duration.isFinite,
              start >= 0, duration > 0, start + duration <= 6 * 60 * 60 else {
            throw NSError(
                domain: "TeacherRest",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Invalid RTTM line \(index + 1) in \(url.lastPathComponent)"
                ]
            )
        }
        result.append(
            ReferenceSegment(
                start: start,
                end: start + duration,
                speaker: String(fields[7])
            )
        )
    }
    return result
}

private func resolve(_ path: String, relativeTo directory: URL) -> URL {
    path.hasPrefix("/")
        ? URL(fileURLWithPath: path)
        : directory.appendingPathComponent(path)
}

private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}

private func loadDatasets(_ manifestURL: URL, split: String) throws -> [Dataset] {
    let manifest = try loadJSON(Manifest.self, from: manifestURL)
    let root = manifestURL.deletingLastPathComponent()
    return try manifest.entries.filter { $0.split == split }.map { entry in
        Dataset(
            entry: entry,
            candidate: try loadJSON(
                CandidateFile.self,
                from: resolve(entry.candidatePath, relativeTo: root)
            ),
            reference: try readRTTM(resolve(entry.referencePath, relativeTo: root)),
            metadata: try loadJSON(
                Metadata.self,
                from: resolve(entry.metadataPath, relativeTo: root)
            )
        )
    }
}

private func candidateOverlapIndices(_ segments: [CandidateSegment]) -> Set<Int> {
    let order = segments.indices.sorted {
        segments[$0].startTimeSeconds < segments[$1].startTimeSeconds
    }
    var result: Set<Int> = []
    for position in order.indices {
        let lhsIndex = order[position]
        let lhs = segments[lhsIndex]
        var next = position + 1
        while next < order.count {
            let rhsIndex = order[next]
            let rhs = segments[rhsIndex]
            if rhs.startTimeSeconds >= lhs.endTimeSeconds { break }
            if rhs.speakerId != lhs.speakerId,
               overlap(
                lhs.startTimeSeconds, lhs.endTimeSeconds,
                rhs.startTimeSeconds, rhs.endTimeSeconds
               ) > 0 {
                result.insert(lhsIndex)
                result.insert(rhsIndex)
            }
            next += 1
        }
    }
    return result
}

private func mappedTeacherCluster(
    segments: [CandidateSegment],
    reference: [ReferenceSegment],
    teacher: String
) -> String? {
    var scores: [String: Double] = [:]
    for segment in segments {
        for turn in reference where turn.speaker == teacher {
            scores[segment.speakerId, default: 0] += overlap(
                segment.startTimeSeconds, segment.endTimeSeconds,
                turn.start, turn.end
            )
        }
    }
    guard let winner = scores.max(by: { $0.value < $1.value }),
          winner.value > 0 else { return nil }
    return winner.key
}

private func suggestedCluster(
    segments: [CandidateSegment],
    gate: Gate
) -> String? {
    var durations: [String: Double] = [:]
    for segment in segments {
        durations[segment.speakerId, default: 0] += segment.duration
    }
    let ranked = durations.sorted { $0.value > $1.value }
    guard let first = ranked.first else { return nil }
    let total = max(1e-9, ranked.reduce(0) { $0 + $1.value })
    let second = ranked.dropFirst().first?.value ?? 0
    let ratio = second > 0 ? first.value / second : .infinity
    guard first.value / total >= gate.dominanceSuggestion.minimumTopShare,
          ratio >= gate.dominanceSuggestion.minimumTopToSecondRatio else {
        return nil
    }
    return first.key
}

private func isCleanTurn(
    _ segment: CandidateSegment,
    overlapping: Bool,
    gate: Gate
) -> Bool {
    !overlapping
        && segment.duration >= gate.turnFiltering.minimumDurationSeconds
        && segment.qualityScore >= gate.turnFiltering.minimumQuality
        && segment.speech >= gate.turnFiltering.minimumQuality
        && segment.overlapP < 0.3
        && segment.snr >= 6
}

private func teacherPrototypes(
    segments: [CandidateSegment],
    confirmedCluster: String,
    overlapping: Set<Int>,
    gate: Gate
) -> [[Double]] {
    let clean = segments.indices.compactMap { index -> (Double, [Double])? in
        let segment = segments[index]
        guard segment.speakerId == confirmedCluster,
              isCleanTurn(
                  segment,
                  overlapping: overlapping.contains(index),
                  gate: gate
              ),
              let vector = normalize(segment.embedding) else { return nil }
        return (segment.duration * segment.qualityScore, vector)
    }.sorted { $0.0 > $1.0 }
    guard let initial = mean(clean.map(\.1)), !clean.isEmpty else { return [] }
    let similarities = clean.map { cosine($0.1, initial) }.sorted()
    let median = similarities[similarities.count / 2]
    return Array(
        clean.compactMap { cosine($0.1, initial) >= median ? $0.1 : nil }.prefix(8)
    )
}

private func turnRole(
    _ segment: CandidateSegment,
    prototypes: [[Double]],
    teacherThreshold: Double,
    othersThreshold: Double
) -> Role {
    guard let vector = normalize(segment.embedding), !prototypes.isEmpty else {
        return .unknown
    }
    let scores = prototypes.map { cosine(vector, $0) }
    let best = scores.max() ?? -1
    let agreed = scores.filter { $0 >= teacherThreshold }.count
    if best >= teacherThreshold && agreed >= min(2, prototypes.count) {
        return .teacher
    }
    if best <= othersThreshold {
        return .others
    }
    return .unknown
}

private func frameRange(start: Double, end: Double, frameCount: Int) -> Range<Int> {
    let lower = max(0, min(frameCount, Int(floor(start * 100))))
    let upper = max(lower, min(frameCount, Int(ceil(end * 100))))
    return lower..<upper
}

private func referenceFrames(
    duration: Double,
    reference: [ReferenceSegment],
    teacher: String
) -> [Role] {
    let count = Int(ceil(duration * 100))
    var active = Array(repeating: UInt8(0), count: count)
    var teacherActive = Array(repeating: false, count: count)
    for segment in reference {
        for frame in frameRange(start: segment.start, end: segment.end, frameCount: count) {
            active[frame] &+= 1
            if segment.speaker == teacher { teacherActive[frame] = true }
        }
    }
    return active.indices.map { frame in
        if active[frame] == 0 { return .silence }
        if active[frame] > 1 { return .unknown }
        return teacherActive[frame] ? .teacher : .others
    }
}

private func smoothRoles(_ frames: [Role]) -> [Role] {
    var result = frames
    var index = 0
    while index < result.count {
        guard result[index] == .unknown else {
            index += 1
            continue
        }
        let start = index
        while index < result.count && result[index] == .unknown {
            index += 1
        }
        let left = start > 0 ? result[start - 1] : nil
        let right = index < result.count ? result[index] : nil
        if let left,
           left == right,
           left == .teacher || left == .others,
           index - start <= 30 {
            for frame in start..<index { result[frame] = left }
        }
    }
    return result
}

private func predictedFrames(
    duration: Double,
    segments: [CandidateSegment],
    roles: [Role],
    overlapping: Set<Int>,
    gate: Gate
) -> [Role] {
    let count = Int(ceil(duration * 100))
    var frames = Array(repeating: Role.silence, count: count)
    for index in segments.indices {
        let segment = segments[index]
        let role: Role
        if overlapping.contains(index) || segment.overlapP >= 0.3 {
            role = .unknown
        } else if !isCleanTurn(segment, overlapping: false, gate: gate) {
            continue
        } else {
            role = roles[index]
        }
        for frame in frameRange(
            start: segment.startTimeSeconds,
            end: segment.endTimeSeconds,
            frameCount: count
        ) {
            if frames[frame] == .silence {
                frames[frame] = role
            } else if frames[frame] != role {
                frames[frame] = .unknown
            }
        }
    }
    return smoothRoles(frames)
}

private func analyze(
    _ dataset: Dataset,
    gate: Gate,
    teacherThreshold: Double,
    othersThreshold: Double
) -> FileResult {
    let segments = dataset.candidate.segments
    let overlapping = candidateOverlapIndices(segments)
    let confirmed = mappedTeacherCluster(
        segments: segments,
        reference: dataset.reference,
        teacher: dataset.metadata.teacherSpeaker
    )
    let suggestion = suggestedCluster(segments: segments, gate: gate)
    let prototypes = confirmed.map {
        teacherPrototypes(
            segments: segments,
            confirmedCluster: $0,
            overlapping: overlapping,
            gate: gate
        )
    } ?? []
    let roles = segments.enumerated().map { index, segment in
        guard isCleanTurn(
            segment,
            overlapping: overlapping.contains(index),
            gate: gate
        ) else { return Role.unknown }
        return turnRole(
            segment,
            prototypes: prototypes,
            teacherThreshold: teacherThreshold,
            othersThreshold: othersThreshold
        )
    }
    let reference = referenceFrames(
        duration: dataset.candidate.durationSeconds,
        reference: dataset.reference,
        teacher: dataset.metadata.teacherSpeaker
    )
    let predicted = predictedFrames(
        duration: dataset.candidate.durationSeconds,
        segments: segments,
        roles: roles,
        overlapping: overlapping,
        gate: gate
    )
    var counts = Counts()
    for index in reference.indices {
        let expected = reference[index]
        let actual = predicted[index]
        if expected == .teacher {
            counts.teacherFalseNegative += actual == .teacher ? 0 : 1
            counts.teacherTruePositive += actual == .teacher ? 1 : 0
            counts.speechFrames += 1
            counts.unknownSpeechFrames += actual == .unknown ? 1 : 0
        } else if expected == .others {
            counts.othersTotal += 1
            counts.othersCorrect += actual == .others ? 1 : 0
            counts.speechFrames += 1
            counts.unknownSpeechFrames += actual == .unknown ? 1 : 0
        } else if expected == .silence {
            counts.silenceFrames += 1
            counts.silenceFalsePositive += actual == .silence ? 0 : 1
        } else {
            counts.overlapFrames += 1
            counts.unsafeOverlapFrames += (actual == .teacher || actual == .others) ? 1 : 0
        }
        if actual == .teacher && expected != .teacher {
            counts.teacherFalsePositive += 1
        }
    }
    counts.suggestionsTotal = 1
    counts.suggestionsCorrect = suggestion != nil && suggestion == confirmed ? 1 : 0
    for question in dataset.metadata.questions where question.referenceRole == "others" {
        counts.studentQuestionsTotal += 1
        let midpoint = max(0, min(predicted.count - 1, Int(((question.start + question.end) / 2) * 100)))
        counts.studentQuestionsCorrect += predicted[midpoint] == .others ? 1 : 0
    }
    return FileResult(
        id: dataset.entry.id,
        teacherPrecision: ratio(
            counts.teacherTruePositive,
            counts.teacherTruePositive + counts.teacherFalsePositive
        ),
        teacherRecall: ratio(
            counts.teacherTruePositive,
            counts.teacherTruePositive + counts.teacherFalseNegative
        ),
        mainSuggestionCorrect: counts.suggestionsCorrect == 1,
        studentQuestionAttribution: ratio(
            counts.studentQuestionsCorrect,
            counts.studentQuestionsTotal
        ),
        silenceFalsePositiveRate: ratio(
            counts.silenceFalsePositive,
            counts.silenceFrames
        ),
        unsafeOverlapAssignmentRate: ratio(
            counts.unsafeOverlapFrames,
            counts.overlapFrames
        ),
        unknownSpeechRate: ratio(counts.unknownSpeechFrames, counts.speechFrames),
        realTimeFactor: dataset.candidate.durationSeconds
            / max(1e-9, dataset.candidate.processingTimeSeconds),
        suggestedCluster: suggestion,
        confirmedCluster: confirmed,
        teacherSimilarity: teacherThreshold,
        othersSimilarity: othersThreshold,
        counts: counts
    )
}

private func aggregate(
    _ files: [FileResult],
    datasets: [Dataset]
) -> AggregateMetrics {
    var counts = Counts()
    for file in files { counts.add(file.counts) }
    return AggregateMetrics(
        teacherPrecision: ratio(
            counts.teacherTruePositive,
            counts.teacherTruePositive + counts.teacherFalsePositive
        ),
        teacherRecall: ratio(
            counts.teacherTruePositive,
            counts.teacherTruePositive + counts.teacherFalseNegative
        ),
        mainSuggestionAccuracy: ratio(
            counts.suggestionsCorrect,
            counts.suggestionsTotal
        ),
        studentQuestionAttribution: ratio(
            counts.studentQuestionsCorrect,
            counts.studentQuestionsTotal
        ),
        silenceFalsePositiveRate: ratio(
            counts.silenceFalsePositive,
            counts.silenceFrames
        ),
        unsafeOverlapAssignmentRate: ratio(
            counts.unsafeOverlapFrames,
            counts.overlapFrames
        ),
        unknownSpeechRate: ratio(counts.unknownSpeechFrames, counts.speechFrames),
        minimumRealTimeFactor: files.map(\.realTimeFactor).min() ?? 0,
        maximumPeakMemoryBytes: datasets.compactMap(\.entry.peakMemoryBytes).max() ?? 0,
        maximumModelBytes: datasets.compactMap(\.entry.modelBytes).max() ?? 0,
        counts: counts
    )
}

private func calibrationPasses(_ metrics: AggregateMetrics, gate: Gate) -> Bool {
    metrics.teacherPrecision >= gate.metrics.teacherPrecisionMinimum
        && metrics.silenceFalsePositiveRate <= gate.metrics.silenceFalsePositiveMaximum
        && metrics.unsafeOverlapAssignmentRate <= gate.metrics.unsafeOverlapAssignmentMaximum
}

private func calibrate(gate: Gate, datasets: [Dataset]) -> Thresholds {
    var candidates: [(Double, Double, AggregateMetrics)] = []
    for teacher in gate.thresholdSelection.teacherSimilarityGrid {
        for width in gate.thresholdSelection.unknownWidthGrid {
            let others = teacher - width
            guard others >= -1 else { continue }
            let files = datasets.map {
                analyze(
                    $0,
                    gate: gate,
                    teacherThreshold: teacher,
                    othersThreshold: others
                )
            }
            candidates.append((teacher, others, aggregate(files, datasets: datasets)))
        }
    }
    let passing = candidates.filter { calibrationPasses($0.2, gate: gate) }
    let pool = passing.isEmpty ? candidates : passing
    let selected = pool.max { lhs, rhs in
        if lhs.2.teacherRecall != rhs.2.teacherRecall {
            return lhs.2.teacherRecall < rhs.2.teacherRecall
        }
        if lhs.2.unknownSpeechRate != rhs.2.unknownSpeechRate {
            return lhs.2.unknownSpeechRate > rhs.2.unknownSpeechRate
        }
        return lhs.0 < rhs.0
    }!
    return Thresholds(
        teacherSimilarity: selected.0,
        othersSimilarity: selected.1,
        selectionStatus: passing.isEmpty
            ? "NO_CONFIGURATION_MET_CALIBRATION_CONSTRAINTS"
            : "CALIBRATION_CONSTRAINTS_MET",
        calibrationMetrics: selected.2
    )
}

private func identityChecks(
    metrics: AggregateMetrics,
    prefix: String,
    gate: Gate
) -> [EvaluationReport.Check] {
    [
        .init(name: "\(prefix).teacherPrecision", passed: metrics.teacherPrecision >= gate.metrics.teacherPrecisionMinimum, actual: metrics.teacherPrecision, required: gate.metrics.teacherPrecisionMinimum),
        .init(name: "\(prefix).teacherRecall", passed: metrics.teacherRecall >= gate.metrics.teacherRecallMinimum, actual: metrics.teacherRecall, required: gate.metrics.teacherRecallMinimum),
        .init(name: "\(prefix).mainSuggestionAccuracy", passed: metrics.mainSuggestionAccuracy >= gate.metrics.mainSuggestionAccuracyMinimum, actual: metrics.mainSuggestionAccuracy, required: gate.metrics.mainSuggestionAccuracyMinimum),
        .init(name: "\(prefix).studentQuestionAttribution", passed: metrics.studentQuestionAttribution >= gate.metrics.studentQuestionAttributionMinimum, actual: metrics.studentQuestionAttribution, required: gate.metrics.studentQuestionAttributionMinimum),
        .init(name: "\(prefix).silenceFalsePositive", passed: metrics.silenceFalsePositiveRate <= gate.metrics.silenceFalsePositiveMaximum, actual: metrics.silenceFalsePositiveRate, required: gate.metrics.silenceFalsePositiveMaximum),
        .init(name: "\(prefix).unsafeOverlapAssignment", passed: metrics.unsafeOverlapAssignmentRate <= gate.metrics.unsafeOverlapAssignmentMaximum, actual: metrics.unsafeOverlapAssignmentRate, required: gate.metrics.unsafeOverlapAssignmentMaximum)
    ]
}

private func evaluationChecks(
    amiMetrics: AggregateMetrics,
    classroomMetrics: AggregateMetrics?,
    evidence: GateEvidence,
    gate: Gate
) -> [EvaluationReport.Check] {
    let minimumLongFormRTF = evidence.runs.map(\.realTimeFactor).min() ?? 0
    let maximumLongFormPeak = evidence.runs.map(\.peakFootprintBytes).max() ?? 0
    let durations = Set(evidence.runs.map(\.minutes))
    let durationsPass = Set(gate.longForm.durationsMinutes).isSubset(of: durations)
    let networkPass = evidence.networkRequestsObserved == gate.privacy.networkRequestsAllowed
        && evidence.runs.allSatisfy(\.networkDeniedSandbox)
    var checks = identityChecks(metrics: amiMetrics, prefix: "ami", gate: gate)
    if let classroomMetrics {
        checks += identityChecks(
            metrics: classroomMetrics,
            prefix: "classroom",
            gate: gate
        )
    } else {
        checks.append(
            .init(
                name: "classroom.evaluationPresent",
                passed: false,
                actual: 0,
                required: 1
            )
        )
    }
    checks += [
        .init(name: "requiredLongFormDurations", passed: durationsPass, actual: Double(durations.intersection(Set(gate.longForm.durationsMinutes)).count), required: Double(gate.longForm.durationsMinutes.count)),
        .init(name: "longFormRealTimeFactor", passed: minimumLongFormRTF >= gate.metrics.minimumRealTimeFactor, actual: minimumLongFormRTF, required: gate.metrics.minimumRealTimeFactor),
        .init(name: "longFormPeakMemoryBytes", passed: maximumLongFormPeak > 0 && maximumLongFormPeak < gate.metrics.maximumPeakMemoryBytes, actual: Double(maximumLongFormPeak), required: Double(gate.metrics.maximumPeakMemoryBytes)),
        .init(name: "networkIsolation", passed: networkPass, actual: networkPass ? 1 : 0, required: 1),
        .init(name: "temporaryArtifactCleanup", passed: evidence.temporaryArtifactsRemaining == 0, actual: Double(evidence.temporaryArtifactsRemaining), required: 0),
        .init(name: "embeddingArtifactCleanup", passed: evidence.embeddingArtifactsRemaining == 0 && evidence.modelCacheArtifactsRemaining == 0, actual: Double(evidence.embeddingArtifactsRemaining + evidence.modelCacheArtifactsRemaining), required: 0),
        .init(name: "crossLectureEmbeddingIsolation", passed: evidence.crossLectureEmbeddingComparisons == gate.privacy.crossLectureEmbeddingComparisonsAllowed, actual: Double(evidence.crossLectureEmbeddingComparisons), required: Double(gate.privacy.crossLectureEmbeddingComparisonsAllowed)),
        .init(name: "persistentVoiceprints", passed: evidence.persistentVoiceprints == gate.privacy.persistentVoiceprintsAllowed, actual: Double(evidence.persistentVoiceprints), required: Double(gate.privacy.persistentVoiceprintsAllowed)),
        .init(name: "persistedEmbeddingEncryption", passed: evidence.persistedEmbeddingArtifactsEncrypted == gate.privacy.embeddingCacheEncryptedIfPersisted, actual: evidence.persistedEmbeddingArtifactsEncrypted ? 1 : 0, required: gate.privacy.embeddingCacheEncryptedIfPersisted ? 1 : 0),
        .init(name: "deleteBehavior", passed: evidence.deleteBehaviorVerified == gate.privacy.deleteMustRemoveTurnsEmbeddingsAndCaches, actual: evidence.deleteBehaviorVerified ? 1 : 0, required: gate.privacy.deleteMustRemoveTurnsEmbeddingsAndCaches ? 1 : 0)
    ]
    return checks
}

private struct ClassroomValidation {
    let missing: [String]
    let calibration: [Dataset]
    let evaluation: [Dataset]
}

private func validateClassroom(
    statusURL: URL,
    status: CorpusStatus,
    gate: Gate
) -> ClassroomValidation {
    var missing: [String] = []
    let summary = status.classroom
    guard summary.ready, let manifestPath = summary.manifest else {
        return ClassroomValidation(
            missing: [
                "classroom corpus is not ready",
                "classroom manifest is missing",
                "classroom consent is not validated",
                "required classroom durations are missing"
            ],
            calibration: [],
            evaluation: []
        )
    }
    let manifestURL = resolve(
        manifestPath,
        relativeTo: statusURL.deletingLastPathComponent()
    )
    let allowedKeys: Set<String> = [
        "lectureID", "split", "teacherID", "roomID", "audioPath", "rttmPath",
        "questionsPath", "candidatePath", "durationSeconds",
        "studentQuestionCount", "teacherConsent", "participantConsent", "notes"
    ]
    let records: [ClassroomRecord]
    do {
        records = try String(contentsOf: manifestURL, encoding: .utf8)
            .split(whereSeparator: \.isNewline)
            .map { line in
                let data = Data(line.utf8)
                guard let object = try JSONSerialization.jsonObject(with: data)
                        as? [String: Any],
                      Set(object.keys).isSubset(of: allowedKeys) else {
                    throw NSError(
                        domain: "TeacherRest",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "invalid classroom manifest keys"]
                    )
                }
                return try JSONDecoder().decode(ClassroomRecord.self, from: data)
            }
    } catch {
        return ClassroomValidation(
            missing: [
                "classroom manifest validation failed: \(error.localizedDescription)"
            ],
            calibration: [],
            evaluation: []
        )
    }
    let manifestRoot = manifestURL.deletingLastPathComponent()
    if Set(records.map(\.lectureID)).count != records.count {
        missing.append("duplicate classroom lecture IDs")
    }
    var derivedQuestionCounts: [String: Int] = [:]
    var datasets: [Dataset] = []
    for record in records {
        let requiredStrings = [
            record.lectureID, record.teacherID, record.roomID, record.audioPath,
            record.rttmPath, record.questionsPath, record.candidatePath
        ]
        if requiredStrings.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) {
            missing.append("empty required classroom field for \(record.lectureID)")
        }
        if record.split != "calibration" && record.split != "evaluation" {
            missing.append("invalid classroom split for \(record.lectureID)")
        }
        if !record.durationSeconds.isFinite
            || record.durationSeconds < 1_800
            || record.durationSeconds > 5_400 {
            missing.append("invalid classroom duration for \(record.lectureID)")
        }
        if record.studentQuestionCount < 0 {
            missing.append("invalid question count for \(record.lectureID)")
        }
        if gate.classroom.consentRequired
            && (!record.teacherConsent || !record.participantConsent) {
            missing.append("missing consent for \(record.lectureID)")
        }
        let audioURL = resolve(record.audioPath, relativeTo: manifestRoot)
        let rttmURL = resolve(record.rttmPath, relativeTo: manifestRoot)
        let questionsURL = resolve(record.questionsPath, relativeTo: manifestRoot)
        let candidateURL = resolve(record.candidatePath, relativeTo: manifestRoot)
        for url in [audioURL, rttmURL, questionsURL, candidateURL] {
            do {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .fileSizeKey]
                )
                if values.isRegularFile != true || (values.fileSize ?? 0) <= 0 {
                    missing.append("invalid classroom artifact for \(record.lectureID)")
                }
            } catch {
                missing.append("missing classroom artifact for \(record.lectureID)")
            }
        }
        do {
            let turns = try readRTTM(rttmURL)
            guard !turns.isEmpty,
                  !turns.contains(where: { $0.end > record.durationSeconds }),
                  turns.contains(where: { $0.speaker == record.teacherID }) else {
                throw NSError(
                    domain: "TeacherRest",
                    code: 4,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "RTTM is outside duration or omits teacher"
                    ]
                )
            }
            let questions = try loadJSON([ClassroomQuestion].self, from: questionsURL)
            let roles = Set(["teacher", "others", "overlap"])
            guard !questions.contains(where: {
                !$0.start.isFinite || !$0.end.isFinite
                    || $0.start < 0 || $0.end <= $0.start
                    || $0.end > record.durationSeconds
                    || $0.text.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty
                    || !roles.contains($0.referenceRole)
            }) else {
                throw NSError(
                    domain: "TeacherRest",
                    code: 5,
                    userInfo: [NSLocalizedDescriptionKey: "invalid question annotation"]
                )
            }
            let derived = questions.filter { $0.referenceRole == "others" }.count
            derivedQuestionCounts[record.lectureID] = derived
            if derived != record.studentQuestionCount {
                missing.append("question count mismatch for \(record.lectureID)")
            }
            let candidate = try loadJSON(CandidateFile.self, from: candidateURL)
            let embeddingDimension = candidate.segments.first?.embedding.count ?? 0
            guard candidate.durationSeconds.isFinite,
                  candidate.durationSeconds > 0,
                  abs(candidate.durationSeconds - record.durationSeconds) <= 1,
                  candidate.processingTimeSeconds.isFinite,
                  candidate.processingTimeSeconds > 0,
                  !candidate.segments.isEmpty,
                  embeddingDimension > 0,
                  !candidate.segments.contains(where: {
                      !$0.startTimeSeconds.isFinite
                          || !$0.endTimeSeconds.isFinite
                          || $0.startTimeSeconds < 0
                          || $0.endTimeSeconds <= $0.startTimeSeconds
                          || $0.endTimeSeconds > candidate.durationSeconds
                          || !$0.qualityScore.isFinite
                          || $0.qualityScore < 0
                          || $0.qualityScore > 1
                          || $0.speakerId.trimmingCharacters(
                              in: .whitespacesAndNewlines
                          ).isEmpty
                          || $0.embedding.count != embeddingDimension
                          || $0.embedding.contains(where: { !$0.isFinite })
                  }) else {
                throw NSError(
                    domain: "TeacherRest",
                    code: 7,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "candidate output is invalid or mismatched"
                    ]
                )
            }
            let metadata = Metadata(
                meeting: record.lectureID,
                teacherSpeaker: record.teacherID,
                questions: questions.map {
                    .init(
                        start: $0.start,
                        end: $0.end,
                        speaker: "",
                        referenceRole: $0.referenceRole,
                        text: $0.text
                    )
                }
            )
            datasets.append(
                Dataset(
                    entry: .init(
                        id: record.lectureID,
                        split: record.split,
                        candidatePath: record.candidatePath,
                        referencePath: record.rttmPath,
                        metadataPath: record.questionsPath,
                        peakMemoryBytes: nil,
                        modelBytes: nil,
                        source: "consented-classroom"
                    ),
                    candidate: candidate,
                    reference: turns,
                    metadata: metadata
                )
            )
        } catch {
            missing.append(
                "classroom evidence validation failed for \(record.lectureID): "
                    + error.localizedDescription
            )
        }
    }
    let calibrationRecords = records.filter { $0.split == "calibration" }
    let evaluationRecords = records.filter { $0.split == "evaluation" }
    let calibrationTeachers = Set(calibrationRecords.map(\.teacherID))
    let calibrationRooms = Set(calibrationRecords.map(\.roomID))
    let evaluationTeachers = Set(evaluationRecords.map(\.teacherID))
    let evaluationRooms = Set(evaluationRecords.map(\.roomID))
    let evaluationHours = evaluationRecords.reduce(0) {
        $0 + $1.durationSeconds
    } / 3_600
    let evaluationQuestions = evaluationRecords.reduce(0) {
        $0 + (derivedQuestionCounts[$1.lectureID] ?? 0)
    }
    if evaluationRecords.count < gate.classroom.minimumEvaluationLectures { missing.append("insufficient classroom lectures") }
    if evaluationTeachers.count < gate.classroom.minimumEvaluationTeachers { missing.append("insufficient distinct classroom teachers") }
    if evaluationRooms.count < gate.classroom.minimumEvaluationRooms { missing.append("insufficient classroom rooms") }
    if evaluationHours < gate.classroom.minimumEvaluationHours { missing.append("insufficient classroom hours") }
    if evaluationQuestions < gate.classroom.minimumEvaluationStudentQuestions { missing.append("insufficient student questions") }
    let teachersDisjoint = calibrationTeachers.isDisjoint(with: evaluationTeachers)
    let roomsDisjoint = calibrationRooms.isDisjoint(with: evaluationRooms)
    if gate.classroom.teacherDisjointCalibrationAndEvaluation && !teachersDisjoint {
        missing.append("classroom teachers are not split-disjoint")
    }
    if gate.classroom.roomDisjointCalibrationAndEvaluation && !roomsDisjoint {
        missing.append("classroom rooms are not split-disjoint")
    }
    let requiredDurations = gate.classroom.requiredDurationsMinutes.sorted()
    for (index, minutes) in requiredDurations.enumerated() {
        let lower = Double(minutes * 60)
        let upper = index + 1 < requiredDurations.count
            ? Double(requiredDurations[index + 1] * 60)
            : .infinity
        if !evaluationRecords.contains(where: {
            $0.durationSeconds >= lower && $0.durationSeconds < upper
        }) {
            missing.append("missing classroom \(minutes)-minute evaluation lecture")
        }
    }
    if summary.evaluationLectures != evaluationRecords.count
        || summary.evaluationTeachers != evaluationTeachers.count
        || summary.evaluationRooms != evaluationRooms.count
        || abs(summary.evaluationHours - evaluationHours) > 0.001
        || summary.evaluationStudentQuestions != evaluationQuestions
        || summary.teacherDisjoint != teachersDisjoint
        || summary.roomDisjoint != roomsDisjoint {
        missing.append("classroom status summary does not match manifest")
    }
    let calibration = datasets.filter { $0.entry.split == "calibration" }
    let evaluation = datasets.filter { $0.entry.split == "evaluation" }
    if calibration.count != calibrationRecords.count
        || evaluation.count != evaluationRecords.count {
        missing.append("not every classroom record has scorable candidate output")
    }
    return ClassroomValidation(
        missing: Array(Set(missing)).sorted(),
        calibration: calibration,
        evaluation: evaluation
    )
}

private func classroomPrerequisites(
    statusURL: URL,
    status: CorpusStatus,
    gate: Gate
) -> [String] {
    validateClassroom(statusURL: statusURL, status: status, gate: gate).missing
}

private func runSelfCheck() {
    let gate = Gate(
        metrics: .init(
            teacherPrecisionMinimum: 0.98,
            teacherRecallMinimum: 0.95,
            mainSuggestionAccuracyMinimum: 0.95,
            studentQuestionAttributionMinimum: 0.95,
            silenceFalsePositiveMaximum: 0.02,
            unsafeOverlapAssignmentMaximum: 0,
            minimumRealTimeFactor: 10,
            maximumPeakMemoryBytes: 1_073_741_824,
            preferredMaximumModelBytes: 104_857_600
        ),
        dominanceSuggestion: .init(minimumTopShare: 0.35, minimumTopToSecondRatio: 1.25),
        turnFiltering: .init(minimumDurationSeconds: 1, minimumQuality: 0.7),
        thresholdSelection: .init(teacherSimilarityGrid: [0.8], unknownWidthGrid: [0.1]),
        classroom: .init(
            required: true,
            consentRequired: true,
            minimumEvaluationLectures: 10,
            minimumEvaluationTeachers: 5,
            minimumEvaluationRooms: 3,
            minimumEvaluationHours: 8,
            minimumEvaluationStudentQuestions: 100,
            teacherDisjointCalibrationAndEvaluation: true,
            roomDisjointCalibrationAndEvaluation: true,
            requiredDurationsMinutes: [30, 60, 90]
        ),
        longForm: .init(
            durationsMinutes: [30, 60, 90],
            mustCompleteLocally: true,
            mustLeaveNoTemporaryArtifacts: true
        ),
        privacy: .init(
            networkRequestsAllowed: 0,
            crossLectureEmbeddingComparisonsAllowed: 0,
            persistentVoiceprintsAllowed: 0,
            embeddingCacheEncryptedIfPersisted: true,
            deleteMustRemoveTurnsEmbeddingsAndCaches: true
        )
    )
    let teacher = normalize([1, 0])!
    let other = normalize([0, 1])!
    let candidate = CandidateFile(
        durationSeconds: 10,
        processingTimeSeconds: 0.1,
        segments: [
            .init(embedding: teacher, endTimeSeconds: 4, qualityScore: 1, speakerId: "A", startTimeSeconds: 0),
            .init(embedding: other, endTimeSeconds: 6, qualityScore: 1, speakerId: "B", startTimeSeconds: 4),
            .init(embedding: teacher, endTimeSeconds: 10, qualityScore: 1, speakerId: "A", startTimeSeconds: 6)
        ]
    )
    let metadata = Metadata(
        meeting: "test",
        teacherSpeaker: "T",
        questions: [.init(start: 4, end: 5, speaker: "S", referenceRole: "others", text: "question")]
    )
    let dataset = Dataset(
        entry: .init(id: "test", split: "evaluation", candidatePath: "", referencePath: "", metadataPath: "", peakMemoryBytes: 10, modelBytes: 10, source: nil),
        candidate: candidate,
        reference: [
            .init(start: 0, end: 4, speaker: "T"),
            .init(start: 4, end: 6, speaker: "S"),
            .init(start: 6, end: 10, speaker: "T")
        ],
        metadata: metadata
    )
    let result = analyze(dataset, gate: gate, teacherThreshold: 0.8, othersThreshold: 0.7)
    precondition(result.teacherPrecision == 1)
    precondition(result.teacherRecall == 1)
    precondition(result.studentQuestionAttribution == 1)
    precondition(result.mainSuggestionCorrect)
    precondition(
        mappedTeacherCluster(
            segments: candidate.segments,
            reference: [.init(start: 20, end: 21, speaker: "T")],
            teacher: "T"
        ) == nil
    )
    let mixed = CandidateFile(
        durationSeconds: 10,
        processingTimeSeconds: 0.1,
        segments: [
            .init(embedding: teacher, endTimeSeconds: 4, qualityScore: 1, speakerId: "A", startTimeSeconds: 0),
            .init(embedding: other, endTimeSeconds: 6, qualityScore: 1, speakerId: "A", startTimeSeconds: 4),
            .init(embedding: teacher, endTimeSeconds: 10, qualityScore: 1, speakerId: "A", startTimeSeconds: 6)
        ]
    )
    let mixedResult = analyze(
        Dataset(
            entry: dataset.entry,
            candidate: mixed,
            reference: dataset.reference,
            metadata: metadata
        ),
        gate: gate,
        teacherThreshold: 0.8,
        othersThreshold: 0.7
    )
    precondition(mixedResult.teacherPrecision == 1)
    precondition(mixedResult.studentQuestionAttribution == 1)
    let evidence = GateEvidence(
        modelBytes: 10,
        runs: [30, 60, 90].map {
            .init(
                minutes: $0,
                realTimeFactor: 20,
                maximumResidentBytes: 10,
                peakFootprintBytes: 10,
                networkDeniedSandbox: true
            )
        },
        networkRequestsObserved: 0,
        temporaryArtifactsRemaining: 0,
        embeddingArtifactsRemaining: 0,
        modelCacheArtifactsRemaining: 0,
        crossLectureEmbeddingComparisons: 0,
        persistentVoiceprints: 0,
        persistedEmbeddingArtifactsEncrypted: false,
        deleteBehaviorVerified: false
    )
    let selfCheckMetrics = aggregate([result], datasets: [dataset])
    let checks = evaluationChecks(
        amiMetrics: selfCheckMetrics,
        classroomMetrics: selfCheckMetrics,
        evidence: evidence,
        gate: gate
    )
    precondition(
        checks.first { $0.name == "requiredLongFormDurations" }?.passed == true
    )
    precondition(
        checks.first { $0.name == "persistedEmbeddingEncryption" }?.passed == false
    )
    precondition(
        checks.first { $0.name == "deleteBehavior" }?.passed == false
    )
    let missingClassroom = classroomPrerequisites(
        statusURL: URL(fileURLWithPath: "/tmp/status.json"),
        status: CorpusStatus(
            classroom: .init(
                ready: false,
                manifest: nil,
                evaluationLectures: 0,
                evaluationTeachers: 0,
                evaluationRooms: 0,
                evaluationHours: 0,
                evaluationStudentQuestions: 0,
                teacherDisjoint: false,
                roomDisjoint: false
            )
        ),
        gate: gate
    )
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("teacher-rest-classroom-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(
        at: root,
        withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    var classroomRecords: [ClassroomRecord] = []
    let durations = [1_800.0, 3_600.0, 5_400.0]
        + Array(repeating: 3_600.0, count: 7)
    for index in 0..<11 {
        let calibration = index == 0
        let lectureID = calibration ? "calibration" : "evaluation-\(index)"
        let teacherID = calibration ? "teacher-cal" : "teacher-\((index - 1) % 5)"
        let roomID = calibration ? "room-cal" : "room-\((index - 1) % 3)"
        let duration = calibration ? 1_800 : durations[index - 1]
        let audio = root.appendingPathComponent("\(lectureID).wav")
        let rttm = root.appendingPathComponent("\(lectureID).rttm")
        let questions = root.appendingPathComponent("\(lectureID)-questions.json")
        let candidateURL = root.appendingPathComponent("\(lectureID)-candidate.json")
        try! Data([0]).write(to: audio)
        try! Data(
            "SPEAKER \(lectureID) 1 0.000 10.000 <NA> <NA> \(teacherID) <NA> <NA>\n".utf8
        ).write(to: rttm)
        let questionRows = (0..<10).map {
            ClassroomQuestion(
                start: Double($0 + 1),
                end: Double($0 + 1) + 0.5,
                text: "question \($0)",
                referenceRole: "others"
            )
        }
        try! JSONEncoder().encode(questionRows).write(to: questions)
        try! JSONEncoder().encode(
            CandidateFile(
                durationSeconds: duration,
                processingTimeSeconds: 1,
                segments: candidate.segments
            )
        ).write(to: candidateURL)
        classroomRecords.append(
            ClassroomRecord(
                lectureID: lectureID,
                split: calibration ? "calibration" : "evaluation",
                teacherID: teacherID,
                roomID: roomID,
                audioPath: audio.lastPathComponent,
                rttmPath: rttm.lastPathComponent,
                questionsPath: questions.lastPathComponent,
                candidatePath: candidateURL.lastPathComponent,
                durationSeconds: duration,
                studentQuestionCount: 10,
                teacherConsent: true,
                participantConsent: true
            )
        )
    }
    let encoder = JSONEncoder()
    let manifestURL = root.appendingPathComponent("manifest.jsonl")
    let manifestText = classroomRecords.map {
        String(decoding: try! encoder.encode($0), as: UTF8.self)
    }.joined(separator: "\n") + "\n"
    try! Data(manifestText.utf8).write(to: manifestURL)
    let evaluationHours = durations.reduce(0, +) / 3_600
    let validClassroom = CorpusStatus(
        classroom: .init(
            ready: true,
            manifest: manifestURL.lastPathComponent,
            evaluationLectures: 10,
            evaluationTeachers: 5,
            evaluationRooms: 3,
            evaluationHours: evaluationHours,
            evaluationStudentQuestions: 100,
            teacherDisjoint: true,
            roomDisjoint: true
        )
    )
    let validMissing = classroomPrerequisites(
        statusURL: root.appendingPathComponent("status.json"),
        status: validClassroom,
        gate: gate
    )
    precondition(validMissing.isEmpty, "\(validMissing)")
    let invalidCandidateURL = root.appendingPathComponent(
        classroomRecords[0].candidatePath
    )
    try! encoder.encode(
        CandidateFile(
            durationSeconds: 0,
            processingTimeSeconds: 0,
            segments: []
        )
    ).write(to: invalidCandidateURL)
    let invalidClassroom = validateClassroom(
        statusURL: root.appendingPathComponent("status.json"),
        status: validClassroom,
        gate: gate
    )
    precondition(invalidClassroom.calibration.isEmpty)
    precondition(
        invalidClassroom.missing.contains {
            $0.contains("candidate output is invalid or mismatched")
        }
    )
    precondition(missingClassroom.contains("classroom consent is not validated"))
    precondition(missingClassroom.contains("required classroom durations are missing"))
    print("teacher-rest-prototype: self-check passed")
}

private func usage() -> Never {
    FileHandle.standardError.write(Data("""
    Usage:
      teacher-rest-prototype self-check
      teacher-rest-prototype calibrate <gate.json> <manifest.json> <corpus-status.json> <thresholds.json>
      teacher-rest-prototype evaluate <gate.json> <manifest.json> <thresholds.json> <corpus-status.json> <gate-evidence.json> <report.json>
      teacher-rest-prototype analyze <gate.json> <candidate.json> <reference.rttm> <metadata.json> <teacher-threshold> <unknown-width> <result.json>

    """.utf8))
    exit(2)
}

private let arguments = CommandLine.arguments

do {
    guard arguments.count >= 2 else { usage() }
    switch arguments[1] {
    case "self-check":
        runSelfCheck()
    case "calibrate":
        guard arguments.count == 6 else { usage() }
        let gate = try loadJSON(Gate.self, from: URL(fileURLWithPath: arguments[2]))
        let manifest = URL(fileURLWithPath: arguments[3])
        let corpusURL = URL(fileURLWithPath: arguments[4])
        let corpus = try loadJSON(CorpusStatus.self, from: corpusURL)
        let classroom = validateClassroom(
            statusURL: corpusURL,
            status: corpus,
            gate: gate
        )
        let datasets = try loadDatasets(manifest, split: "calibration")
            + classroom.calibration
        guard !datasets.isEmpty else {
            throw NSError(
                domain: "TeacherRest",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "no calibration datasets"]
            )
        }
        var thresholds = calibrate(gate: gate, datasets: datasets)
        if !classroom.missing.isEmpty {
            thresholds = Thresholds(
                teacherSimilarity: thresholds.teacherSimilarity,
                othersSimilarity: thresholds.othersSimilarity,
                selectionStatus: "CLASSROOM_CALIBRATION_MISSING",
                calibrationMetrics: thresholds.calibrationMetrics
            )
        }
        try writeJSON(thresholds, to: URL(fileURLWithPath: arguments[5]))
    case "evaluate":
        guard arguments.count == 8 else { usage() }
        let gate = try loadJSON(Gate.self, from: URL(fileURLWithPath: arguments[2]))
        let manifestURL = URL(fileURLWithPath: arguments[3])
        let thresholds = try loadJSON(Thresholds.self, from: URL(fileURLWithPath: arguments[4]))
        let corpusURL = URL(fileURLWithPath: arguments[5])
        let corpus = try loadJSON(CorpusStatus.self, from: corpusURL)
        let evidence = try loadJSON(GateEvidence.self, from: URL(fileURLWithPath: arguments[6]))
        let amiDatasets = try loadDatasets(manifestURL, split: "evaluation")
        let classroom = validateClassroom(
            statusURL: corpusURL,
            status: corpus,
            gate: gate
        )
        let amiFiles = amiDatasets.map {
            analyze(
                $0,
                gate: gate,
                teacherThreshold: thresholds.teacherSimilarity,
                othersThreshold: thresholds.othersSimilarity
            )
        }
        let classroomFiles = classroom.evaluation.map {
            analyze(
                $0,
                gate: gate,
                teacherThreshold: thresholds.teacherSimilarity,
                othersThreshold: thresholds.othersSimilarity
            )
        }
        let amiMetrics = aggregate(amiFiles, datasets: amiDatasets)
        let classroomMetrics = classroom.evaluation.isEmpty
            ? nil
            : aggregate(classroomFiles, datasets: classroom.evaluation)
        let checks = evaluationChecks(
            amiMetrics: amiMetrics,
            classroomMetrics: classroomMetrics,
            evidence: evidence,
            gate: gate
        )
        let missing = classroom.missing
        let passed = thresholds.selectionStatus == "CALIBRATION_CONSTRAINTS_MET"
            && checks.allSatisfy(\.passed)
            && missing.isEmpty
        let report = EvaluationReport(
            decision: passed ? "PASS" : "FAIL",
            thresholds: thresholds,
            aggregate: amiMetrics,
            classroomAggregate: classroomMetrics,
            files: amiFiles + classroomFiles,
            checks: checks,
            classroomReady: missing.isEmpty,
            missingPrerequisites: missing
        )
        try writeJSON(report, to: URL(fileURLWithPath: arguments[7]))
        print(report.decision)
    case "analyze":
        guard arguments.count == 9,
              let teacher = Double(arguments[6]),
              let width = Double(arguments[7]) else { usage() }
        let gate = try loadJSON(Gate.self, from: URL(fileURLWithPath: arguments[2]))
        let dataset = Dataset(
            entry: .init(id: "single", split: "evaluation", candidatePath: "", referencePath: "", metadataPath: "", peakMemoryBytes: nil, modelBytes: nil, source: nil),
            candidate: try loadJSON(CandidateFile.self, from: URL(fileURLWithPath: arguments[3])),
            reference: try readRTTM(URL(fileURLWithPath: arguments[4])),
            metadata: try loadJSON(Metadata.self, from: URL(fileURLWithPath: arguments[5]))
        )
        try writeJSON(
            analyze(dataset, gate: gate, teacherThreshold: teacher, othersThreshold: teacher - width),
            to: URL(fileURLWithPath: arguments[8])
        )
    default:
        usage()
    }
} catch {
    FileHandle.standardError.write(Data("teacher-rest-prototype: \(error.localizedDescription)\n".utf8))
    exit(1)
}
