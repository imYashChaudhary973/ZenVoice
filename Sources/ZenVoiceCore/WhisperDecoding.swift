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

/// How aggressively the decoder should search for a better transcript.
public enum WhisperDecoding {
    /// Greedy decoding commits to the most likely token at every step and never
    /// reconsiders. Beam search keeps several candidate transcripts alive and
    /// picks whichever reads best overall, so an early wrong guess can still be
    /// corrected.
    ///
    /// That safety net is worth roughly three points of word error rate on
    /// Whisper Base, and nothing measurable on Medium or Turbo — those models
    /// are confident enough that the alternatives it explores are identical, so
    /// the extra decode time buys nothing. It is therefore paid for only where
    /// it pays back.
    public static let beamSize: Int32 = 5

    /// Tiny and Base fall below this; Small and everything larger sit above it.
    ///
    /// The ceiling looks like a crude proxy for "is this model confident
    /// enough", and it was reasonable to expect it to misclassify
    /// Whisper-Hindi2Hinglish-Apex: 874 MB puts it far above the line, yet it
    /// decodes an under-represented language where alternatives should be
    /// worth exploring. Measured, and the proxy holds anyway:
    ///
    ///     greedy       English 16.8%   loanwords 21/26   long-form clean
    ///     beam size 5  English 15.5%   loanwords 21/26   invents 5 words
    ///
    /// Beam search bought 1.3 points of English word error rate, nothing at all
    /// on the metric Apex exists for, and started fabricating — enough to trip
    /// the harness's 5% insertion ceiling on long-form. Invented text is the
    /// worst failure a dictation tool has, because the user may never notice
    /// words they did not say. Not worth 1.3 points.
    public static let beamSearchSizeCeilingBytes: Int64 = 300_000_000

    public static func usesBeamSearch(modelFileSizeBytes: Int64) -> Bool {
        modelFileSizeBytes > 0
            && modelFileSizeBytes < beamSearchSizeCeilingBytes
    }

    /// How long decoding may run, as a multiple of the recording's own length.
    ///
    /// Decoding is normally far faster than real time — Whisper Turbo runs at
    /// about nine times, Tiny at a hundred — so a decode that takes twice the
    /// audio's duration is not slow, it is stuck. Measured: seventy-three
    /// seconds of code-switched Hindi ran for fifteen minutes under Turbo
    /// before being abandoned, because the decoder loops and runs to its token
    /// limit on every window.
    ///
    /// Set high enough that an unaccelerated Intel Mac running a large model
    /// never trips it, and low enough that the user is not left staring at a
    /// frozen app.
    public static let decodeTimeoutMultiple: Double = 2

    /// Floor for the deadline, so a two-second utterance still gets a workable
    /// budget including model load.
    public static let minimumDecodeTimeoutSeconds: TimeInterval = 15

    public static func decodeDeadline(
        audioSeconds: TimeInterval
    ) -> TimeInterval {
        max(
            minimumDecodeTimeoutSeconds,
            audioSeconds * decodeTimeoutMultiple
        )
    }

    /// Silence prepended to every recording before decoding.
    ///
    /// Push-to-talk gives Whisper no lead-in: the user presses the key and
    /// starts talking, so speech begins in the opening milliseconds of the
    /// buffer. Some models drop the first word outright when that happens.
    /// Measured on Whisper-Hindi2Hinglish-Apex with the same clip, and the
    /// first word is simply gone:
    ///
    ///     no padding    "Ka status kya hai? Mainne email bhej diya."
    ///     0.5 s padding "Project ka status kya hai? Mainne email bhej diya."
    ///
    /// The word error rate on that clip halves, 22.2% to 11.1%.
    ///
    /// This is free. whisper.cpp pads every input out to its 30-second window
    /// regardless, so half a second of leading silence costs no extra decode
    /// time — it only moves where the speech sits inside a window that was
    /// going to be filled anyway.
    public static let leadInSilenceSeconds = 0.5

    public static func withLeadInSilence(
        _ samples: [Float],
        sampleRate: Double = 16_000
    ) -> [Float] {
        guard !samples.isEmpty else {
            return samples
        }
        let padding = Int(leadInSilenceSeconds * sampleRate)
        return [Float](repeating: 0, count: padding) + samples
    }

    /// Why `audio_ctx` is left alone.
    ///
    /// whisper pads every input out to a 30-second window and runs the encoder
    /// across all 1500 of its positions regardless of what was said, so a
    /// four-second dictation pays the same encoder cost as a twenty-nine second
    /// one. Since dictation is overwhelmingly short, most of that work encodes
    /// silence, and `whisper_full_params.audio_ctx` exists to truncate it. The
    /// saving is real and large. It was measured, on the accuracy harness's
    /// twelve clips under whisper-large-v3-turbo, scaling the window to the
    /// audio with 50% headroom above what the speech occupied:
    ///
    ///     decode time   whole 10.90s -> 6.44s      41% faster
    ///                   segmented 27.96s -> 10.28s  63% faster
    ///
    /// And it destroys the transcript:
    ///
    ///     synthetic whole      3.0% -> 24.2% word error rate
    ///     synthetic segmented  3.4% -> 125.6%
    ///     clean speech         3.0% -> 29.3%, 59 insertions
    ///     Hinglish loanwords   4/26 -> 0/26
    ///     Hindi                transliteration dropped entirely
    ///
    /// The failure is the decoder looping: it cross-attends to an encoding that
    /// stops before the utterance does and repeats the last thing it is sure
    /// of, emitting "and returns unauthorized instead of a server error" six
    /// times, or degenerating into "-e-d-e-d-e-d". Fabricated text is the worst
    /// output a dictation tool has, because the user may never notice words
    /// they did not say — the same reasoning that ruled out beam search above,
    /// at far greater cost here.
    ///
    /// Flash attention was the obvious suspect, since it has historically
    /// interacted badly with a reduced context. It is not the cause: with
    /// `flash_attn` off the repetition is cleaner but no less severe, reaching
    /// 218% and 520% word error rate on individual clips. The model simply
    /// requires the window it was trained on.
    ///
    /// Anyone reaching for this again should expect to pay for the speed in
    /// invented words, and should re-run `ZenVoiceAccuracyChecks` before
    /// believing otherwise.
    public static let audioContextIsModelDefault = true
}
