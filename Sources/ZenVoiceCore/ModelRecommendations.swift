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

public struct HardwareProfile: Equatable, Sendable {
    public let physicalMemoryBytes: UInt64
    public let logicalCoreCount: Int
    public let architecture: String
    public let availableModelStorageBytes: Int64

    public init(
        physicalMemoryBytes: UInt64,
        logicalCoreCount: Int,
        architecture: String,
        availableModelStorageBytes: Int64
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.logicalCoreCount = logicalCoreCount
        self.architecture = architecture
        self.availableModelStorageBytes = availableModelStorageBytes
    }

    public static func current(
        fileManager: FileManager = .default
    ) -> HardwareProfile {
        let directory = (try? VerifiedModelCatalog.modelsDirectory(
            fileManager: fileManager
        )) ?? fileManager.homeDirectoryForCurrentUser
        let available = (
            try? directory.resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey]
            ).volumeAvailableCapacityForImportantUsage
        ) ?? 0
        #if arch(arm64)
        let architecture = "Apple Silicon"
        #elseif arch(x86_64)
        let architecture = "Intel"
        #else
        let architecture = "Unknown"
        #endif
        return HardwareProfile(
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            logicalCoreCount: ProcessInfo.processInfo.processorCount,
            architecture: architecture,
            availableModelStorageBytes: available
        )
    }

    public var memoryGigabytes: Int {
        max(1, Int(physicalMemoryBytes / 1_073_741_824))
    }

    /// Apple Silicon decodes on the GPU through Metal, so a larger model costs
    /// far less time than the same model does on Intel. Model choice has to
    /// account for this — memory alone says nothing about how fast a Mac can
    /// actually transcribe.
    public var hasGPUAcceleratedTranscription: Bool {
        architecture == "Apple Silicon"
    }

    public var summary: String {
        "\(memoryGigabytes) GB memory • \(logicalCoreCount) cores • \(architecture)"
    }
}

public enum ModelRecommendationLevel: Equatable, Sendable {
    case recommended
    case supported
    case caution
    case insufficientStorage
}

public struct ModelRecommendation: Equatable, Sendable {
    public let level: ModelRecommendationLevel
    public let title: String
    public let rationale: String

    public init(
        level: ModelRecommendationLevel,
        title: String,
        rationale: String
    ) {
        self.level = level
        self.title = title
        self.rationale = rationale
    }
}

public enum ModelRecommendationEngine {
    /// The one model this Mac should use.
    ///
    /// Recommending by memory alone sent capable Apple Silicon Macs to Whisper
    /// Base. Turbo is multilingual, decodes on the GPU, and costs about a
    /// third of Medium's download, so on any Mac with a Metal path it is the
    /// right default.
    ///
    /// Measured on 24 real recordings, rather than asserted:
    ///
    ///     tiny.en      5.4%   100x real time
    ///     base.en      4.8%    63x
    ///     turbo        3.3%     9x    547 MB
    ///     medium.en    2.9%    10x    1.5 GB
    ///     medium       2.7%     9x    1.5 GB
    ///
    /// An earlier version of this comment claimed Turbo "matches Whisper
    /// Medium's accuracy". It does not — Medium is 0.6 points better, about a
    /// fifth of the remaining errors — but it costs three times the disk for
    /// the same speed, so Turbo remains the better default. The claim was
    /// simply never measured.
    public static func recommendedModelID(
        for profile: HardwareProfile,
        language: LanguageProfile = .english
    ) -> String {
        // Hinglish is decided by the language, not the hardware. Every general
        // model reaches it by transcribing Devanagari and romanizing, which
        // destroys the English half of the sentence: Turbo and Medium both
        // preserved 0 of the English words in the corpus, against 82 of 96
        // for the specialist. `document` comes back as डोक्यूमेंट.
        //
        // Recommending on hardware alone sent every Hinglish user to a model
        // that cannot do the one thing they chose the app for.
        if language == .hinglish {
            return "hindi2hinglish-apex"
        }
        // English on Apple Silicon defaults to Whisper Turbo, the most capable
        // open multilingual model available through whisper.cpp. Without GPU
        // transcription the same size model is too slow, so Intel and small-
        // memory Macs fall through to Small.
        if language == .english, profile.hasGPUAcceleratedTranscription {
            return "whisper-large-v3-turbo"
        }
        // No Metal path: model size translates directly into waiting, and Small
        // is the largest multilingual build that stays responsive. It is a
        // compromise rather than a tier — 35.5% word error rate overall, and
        // effectively European-languages-only.
        guard profile.hasGPUAcceleratedTranscription else {
            return "whisper-small-multilingual"
        }
        return profile.memoryGigabytes >= 8
            ? "whisper-large-v3-turbo"
            : "whisper-small-multilingual"
    }

    public static func recommendedModel(
        for profile: HardwareProfile,
        language: LanguageProfile = .english
    ) -> VerifiedModel? {
        VerifiedModelCatalog.model(
            id: recommendedModelID(for: profile, language: language)
        )
    }

    /// The tier containing the recommended model, so tier-level UI stays
    /// consistent with the model-level recommendation.
    public static func recommendedTier(
        for profile: HardwareProfile,
        language: LanguageProfile = .english
    ) -> ModelPerformanceTier {
        recommendedModel(for: profile, language: language)?.tier ?? .balanced
    }

    public static func recommendation(
        for model: VerifiedModel,
        profile: HardwareProfile,
        language: LanguageProfile = .english
    ) -> ModelRecommendation {
        let installationHeadroom = max(
            model.fileSizeBytes * 2,
            model.fileSizeBytes + 512 * 1_048_576
        )
        guard profile.availableModelStorageBytes >= installationHeadroom else {
            return ModelRecommendation(
                level: .insufficientStorage,
                title: "More storage needed",
                rationale:
                    "Keep at least \(formatted(installationHeadroom)) free for a safe download and installation."
            )
        }

        if model.id == recommendedModelID(
            for: profile,
            language: language
        ) {
            return ModelRecommendation(
                level: .recommended,
                title: "Recommended",
                rationale:
                    model.languageCapability == .hinglish
                    ? "Built for Hindi-English code-switching and Latin-script output."
                    : profile.hasGPUAcceleratedTranscription
                        ? "Best accuracy for its size on this Mac's GPU, and it handles every supported language."
                        : "The best accuracy this Mac can transcribe without a noticeable wait."
            )
        }

        // Large downloads that are not the recommendation are usually a worse
        // trade than the recommendation itself: same accuracy, several times
        // the disk.
        if model.fileSizeBytes > 1_000_000_000 {
            return ModelRecommendation(
                level: .caution,
                title: "Larger than needed",
                rationale:
                    "Whisper Turbo offers nearby accuracy in a fraction of the space; this remains available if you prefer it."
            )
        }
        if model.tier == .highAccuracy,
           !profile.hasGPUAcceleratedTranscription {
            return ModelRecommendation(
                level: .caution,
                title: "May feel slow",
                rationale:
                    "High Accuracy without GPU transcription can lag behind speech; manual override remains available."
            )
        }
        return ModelRecommendation(
            level: .supported,
            title: "Compatible",
            rationale:
                model.tier == .fast
                    ? "Prioritizes response time for short local dictation."
                    : "Offers a different speed and accuracy trade-off."
        )
    }

    private static func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

public struct ModelBenchmarkSample: Codable, Equatable, Sendable {
    public let modelID: String
    public let audioDurationSeconds: TimeInterval
    public let processingDurationSeconds: TimeInterval
    public let recordedAt: Date

    public init(
        modelID: String,
        audioDurationSeconds: TimeInterval,
        processingDurationSeconds: TimeInterval,
        recordedAt: Date = Date()
    ) {
        self.modelID = modelID
        self.audioDurationSeconds = audioDurationSeconds
        self.processingDurationSeconds = processingDurationSeconds
        self.recordedAt = recordedAt
    }

    public var realtimeFactor: Double {
        guard audioDurationSeconds > 0 else {
            return 0
        }
        return processingDurationSeconds / audioDurationSeconds
    }
}

public struct ModelBenchmarkSummary: Equatable, Sendable {
    public let modelID: String
    public let sampleCount: Int
    public let averageRealtimeFactor: Double
    public let averageProcessingDurationSeconds: TimeInterval
    public let lastRecordedAt: Date
}

public enum ModelBenchmarkStore {
    public static let preferenceKey = "ZenVoice.modelBenchmarks.v1"

    public static func record(
        modelID: String,
        audioDurationSeconds: TimeInterval,
        processingDurationSeconds: TimeInterval,
        recordedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        guard audioDurationSeconds > 0,
              processingDurationSeconds > 0,
              processingDurationSeconds.isFinite else {
            return
        }
        var samples = load(defaults: defaults)
        samples.append(
            ModelBenchmarkSample(
                modelID: modelID,
                audioDurationSeconds: audioDurationSeconds,
                processingDurationSeconds: processingDurationSeconds,
                recordedAt: recordedAt
            )
        )
        samples = Array(samples.suffix(50))
        if let data = try? JSONEncoder().encode(samples) {
            defaults.set(data, forKey: preferenceKey)
        }
    }

    public static func summary(
        for modelID: String,
        defaults: UserDefaults = .standard
    ) -> ModelBenchmarkSummary? {
        let samples = load(defaults: defaults).filter {
            $0.modelID == modelID
        }
        guard let last = samples.max(by: {
            $0.recordedAt < $1.recordedAt
        }) else {
            return nil
        }
        let totalAudio = samples.reduce(0) {
            $0 + $1.audioDurationSeconds
        }
        let totalProcessing = samples.reduce(0) {
            $0 + $1.processingDurationSeconds
        }
        return ModelBenchmarkSummary(
            modelID: modelID,
            sampleCount: samples.count,
            averageRealtimeFactor:
                totalAudio > 0 ? totalProcessing / totalAudio : 0,
            averageProcessingDurationSeconds:
                totalProcessing / Double(samples.count),
            lastRecordedAt: last.recordedAt
        )
    }

    public static func clear(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: preferenceKey)
    }

    private static func load(
        defaults: UserDefaults
    ) -> [ModelBenchmarkSample] {
        guard let data = defaults.data(forKey: preferenceKey),
              let samples = try? JSONDecoder().decode(
                [ModelBenchmarkSample].self,
                from: data
              ) else {
            return []
        }
        return samples
    }
}
