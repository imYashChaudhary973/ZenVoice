import FluidAudio
import Foundation
import ZenVoiceCore

/// Loading only.
///
/// Downloading deliberately does not live here. `UnifiedAsrManager.loadModels(to:)`
/// fetches from the model repository's default branch and honours FluidAudio's
/// `REGISTRY_URL`/`MODEL_REGISTRY_URL` overrides, which cannot express the
/// pinned revision this catalogue records. `VerifiedModelDownloader` fetches
/// each manifest file from that revision itself and verifies the bundle before
/// installing it; FluidAudio is then handed an already-verified local
/// directory through `loadModels(from:)`.
public enum ParakeetModelSupport {}

struct ParakeetDecodedResult {
    let text: String
    let segments: [TranscriptSegment]
}

final class ParakeetTranscriberEngine: @unchecked Sendable {
    private let manager: UnifiedAsrManager
    private let readiness: Task<Void, Error>

    init(modelURL: URL) {
        let manager = UnifiedAsrManager(encoderPrecision: .int8)
        self.manager = manager
        readiness = Task.detached(priority: .userInitiated) {
            try await manager.loadModels(from: modelURL)
            // CoreML performs expensive first-prediction setup. Do it while
            // ZenVoice launches so the user's first dictation stays fast.
            _ = try? await manager.transcribe(
                Array(repeating: 0, count: 16_000)
            )
        }
    }

    deinit {
        readiness.cancel()
    }

    /// Blocks until the model is loaded and CoreML's first prediction is done.
    ///
    /// `init` only *starts* that work — it spawns a detached task and returns
    /// immediately — so a caller that treats construction as readiness gets a
    /// transcriber that looks warm and is not. Measured on
    /// parakeet-unified-en-int8: first decode 8.41s, second decode 0.03s. All
    /// but 30 ms of that first call is this wait, and it lands on the user's
    /// first dictation unless something absorbs it beforehand.
    func warmUp() {
        _ = try? waitForAsync {
            try await self.readiness.value
        }
    }

    func transcribe(samples: [Float]) throws -> ParakeetDecodedResult {
        let output = try waitForAsync {
            try await self.readiness.value
            return try await self.manager.transcribeWithTimings(samples)
        }
        let segments = buildWordTimings(
            from: output.tokenTimings
        ).map {
            TranscriptSegment(
                text: $0.word,
                startSeconds: $0.startTime,
                endSeconds: $0.endTime
            )
        }
        return ParakeetDecodedResult(
            text: output.text,
            segments: segments
        )
    }

    private func waitForAsync<Value>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) throws -> Value {
        let semaphore = DispatchSemaphore(value: 0)
        let box = AsyncResultBox<Value>()
        Task.detached(priority: .userInitiated) {
            do {
                box.store(.success(try await operation()))
            } catch {
                box.store(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = box.load() else {
            throw WhisperTranscriber.TranscriptionError.runtimeFailed
        }
        return try result.get()
    }
}

private final class AsyncResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?

    func store(_ result: Result<Value, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<Value, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}
