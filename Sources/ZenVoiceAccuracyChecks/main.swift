import Foundation
import ZenVoiceCore
import ZenVoiceRefinementRuntime
import ZenVoiceRuntime

// ZenVoiceAccuracyChecks — measures transcription accuracy instead of guessing
// at it.
//
// The harness renders deterministic speech fixtures, runs them through the same
// WhisperTranscriber the app uses, and reports Word Error Rate for two decode
// strategies:
//
//   whole    — the finished recording decoded in a single pass
//   segments — decoded in the pieces live dictation cuts at, then concatenated
//
// The gap between those two is the cost of segmented decoding. Keeping it
// visible is the point: it is what justified making the release path decode the
// whole recording, and it is what will catch a regression back to concatenated
// output.
//
// Environment:
//   ZENVOICE_MODEL_PATH        explicit model, otherwise the usual discovery
//   ZENVOICE_ACCURACY_GAIN     input gain applied before decoding (default 0.35)
//   ZENVOICE_ACCURACY_NOISE    noise floor added before decoding (default 0.004)
//   ZENVOICE_ACCURACY_CLEAN    set to 1 to measure studio-clean audio instead
//   ZENVOICE_ACCURACY_FIXTURES cache directory for rendered audio
//   ZENVOICE_ACCURACY_VERBOSE  set to 1 to print every hypothesis

private let environment = ProcessInfo.processInfo.environment

private func value(_ key: String, default fallback: Float) -> Float {
    environment[key].flatMap(Float.init) ?? fallback
}

private func flag(_ key: String) -> Bool {
    environment[key] == "1"
}

private func report(_ message: String = "") {
    print(message)
}

private func fail(_ message: String) -> Never {
    FileHandle.standardError.write(
        Data("ZenVoice accuracy checks failed: \(message)\n".utf8)
    )
    exit(1)
}

private func skip(_ message: String) -> Never {
    print("ZenVoice accuracy checks skipped: \(message)")
    exit(0)
}

private struct Totals {
    var whole = Scoring.Result.zero
    var segmented = Scoring.Result.zero
    var wholeSeconds: TimeInterval = 0
    var segmentedSeconds: TimeInterval = 0
    var segmentCount = 0
}

private extension String {
    func leftPadded(to width: Int) -> String {
        count >= width
            ? self
            : String(repeating: " ", count: width - count) + self
    }
}

/// Runs the measurement in its own scope so the Whisper context is released
/// before the process exits. Leaving it alive trips a Metal teardown assertion
/// inside ggml during static destruction.
private func measure() -> Bool {
    let configuration: ZenVoiceConfiguration
    do {
        configuration = try ZenVoiceConfiguration.discover(
            languageProfile: .english
        )
    } catch ZenVoiceConfiguration.ConfigurationError.modelMissing {
        skip(
            "install a verified model in Models or set ZENVOICE_MODEL_PATH."
        )
    } catch {
        fail(error.localizedDescription)
    }

    let fixtureDirectory = environment["ZENVOICE_ACCURACY_FIXTURES"]
        .map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "zenvoice-accuracy-fixtures",
                isDirectory: true
            )

    let clips: [Fixtures.Clip]
    do {
        clips = try Fixtures.render(into: fixtureDirectory)
    } catch {
        // A machine without usable speech synthesis cannot run the harness,
        // but that is an environment gap rather than an accuracy regression.
        skip(error.localizedDescription)
    }

    let isClean = flag("ZENVOICE_ACCURACY_CLEAN")
    let isVerbose = flag("ZENVOICE_ACCURACY_VERBOSE")
    let gain = isClean ? 1 : value("ZENVOICE_ACCURACY_GAIN", default: 0.35)
    let noise = isClean ? 0 : value("ZENVOICE_ACCURACY_NOISE", default: 0.004)

    let transcriber = WhisperTranscriber(configuration: configuration)

    func decode(_ samples: [Float]) -> String {
        (
            try? transcriber.transcribe(
                samples: samples,
                languageProfile: .english
            )
        )?.finalTranscript ?? ""
    }

    report()
    report("ZenVoice accuracy — model \(configuration.modelID)")
    report(
        isClean
            ? "input: studio clean"
            : String(format: "input: gain %.2f, noise floor %.3f", gain, noise)
    )
    report()
    report("  clip                          whole   segments   segments cost")
    report("  " + String(repeating: "-", count: 60))

    var totals = Totals()
    var emptyDecodes: [String] = []
    var refinementFailures: [String] = []

    for clip in clips {
        let samples = Fixtures.degraded(
            (try? Fixtures.samples(at: clip.url)) ?? [],
            gain: gain,
            noise: noise
        )
        guard !samples.isEmpty else {
            fail("fixture \(clip.name) produced no audio")
        }

        // Strategy 1: the finished recording, decoded once.
        let wholeStart = Date()
        let whole = decode(samples)
        totals.wholeSeconds += Date().timeIntervalSince(wholeStart)

        // Strategy 2: decoded in the pieces live dictation would cut at.
        let segments = LiveSegmentation.segments(of: samples)
        let segmentedStart = Date()
        let segmented = segments
            .map { decode(Array($0)) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        totals.segmentedSeconds += Date().timeIntervalSince(segmentedStart)
        totals.segmentCount += segments.count

        if whole.isEmpty || segmented.isEmpty {
            emptyDecodes.append(clip.name)
        }

        let wholeScore = Scoring.wordErrorRate(
            reference: clip.sentence.text,
            hypothesis: whole
        )
        let segmentedScore = Scoring.wordErrorRate(
            reference: clip.sentence.text,
            hypothesis: segmented
        )
        totals.whole = totals.whole + wholeScore
        totals.segmented = totals.segmented + segmentedScore

        report(
            "  "
                + clip.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                + wholeScore.percentage.leftPadded(to: 7)
                + segmentedScore.percentage.leftPadded(to: 11)
                + String(
                    format: "%+9.1f pts",
                    (segmentedScore.rate - wholeScore.rate) * 100
                )
                + "  \(segments.count) seg"
        )
        // A hypothesis that scores badly is far easier to act on when the text
        // is visible, so surface it rather than leaving a bare percentage.
        if isVerbose || wholeScore.rate > 0.5 || segmentedScore.rate > 0.5 {
            report("      whole:    \(whole.isEmpty ? "<empty>" : whole)")
            report(
                "      segments: \(segmented.isEmpty ? "<empty>" : segmented)"
            )
        }
    }

    report("  " + String(repeating: "-", count: 60))
    report(
        "  "
            + "OVERALL".padding(toLength: 28, withPad: " ", startingAt: 0)
            + totals.whole.percentage.leftPadded(to: 7)
            + totals.segmented.percentage.leftPadded(to: 11)
            + String(
                format: "%+9.1f pts",
                (totals.segmented.rate - totals.whole.rate) * 100
            )
    )
    report()
    report(
        String(
            format: "  decode time: whole %.2fs / %d clips, "
                + "segmented %.2fs / %d segments",
            totals.wholeSeconds,
            clips.count,
            totals.segmentedSeconds,
            totals.segmentCount
        )
    )
    report()

    // ---- refinement pipeline ----
    //
    // Transcription is only the first stage. What reaches the user has also
    // been through voice commands, Instant Refine, optionally a local language
    // model, and personal correction rules — any of which can make the text
    // worse. A language model rewriting a transcript is exactly where invented
    // content creeps in, so each stage is scored against the same reference the
    // raw transcript is.
    if !flag("ZENVOICE_ACCURACY_SKIP_REFINE") {
        let coordinator = LocalRefinementCoordinator()
        // Prefer an explicit path, otherwise use whichever verified refinement
        // model is actually installed.
        let installedRefinementModel = VerifiedRefinementModelCatalog.models
            .compactMap { model -> URL? in
                guard let url = try? VerifiedRefinementModelCatalog
                    .installedURL(for: model),
                    FileManager.default.fileExists(atPath: url.path) else {
                    return nil
                }
                return url
            }
            .first
        let localModelURL = environment["ZENVOICE_REFINEMENT_MODEL_PATH"]
            .map { URL(fileURLWithPath: $0) }
            ?? installedRefinementModel
        coordinator.update(modelURL: localModelURL)

        let stages: [(String, InstantRefineMode)] = localModelURL == nil
            ? [("clean", .clean), ("agent prompt", .agentPrompt)]
            : [
                ("clean", .clean),
                ("agent prompt", .agentPrompt),
                ("local model", .localModel)
            ]

        // Measured against disfluent speech, not the clean fixtures. On tidy
        // sentences there is nothing to refine, so every mode scores identically
        // and the test proves nothing. Hesitations and restarts are what
        // refinement exists for.
        let refinementClips =
            ((try? Fixtures.renderDisfluent(into: fixtureDirectory)) ?? [])
            + clips

        report("  refinement stages (disfluent speech + clean fixtures)")
        report("  " + String(repeating: "-", count: 60))
        if localModelURL == nil {
            report("  local model stage skipped — no refinement model installed")
        }

        var rawTotal = Scoring.Result.zero
        var stageTotals = [String: Scoring.Result]()
        var stageInsertions = [String: Int]()
        var stageRejections = [String: Int]()
        var stageChanged = [String: Int]()

        for clip in refinementClips {
            let samples = Fixtures.degraded(
                (try? Fixtures.samples(at: clip.url)) ?? [],
                gain: gain,
                noise: noise
            )
            guard !samples.isEmpty else { continue }
            let raw = decode(samples)
            guard !raw.isEmpty else { continue }
            rawTotal = rawTotal + Scoring.wordErrorRate(
                reference: clip.sentence.text,
                hypothesis: raw
            )
            for (name, mode) in stages {
                let outcome = coordinator.refine(
                    raw,
                    mode: mode,
                    languageCode: "en"
                )
                let refined = outcome.text
                if outcome.wasRejected {
                    stageRejections[name] = (stageRejections[name] ?? 0) + 1
                }
                if refined != raw {
                    stageChanged[name] = (stageChanged[name] ?? 0) + 1
                }
                let score = Scoring.wordErrorRate(
                    reference: clip.sentence.text,
                    hypothesis: refined
                )
                stageTotals[name] = (stageTotals[name] ?? .zero) + score
                stageInsertions[name] =
                    (stageInsertions[name] ?? 0) + score.insertions
            }
        }

        report(
            "  "
                + "raw transcript".padding(
                    toLength: 28, withPad: " ", startingAt: 0
                )
                + rawTotal.percentage.leftPadded(to: 7)
        )
        for (name, _) in stages {
            guard let score = stageTotals[name] else { continue }
            let delta = (score.rate - rawTotal.rate) * 100
            report(
                "  "
                    + "after \(name)".padding(
                        toLength: 28, withPad: " ", startingAt: 0
                    )
                    + score.percentage.leftPadded(to: 7)
                    + String(format: "%+9.1f pts", delta)
                    + String(format: "%5d ins", stageInsertions[name] ?? 0)
                    + String(
                        format: "%5d changed, %d rejected",
                        stageChanged[name] ?? 0,
                        stageRejections[name] ?? 0
                    )
            )
            // Refinement is meant to tidy text, not rewrite meaning. A stage
            // that makes the transcript measurably less like what was said is
            // costing the user accuracy for presentation.
            if delta > 2.0 {
                refinementFailures.append(
                    "\(name) refinement raised word error rate by "
                        + String(format: "%.1f", delta)
                        + " points"
                )
            }
        }
        report()
    }

    // ---- long form ----
    //
    // Past 30 seconds Whisper decodes in successive windows, conditioning each
    // on what it produced for the last. Word error rate alone hides the two
    // failures that causes, so insertions and repetition are reported directly.
    var longFormFailures: [String] = []
    if let longClips = try? Fixtures.renderLongForm(into: fixtureDirectory),
       !longClips.isEmpty {
        report("  long-form dictation (crosses the 30 s window boundary)")
        report("  " + String(repeating: "-", count: 60))
        for clip in longClips {
            let samples = Fixtures.degraded(
                (try? Fixtures.samples(at: clip.url)) ?? [],
                gain: gain,
                noise: noise
            )
            guard !samples.isEmpty else { continue }
            let seconds = Double(samples.count) / 16_000
            let text = decode(samples)
            let score = Scoring.wordErrorRate(
                reference: clip.sentence.text,
                hypothesis: text
            )
            let repetition = Scoring.repetitionRate(text)
            report(
                "  "
                    + String(format: "%.0fs audio", seconds)
                        .padding(toLength: 28, withPad: " ", startingAt: 0)
                    + score.percentage.leftPadded(to: 7)
                    + String(format: "%5d ins", score.insertions)
                    + String(format: "%7.1f%% repeat", repetition * 100)
            )
            if isVerbose {
                report("      \(text.isEmpty ? "<empty>" : text)")
            }
            // Invented words matter more than misheard ones here: the user may
            // never notice text they did not say.
            if score.insertionRate > 0.05 {
                longFormFailures.append(
                    "\(clip.name) invented \(score.insertions) words "
                        + "(\(String(format: "%.1f%%", score.insertionRate * 100)) of the reference)"
                )
            }
            if repetition > 0.10 {
                longFormFailures.append(
                    "\(clip.name) repeated "
                        + String(format: "%.1f%%", repetition * 100)
                        + " of its 5-grams — likely a decode loop"
                )
            }
        }
        report()
    }

    // ---- Hindi ----
    //
    // Exercises multilingual decoding and, separately, the transliteration path
    // that Hinglish output depends on. Skipped when the model is English-only
    // or the Hindi voice is not installed.
    var hindiFailures: [String] = []
    if configuration.modelLanguageCapability == .multilingual,
       Fixtures.isHindiVoiceInstalled(),
       let hindiClips = try? Fixtures.renderHindi(into: fixtureDirectory),
       !hindiClips.isEmpty {
        report("  Hindi (multilingual decode + transliteration)")
        report("  " + String(repeating: "-", count: 60))
        let devanagari = LanguageProfile(
            inputLanguageCode: "hi",
            outputMode: .spokenLanguage
        )
        for clip in hindiClips {
            let samples = Fixtures.degraded(
                (try? Fixtures.samples(at: clip.url)) ?? [],
                gain: gain,
                noise: noise
            )
            guard !samples.isEmpty else { continue }

            let native = (
                try? transcriber.transcribe(
                    samples: samples,
                    languageProfile: devanagari
                )
            )?.finalTranscript ?? ""
            let score = Scoring.wordErrorRate(
                reference: clip.sentence.text,
                hypothesis: native
            )

            // Hinglish output has no single correct spelling, so asserting a
            // word error rate against it would be measuring taste. What can be
            // checked is the property the feature promises: nothing is left in
            // the original script.
            let latin = (
                try? transcriber.transcribe(
                    samples: samples,
                    languageProfile: .hinglish
                )
            )?.finalTranscript ?? ""
            let leftoverDevanagari = latin.unicodeScalars.contains {
                (0x0900...0x097F).contains(Int($0.value))
            }

            report(
                "  "
                    + clip.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                    + score.percentage.leftPadded(to: 7)
                    + (leftoverDevanagari ? "   NOT transliterated" : "   latin ok")
            )
            if isVerbose {
                report("      devanagari: \(native.isEmpty ? "<empty>" : native)")
                report("      hinglish:   \(latin.isEmpty ? "<empty>" : latin)")
            }
            if native.isEmpty {
                hindiFailures.append("\(clip.name) produced no Hindi transcript")
            }
            if leftoverDevanagari {
                hindiFailures.append(
                    "\(clip.name) left Devanagari in Hinglish output: \(latin)"
                )
            }
        }
        report()
    }

    // ---- real speech ----
    //
    // Optional operator-supplied recordings. Every synthetic number above is
    // optimistic; this is where that gets checked against a real voice.
    if let corpusPath = environment["ZENVOICE_ACCURACY_CORPUS"] {
        let corpus = (
            try? Fixtures.corpus(at: URL(fileURLWithPath: corpusPath))
        ) ?? []
        if corpus.isEmpty {
            report("  real-speech corpus at \(corpusPath): no wav+txt pairs found")
            report()
        } else {
            report("  real speech (\(corpus.count) recordings)")
            report("  " + String(repeating: "-", count: 60))
            var corpusWhole = Scoring.Result.zero
            var corpusSegmented = Scoring.Result.zero
            for clip in corpus {
                // Real recordings arrive at whatever level they were captured
                // at, so the synthetic degradation is deliberately not applied.
                let samples = (try? Fixtures.samples(at: clip.url)) ?? []
                guard !samples.isEmpty else {
                    report("  \(clip.name): could not read audio")
                    continue
                }
                let whole = decode(samples)
                let segments = LiveSegmentation.segments(of: samples)
                let segmented = segments
                    .map { decode(Array($0)) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                let wholeScore = Scoring.wordErrorRate(
                    reference: clip.sentence.text,
                    hypothesis: whole
                )
                let segmentedScore = Scoring.wordErrorRate(
                    reference: clip.sentence.text,
                    hypothesis: segmented
                )
                corpusWhole = corpusWhole + wholeScore
                corpusSegmented = corpusSegmented + segmentedScore
                report(
                    "  "
                        + clip.name.padding(
                            toLength: 28, withPad: " ", startingAt: 0
                        )
                        + wholeScore.percentage.leftPadded(to: 7)
                        + segmentedScore.percentage.leftPadded(to: 11)
                        + String(
                            format: "%+9.1f pts",
                            (segmentedScore.rate - wholeScore.rate) * 100
                        )
                        + "  \(segments.count) seg"
                )
                if isVerbose {
                    report("      whole:    \(whole)")
                    report("      segments: \(segmented)")
                }
            }
            report(
                "  "
                    + "REAL SPEECH".padding(
                        toLength: 28, withPad: " ", startingAt: 0
                    )
                    + corpusWhole.percentage.leftPadded(to: 7)
                    + corpusSegmented.percentage.leftPadded(to: 11)
                    + String(
                        format: "%+9.1f pts",
                        (corpusSegmented.rate - corpusWhole.rate) * 100
                    )
            )
            report()
        }
    }

    // The fixtures deliberately contain pauses. If segmentation never fires,
    // the two strategies are the same measurement and the harness is not
    // testing what it claims to.
    guard totals.segmentCount > clips.count else {
        fail(
            "segmentation never fired — \(totals.segmentCount) segments across "
                + "\(clips.count) clips means the two strategies are identical"
        )
    }

    guard emptyDecodes.isEmpty else {
        fail("no transcript produced for: \(emptyDecodes.joined(separator: ", "))")
    }

    guard refinementFailures.isEmpty else {
        fail(
            "refinement degraded the transcript: "
                + refinementFailures.joined(separator: "; ")
        )
    }

    guard hindiFailures.isEmpty else {
        fail("Hindi coverage failed: \(hindiFailures.joined(separator: "; "))")
    }

    guard longFormFailures.isEmpty else {
        fail(
            "long-form dictation degraded: "
                + longFormFailures.joined(separator: "; ")
        )
    }

    // Segmented decoding may tie with whole-recording decoding on easy audio,
    // but it must never beat it — if it does, the premise behind decoding the
    // whole recording on release no longer holds and needs re-justifying.
    guard totals.segmented.rate >= totals.whole.rate - 0.005 else {
        fail(
            "segmented decoding scored better than whole-recording decoding "
                + "(\(totals.segmented.percentage) vs "
                + "\(totals.whole.percentage)) — re-examine the release path"
        )
    }

    // A catastrophic decode regression should break the build rather than
    // quietly degrade dictation. The bound is deliberately generous: fixtures
    // are synthetic and the installed model varies by machine.
    guard totals.whole.rate <= 0.35 else {
        fail(
            "whole-recording word error rate \(totals.whole.percentage) "
                + "exceeds the 35% ceiling — transcription is badly broken"
        )
    }

    report(
        "ZenVoiceAccuracyChecks passed "
            + "(whole \(totals.whole.percentage), "
            + "segmented \(totals.segmented.percentage), "
            + "segmentation cost "
            + String(
                format: "%.1f pts).",
                (totals.segmented.rate - totals.whole.rate) * 100
            )
    )
    return true
}

exit(measure() ? 0 : 1)
