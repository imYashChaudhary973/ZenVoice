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

/// What one refinement mode did to one cohort of clips.
private struct StageOutcome {
    var score = Scoring.Result.zero
    var insertions = 0
    /// Times the meaning guard threw the candidate away.
    var rejections = 0
    /// Times the output differed from the input at all.
    var changed = 0
    var clipCount = 0
    var seconds: TimeInterval = 0
    /// Per-clip median refine time, so the reported figure is a typical
    /// dictation rather than a sum that a single slow sample can dominate.
    var durations: [TimeInterval] = []

    /// Median across clips, in milliseconds.
    var medianMilliseconds: Double {
        guard !durations.isEmpty else { return 0 }
        return durations.sorted()[durations.count / 2] * 1_000
    }
    /// Protected tokens altered, as "clip: token before→after".
    var violations: [String] = []

    var rejectionRate: Double {
        clipCount == 0 ? 0 : Double(rejections) / Double(clipCount)
    }
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

    // Pinned decode by default. The harness exists to detect changes, and it
    // cannot do that while its own output moves by more than a point of word
    // error rate between identical runs. Set ZENVOICE_ACCURACY_SAMPLED=1 to
    // measure the shipping configuration, temperature fallback included.
    let isReproducible = !flag("ZENVOICE_ACCURACY_SAMPLED")
    // Refine repeats per clip, for the latency median. Three is enough to
    // discard a single scheduling stall without tripling a full run.
    let latencyRepeats = Int(
        environment["ZENVOICE_REFINE_REPEATS"].flatMap(Int.init) ?? 3
    )
    let transcriber = WhisperTranscriber(
        configuration: configuration,
        isReproducible: isReproducible
    )

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

        // Two cohorts, scored separately.
        //
        // Pooling them was hiding the very thing this section exists to
        // measure. Three disfluent clips sat among twelve clean ones, and on
        // clean speech every mode scores identically because there is nothing
        // to fix — so a mode that did literally nothing still posted the same
        // improvement as one that worked, and the suite called it a pass.
        //
        // Split, each cohort carries its own half of the contract: refinement
        // must help where there is something to fix, and must not meddle where
        // there is not. Neither claim is checkable from the pooled average.
        let disfluentClips =
            (try? Fixtures.renderDisfluent(into: fixtureDirectory)) ?? []
        // Real recordings, from the same ZENVOICE_ACCURACY_CORPUS directory the
        // transcription section already reads, so one folder of wav+txt pairs
        // serves both. Synthesized and real speech stay in separate cohorts
        // rather than merged: they have different error distributions, and
        // averaging them would reintroduce exactly the dilution the split above
        // just removed.
        let corpusClips = environment["ZENVOICE_ACCURACY_CORPUS"]
            .map { URL(fileURLWithPath: $0) }
            .flatMap { try? Fixtures.corpus(at: $0) } ?? []
        var cohorts: [(
            name: String,
            clips: [Fixtures.Clip],
            claim: String,
            isSynthetic: Bool
        )] = [
            ("disfluent speech", disfluentClips, "refinement must help", true),
            ("clean speech", clips, "refinement must not meddle", true)
        ]
        if !corpusClips.isEmpty {
            cohorts.append(
                ("real dictation", corpusClips, "refinement must help", false)
            )
        }

        if localModelURL == nil {
            report("  local model stage skipped — no refinement model installed")
        }

        var cohortRaw: [String: Scoring.Result] = [:]
        var cohortStages: [String: [String: StageOutcome]] = [:]
        var unhandled: [String] = []

        for cohort in cohorts {
            var rawTotal = Scoring.Result.zero
            var outcomes: [String: StageOutcome] = [:]

            for clip in cohort.clips {
                let loaded = (try? Fixtures.samples(at: clip.url)) ?? []
                // Real recordings already carry their own room tone and level.
                // Degrading them would simulate a microphone on top of a
                // microphone.
                let samples = cohort.isSynthetic
                    ? Fixtures.degraded(loaded, gain: gain, noise: noise)
                    : loaded
                guard !samples.isEmpty else { continue }
                let raw = decode(samples)
                guard !raw.isEmpty else { continue }
                var clipChanged = false
                rawTotal = rawTotal + Scoring.wordErrorRate(
                    reference: clip.sentence.text,
                    hypothesis: raw
                )
                for (name, mode) in stages {
                    var outcome = outcomes[name] ?? StageOutcome()
                    // Repeat and take the median. A single sample was moving
                    // by 3x between identical runs, which is larger than any
                    // effect worth measuring; the transcript is fixed by this
                    // point, so the repeats differ only in machine load.
                    var samples: [TimeInterval] = []
                    var result = InstantRefineResult(text: raw, correctionCount: 0)
                    for _ in 0..<max(1, latencyRepeats) {
                        let attemptStart = Date()
                        result = coordinator.refine(
                            raw,
                            mode: mode,
                            languageCode: "en"
                        )
                        samples.append(
                            Date().timeIntervalSince(attemptStart)
                        )
                    }
                    outcome.durations.append(
                        samples.sorted()[samples.count / 2]
                    )
                    let refined = result.text
                    if result.wasRejected { outcome.rejections += 1 }
                    if refined != raw {
                        outcome.changed += 1
                        clipChanged = true
                    }
                    outcome.clipCount += 1
                    let score = Scoring.wordErrorRate(
                        reference: clip.sentence.text,
                        hypothesis: refined
                    )
                    outcome.score = outcome.score + score
                    outcome.insertions += score.insertions
                    for violation in SemanticSafety.violations(
                        raw: raw,
                        refined: refined
                    ) {
                        outcome.violations.append(
                            "\(clip.name): \(violation.description)"
                        )
                    }
                    outcomes[name] = outcome
                }

                // A disfluent clip that no mode altered is a disfluency the
                // product cannot see. This is the actionable list — the WER
                // delta says refinement helped, but not that it helped on
                // everything, and an average over eight clips can look healthy
                // while six of them pass through untouched.
                if !clipChanged, cohort.name != "clean speech" {
                    unhandled.append("\(clip.name): \(raw)")
                }
            }

            cohortRaw[cohort.name] = rawTotal
            cohortStages[cohort.name] = outcomes
        }

        for cohort in cohorts {
            guard let rawTotal = cohortRaw[cohort.name],
                  let outcomes = cohortStages[cohort.name] else { continue }
            let clipCount = outcomes.values.first?.clipCount ?? 0
            report(
                "  refinement — \(cohort.name)"
                    + " (\(clipCount) clips, \(cohort.claim))"
            )
            report("  " + String(repeating: "-", count: 60))
            report(
                "  "
                    + "raw transcript".padding(
                        toLength: 28, withPad: " ", startingAt: 0
                    )
                    + rawTotal.percentage.leftPadded(to: 7)
            )
            for (name, _) in stages {
                guard let outcome = outcomes[name] else { continue }
                let delta = (outcome.score.rate - rawTotal.rate) * 100
                report(
                    "  "
                        + "after \(name)".padding(
                            toLength: 28, withPad: " ", startingAt: 0
                        )
                        + outcome.score.percentage.leftPadded(to: 7)
                        + String(format: "%+9.1f pts", delta)
                        + String(format: "%5d ins", outcome.insertions)
                        + String(
                            format: "%5d changed, %d rejected (%.0f%%)",
                            outcome.changed,
                            outcome.rejections,
                            outcome.rejectionRate * 100
                        )
                        + String(
                            format: "%6.0f ms/clip",
                            outcome.medianMilliseconds
                        )
                )
            }
            report()
        }

        if !unhandled.isEmpty {
            report(
                "  disfluencies no mode touched"
                    + " (\(unhandled.count) clips passed through unchanged)"
            )
            report("  " + String(repeating: "-", count: 60))
            for clip in unhandled {
                report("    \(clip)")
            }
            report()
        }

        // ---- assertions ----

        // 1. Refinement must not make clean speech worse. Pre-existing.
        if let rawTotal = cohortRaw["clean speech"],
           let outcomes = cohortStages["clean speech"] {
            for (name, _) in stages {
                guard let outcome = outcomes[name] else { continue }
                let delta = (outcome.score.rate - rawTotal.rate) * 100
                if delta > 2.0 {
                    refinementFailures.append(
                        "\(name) raised word error rate on clean speech by "
                            + String(format: "%.1f", delta) + " points"
                    )
                }
            }
        }

        // 2. Refinement must never alter a negation or a quantity. Reported as
        // an absolute count, never a rate: one inverted sentence in a thousand
        // dictations is a product failure, and an average would bury it.
        report("  semantic safety (negations and quantities, must be zero)")
        report("  " + String(repeating: "-", count: 60))
        for (name, _) in stages {
            let violations = cohorts.compactMap {
                cohortStages[$0.name]?[name]?.violations
            }
            .flatMap(\.self)
            report(
                "  "
                    + name.padding(toLength: 28, withPad: " ", startingAt: 0)
                    + "\(violations.count) violations".leftPadded(to: 15)
            )
            for violation in violations.prefix(5) {
                report("      \(violation)")
            }
            if !violations.isEmpty {
                refinementFailures.append(
                    "\(name) altered \(violations.count) protected token(s): "
                        + violations.prefix(3).joined(separator: ", ")
                )
            }
        }
        report()

        // 3. Refinement must actually refine.
        //
        // The suite had no assertion in this direction at all: it failed only
        // when refinement made things worse, so deleting Instant Refine
        // entirely would have kept it green. That is the wrong shape of test
        // for a feature whose failure mode is silence, and it is why a mode
        // contributing 0.0 points shipped unnoticed.
        //
        // Opt-in for now, because it fails today by design — turning it on is
        // the definition of done for the guard work, not a CI break to absorb
        // before it starts. Enable with ZENVOICE_REFINE_STRICT=1.
        if let rawTotal = cohortRaw["disfluent speech"],
           let outcomes = cohortStages["disfluent speech"] {
            var advisories: [String] = []
            for (name, _) in stages {
                guard let outcome = outcomes[name] else { continue }
                let delta = (outcome.score.rate - rawTotal.rate) * 100
                if delta > -1.0 {
                    advisories.append(
                        "\(name) improved disfluent speech by only "
                            + String(format: "%.1f", -delta)
                            + " points (want 1.0+)"
                    )
                }
            }
            // A downloaded language model has to beat the regexes it runs on
            // top of, or it is 1.1 GB and a per-dictation stall for nothing.
            if let local = outcomes["local model"],
               let clean = outcomes["clean"] {
                let gain = (clean.score.rate - local.score.rate) * 100
                if gain < 0.5 {
                    advisories.append(
                        "local model beat clean by only "
                            + String(format: "%.1f", gain)
                            + " points — the guard is discarding "
                            + String(format: "%.0f%%", local.rejectionRate * 100)
                            + " of its output"
                    )
                }
            }
            if flag("ZENVOICE_REFINE_STRICT") {
                refinementFailures.append(contentsOf: advisories)
            } else if !advisories.isEmpty {
                report("  refinement shortfalls (advisory —"
                    + " set ZENVOICE_REFINE_STRICT=1 to enforce)")
                report("  " + String(repeating: "-", count: 60))
                for advisory in advisories {
                    report("    \(advisory)")
                }
                report()
            }
        }
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

    // ---- Hinglish loanword preservation ----
    //
    // The check above only asks whether Devanagari is gone. That is passed
    // equally by `kampyutara par kama kara raha hum` and by
    // `computer par kaam kar raha hoon`, so it cannot see the defect that
    // actually makes Hinglish unusable. This asks the question that can be
    // answered without a canonical spelling: did the English words come back as
    // English?
    // A metric that always returned zero would produce exactly the baseline
    // reported below, so it has to demonstrate it can tell the two apart before
    // its verdict on real audio means anything.
    let metricOnGoodOutput = Scoring.loanwordPreservation(
        expected: ["project", "status", "pull request"],
        hypothesis: "project ka status kya hai, pull request review kar do"
    )
    let metricOnBrokenOutput = Scoring.loanwordPreservation(
        expected: ["project", "status", "pull request"],
        hypothesis: "projekta ka stetasa kya hai, pula rikvesta raviyu kara do"
    )
    guard metricOnGoodOutput.preserved == 3, metricOnBrokenOutput.preserved == 0
    else {
        fail(
            "loanword metric is broken: natural Hinglish scored "
                + "\(metricOnGoodOutput.preserved)/3 and romanized mush scored "
                + "\(metricOnBrokenOutput.preserved)/3"
        )
    }

    var hinglishLoanwords = Scoring.LoanwordResult.zero
    // A Hinglish-native model is not `.multilingual`, and it is the one model
    // this section most needs to run against.
    let hinglishShouldRun = [.multilingual, .hinglish]
        .contains(configuration.modelLanguageCapability)
        && Fixtures.isHindiVoiceInstalled()
    if hinglishShouldRun,
       let hinglishClips = try? Fixtures.renderHinglish(into: fixtureDirectory),
       !hinglishClips.isEmpty {
        report("  Hinglish (English words surviving as English)")
        report("  " + String(repeating: "-", count: 60))
        for clip in hinglishClips {
            let samples = Fixtures.degraded(
                (try? Fixtures.samples(at: clip.url)) ?? [],
                gain: gain,
                noise: noise
            )
            guard !samples.isEmpty else { continue }

            let latin = (
                try? transcriber.transcribe(
                    samples: samples,
                    languageProfile: .hinglish
                )
            )?.finalTranscript ?? ""
            let loanwords = Scoring.loanwordPreservation(
                expected: clip.sentence.loanwords ?? [],
                hypothesis: latin
            )
            hinglishLoanwords = hinglishLoanwords + loanwords

            report(
                "  "
                    + clip.name.padding(toLength: 28, withPad: " ", startingAt: 0)
                    + "\(loanwords.preserved)/\(loanwords.total)".leftPadded(to: 7)
                    + loanwords.percentage.leftPadded(to: 8)
                    + (loanwords.lost.isEmpty
                        ? ""
                        : "   lost: " + loanwords.lost.joined(separator: ", "))
            )
            if isVerbose {
                report("      hinglish: \(latin.isEmpty ? "<empty>" : latin)")
            }
            if latin.isEmpty {
                hindiFailures.append(
                    "\(clip.name) produced no Hinglish transcript"
                )
            }
        }
        report("  " + String(repeating: "-", count: 60))
        report(
            "  "
                + "OVERALL".padding(toLength: 28, withPad: " ", startingAt: 0)
                + "\(hinglishLoanwords.preserved)/\(hinglishLoanwords.total)"
                    .leftPadded(to: 7)
                + hinglishLoanwords.percentage.leftPadded(to: 8)
        )
        report()
    }

    // The whole section sits behind optional rendering, so a fixture set that
    // quietly stopped producing clips would read as a clean run rather than as
    // lost coverage. Measured 2026-07-25 on Whisper Medium: 0/26. That zero is
    // the defect, not a harness fault — see docs/hinglish/05-update-2026-07.md.
    // The floor rises to a real threshold when a Hinglish-native model lands;
    // until then the only thing worth asserting is that it still measures.
    if hinglishShouldRun, hinglishLoanwords.total == 0 {
        hindiFailures.append(
            "Hinglish loanword coverage produced no measurements"
        )
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
