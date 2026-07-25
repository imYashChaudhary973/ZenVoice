import Foundation
import ZenVoiceCore
import ZenVoiceRefinementRuntime

// RefineLab — three ways of using a small local model, measured against each
// other rather than argued about.
//
// The shipping design asked the model to read a transcript and emit the edits
// itself. It contributed 0.0 points on every variation tried, because that
// shape of question needs open-ended judgement, position arithmetic and format
// discipline at once, and a 1.5B model is weak at all three together.
//
// These strategies keep the judgement and remove everything else. Deterministic
// rules propose candidate deletions — cheap, deliberately over-eager — and the
// model only decides which proposals are right. It never chooses what to look
// at, so it cannot invent, and the worst it can do is approve or refuse a
// deletion the rules already bounded.
//
//   scorer    asks which of two texts reads more naturally, from one forward
//             pass over each. No instructions, no generated text.
//   verifier  asks a yes/no question per candidate, answered by reading two
//             logits. No generation either.
//   oracle    cheats: it accepts a candidate only if it genuinely lowers word
//             error rate against the reference. Not shippable — it is the
//             ceiling. If a perfect judge cannot add much, no real model can,
//             and that answers whether fine-tuning is worth starting.

enum RefineLab {
    /// Counts of what the scorer actually asked the model, so the reported
    /// cost is not a median dominated by clips that never called it.
    struct Telemetry {
        var candidates = 0
        var modelCalls = 0
        var modelSeconds: TimeInterval = 0

        mutating func reset() {
            self = Telemetry()
        }
    }

    nonisolated(unsafe) static var telemetry = Telemetry()

    /// Words of context kept either side of a candidate when scoring it.
    ///
    /// Wide enough to carry the grammar the judgement depends on — "on Tuesday
    /// actually Wednesday" needs the words around it to read as a correction —
    /// and narrow enough that the cost per check does not grow with the
    /// dictation.
    static let windowRadius = 8

    /// How the scorer's cost grows with dictation length.
    ///
    /// The question this exists to answer: the scorer scores the *whole*
    /// transcript once per candidate, and candidates grow with length, so cost
    /// plausibly grows with the square of it. That is the same failure the
    /// edit-script redesign removed, in a new disguise, and it would sink the
    /// approach on long dictation.
    ///
    /// Text-only, so it needs no audio and no Whisper — the curve is a
    /// property of the scorer, not of transcription.
    static func latencyProbe(
        refiner: LocalTextRefiner,
        margin: Double
    ) -> [(words: Int, candidates: Int, calls: Int, milliseconds: Double)] {
        // One unit is a plausible sentence carrying a correction cue and a
        // hedge, so candidate count scales with length the way real dictation
        // would.
        let unit =
            "We should ship the beta on Thursday actually Friday "
            + "and the API just returns a cached response."
        return [1, 2, 4, 8, 16].map { repeats in
            let transcript = Array(repeating: unit, count: repeats)
                .joined(separator: " ")
            telemetry.reset()
            let started = Date()
            _ = scorer(transcript, refiner: refiner, margin: margin)
            let elapsed = Date().timeIntervalSince(started) * 1_000
            return (
                words: LocalRefinementPrompt.words(in: transcript).count,
                candidates: telemetry.candidates,
                calls: telemetry.modelCalls,
                milliseconds: elapsed
            )
        }
    }

    /// A contiguous span the rules suspect is disfluent.
    struct Candidate {
        let range: Range<Int>
        let reason: String

        func applied(to words: [String]) -> [String] {
            var result = words
            result.removeSubrange(range)
            return result
        }
    }

    /// Cues that mark the speaker replacing what they just said. The words
    /// before the cue are the abandoned version.
    private static let correctionCues: Set<String> = [
        "actually", "sorry", "rather", "instead"
    ]

    /// Words that are usually filler but are ordinary English often enough
    /// that a rule cannot decide alone. Exactly the judgement the model is for.
    private static let hedges: Set<String> = [
        "like", "basically", "literally", "honestly", "obviously",
        "essentially", "seriously", "totally", "really", "just", "so",
        "well", "anyway", "right"
    ]

    private static func normalized(_ word: String) -> String {
        word.lowercased().components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).joined()
    }

    /// Over-proposes on purpose. Precision is the model's job; this only has
    /// to avoid missing things, and never to propose removing a negation or a
    /// quantity.
    static func candidates(in words: [String]) -> [Candidate] {
        var found: [Candidate] = []

        for (index, word) in words.enumerated() {
            let token = normalized(word)

            // "on Tuesday actually Wednesday" — drop the abandoned version
            // together with its cue. Widths of one to three cover most
            // spoken corrections.
            if correctionCues.contains(token) {
                for width in 1...3 where index - width >= 0 {
                    let range = (index - width)..<(index + 1)
                    guard range.lowerBound >= 0 else { continue }
                    found.append(
                        Candidate(range: range, reason: "correction")
                    )
                }
            }

            if hedges.contains(token) {
                found.append(
                    Candidate(
                        range: index..<(index + 1),
                        reason: "hedge"
                    )
                )
            }
        }

        // Never propose removing meaning. The guard would refuse it anyway;
        // proposing it would only waste a model call and risk an approval.
        return found.filter { candidate in
            words[candidate.range].allSatisfy {
                !ProtectedTokens.isProtected($0)
            }
        }
    }

    /// Applies non-overlapping accepted candidates, best-scoring first.
    private static func apply(
        _ accepted: [(Candidate, Double)],
        to words: [String]
    ) -> String {
        var taken = Set<Int>()
        var chosen: [Candidate] = []
        for (candidate, _) in accepted.sorted(by: { $0.1 > $1.1 }) {
            guard !candidate.range.contains(where: taken.contains) else {
                continue
            }
            candidate.range.forEach { taken.insert($0) }
            chosen.append(candidate)
        }
        guard !chosen.isEmpty else {
            return words.joined(separator: " ")
        }
        return words.enumerated()
            .filter { !taken.contains($0.offset) }
            .map(\.element)
            .joined(separator: " ")
    }

    // MARK: idea 1 — the model as a scorer

    /// Keeps a deletion when removing it makes the sentence read more
    /// naturally by at least `margin`.
    ///
    /// The margin matters: near-zero differences are noise, and a language
    /// model finds almost any shorter text slightly more likely, so a
    /// threshold of zero would delete indiscriminately.
    static func scorer(
        _ transcript: String,
        refiner: LocalTextRefiner,
        margin: Double
    ) -> String {
        let words = LocalRefinementPrompt.words(in: transcript)
        let candidates = candidates(in: words)
        telemetry.candidates += candidates.count
        guard !candidates.isEmpty else {
            return transcript
        }

        var accepted: [(Candidate, Double)] = []
        for candidate in candidates {
            // Score a window around the candidate rather than the whole
            // transcript.
            //
            // Scoring the whole text per candidate made cost grow with the
            // square of dictation length — measured at 1.4 s for 17 words and
            // 5.7 minutes for 272 — because both the number of candidates and
            // the cost of each scoring pass grow together. That is the same
            // failure the edit-script redesign removed, wearing a new hat.
            //
            // Whether "Tuesday actually" is a correction is settled by the
            // words either side of it; a sentence three paragraphs later has
            // no bearing. Bounding the context makes each check a fixed cost
            // and the total linear in the number of candidates.
            let lower = max(0, candidate.range.lowerBound - windowRadius)
            let upper = min(
                words.count,
                candidate.range.upperBound + windowRadius
            )
            let window = Array(words[lower..<upper])
            let localStart = candidate.range.lowerBound - lower
            let localEnd = candidate.range.upperBound - lower
            let localRange = localStart..<localEnd
            var without = window
            without.removeSubrange(localRange)
            guard !without.isEmpty else { continue }

            let callStart = Date()
            guard let withSpan = try? refiner.logLikelihood(
                of: window.joined(separator: " ")
            ),
            let withoutSpan = try? refiner.logLikelihood(
                of: without.joined(separator: " ")
            ) else {
                continue
            }
            telemetry.modelCalls += 2
            telemetry.modelSeconds += Date().timeIntervalSince(callStart)

            let gain = withoutSpan - withSpan
            if gain > margin {
                accepted.append((candidate, gain))
            }
        }
        return apply(accepted, to: words)
    }

    // MARK: idea 2 — the model as a yes/no verifier

    static func verifier(
        _ transcript: String,
        refiner: LocalTextRefiner,
        threshold: Double
    ) -> String {
        let words = LocalRefinementPrompt.words(in: transcript)
        let candidates = candidates(in: words)
        guard !candidates.isEmpty else {
            return transcript
        }
        var accepted: [(Candidate, Double)] = []
        for candidate in candidates {
            let span = words[candidate.range].joined(separator: " ")
            let prompt = """
            <|im_start|>system
            You judge speech transcripts. Answer only yes or no.<|im_end|>
            <|im_start|>user
            Transcript: "\(transcript)"
            Is "\(span)" a filler or an abandoned false start that should be deleted, rather than words the speaker meant to keep?<|im_end|>
            <|im_start|>assistant
            """
            guard let probability = try? refiner.choiceProbability(
                prompt: prompt,
                preferred: "yes",
                alternative: "no"
            ) else {
                continue
            }
            if probability > threshold {
                accepted.append((candidate, probability))
            }
        }
        return apply(accepted, to: words)
    }

    // MARK: idea 3 proxy — the ceiling

    /// Accepts a candidate only when it actually lowers word error rate
    /// against the reference.
    ///
    /// This is cheating and cannot ship — it reads the answer key. Its value
    /// is as an upper bound: it is what a flawless judge would score, so it
    /// caps every strategy above and tells us whether a better model is worth
    /// chasing at all.
    static func oracle(
        _ transcript: String,
        reference: String
    ) -> String {
        let words = LocalRefinementPrompt.words(in: transcript)
        let candidates = candidates(in: words)
        guard !candidates.isEmpty else {
            return transcript
        }
        let baseline = Scoring.wordErrorRate(
            reference: reference,
            hypothesis: transcript
        ).distance
        var accepted: [(Candidate, Double)] = []
        for candidate in candidates {
            let edited = candidate.applied(to: words)
                .joined(separator: " ")
            let distance = Scoring.wordErrorRate(
                reference: reference,
                hypothesis: edited
            ).distance
            if distance < baseline {
                accepted.append((candidate, Double(baseline - distance)))
            }
        }
        return apply(accepted, to: words)
    }
}
