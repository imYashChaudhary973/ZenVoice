# Diagnosis: Why Hinglish Output Is Bad

Every finding below is grounded in this codebase or in a measurement taken from
it. Where a claim is inference rather than measurement, it says so.

## The current pipeline

```
microphone
   ↓
AudioRecorder                     16 kHz mono Float32
   ↓
WhisperTranscriber.transcribe()   whisper.cpp, language = profile.inputLanguageCode
   ↓                              GREEDY sampling, no beam search
TranscriptCleaner.clean()         whitespace/filler tidy-up
   ↓
LocalTransliterator.latinScript() ICU .toLatin + .stripDiacritics   ← only for Hinglish
   ↓
InstantRefine (local Qwen 2.5)    guarded: may not change any word
   ↓
TextInserter                      paste into the focused app
```

The Hinglish profile is defined in
[`LanguageSupport.swift`](../../Sources/ZenVoiceCore/LanguageSupport.swift):

```swift
public static let hinglish = LanguageProfile(
    inputLanguageCode: "hi",
    outputMode: .latinScript
)
```

So Hinglish means: *ask Whisper for Hindi, get Devanagari, then mechanically
romanize it.* That decision is the origin of findings 1 and 2.

---

<a name="f1"></a>
## Finding 1 — Romanization cannot produce natural Hinglish (Critical)

`LocalTransliterator.latinScript` applies ICU's `.toLatin` transform, then strips
diacritics. Reproducing that logic exactly on ordinary Hinglish sentences:

| Whisper output (`language=hi`) | ZenVoice produces | What a person writes |
|---|---|---|
| क्या हाल है | `kya hala hai` | kya haal hai |
| मैं कंप्यूटर पर काम कर रहा हूँ | `maim kampyutara para kama kara raha hum` | main computer par kaam kar raha hoon |
| मुझे मीटिंग में जाना है | `mujhe mitinga mem jana hai` | mujhe meeting mein jaana hai |
| यह फ़ाइल डाउनलोड कर दो | `yaha fa'ila da'unaloda kara do` | yeh file download kar do |
| प्रोजेक्ट का स्टेटस क्या है | `projekta ka stetasa kya hai` | project ka status kya hai |
| थोड़ा सा वेट करो | `thora sa veta karo` | thoda sa wait karo |
| मैंने ईमेल भेज दिया | `mainne imela bheja diya` | maine email bhej diya |
| सर्वर डाउन है | `sarvara da'una hai` | server down hai |

**8 out of 8 differ from what a person would write.** Three separate defects are
visible:

**Schwa deletion is not modelled.** Written Hindi carries an inherent `a` after
most consonants that speakers do not pronounce. `काम` is *kaam*, not *kama*;
`हाल` is *haal*, not *hala*. ICU performs a faithful letter-by-letter
transliteration, which is the correct behaviour for a transliteration API and the
wrong behaviour for producing text people read. Schwa deletion in Hindi is
context-dependent and not solvable with a suffix-stripping rule.

**Diacritic stripping destroys vowel length.** `.toLatin` produces `hāla`; the
`.stripDiacritics` pass flattens `ā` to `a`. The distinction between long and
short vowels — which is what makes *haal* look right and *hal* look wrong — is
discarded on purpose by the code.

**ICU emits apostrophes at syllable boundaries.** `डाउन` becomes `da'una` and
`फ़ाइल` becomes `fa'ila`. These are artefacts of the transliteration standard and
never appear in written Hinglish.

> Reproduce: `docs/hinglish/tools/translit-check.swift` (see
> [04-evaluation.md](04-evaluation.md)).

---

<a name="f2"></a>
## Finding 2 — English loanwords are destroyed by the round-trip (Critical)

This is the most damaging defect, and it is structural rather than cosmetic.

When someone says *"project ka status kya hai"*, Whisper running with
`language=hi` writes the English words **in Devanagari**, because that is what a
Hindi language token instructs it to do. The romanizer then converts those
Devanagari spellings back to Latin with no knowledge that they were English to
begin with:

| Spoken | Whisper writes | ZenVoice returns |
|---|---|---|
| computer | कंप्यूटर | `kampyutara` |
| meeting | मीटिंग | `mitinga` |
| download | डाउनलोड | `da'unaloda` |
| status | स्टेटस | `stetasa` |
| server | सर्वर | `sarvara` |
| email | ईमेल | `imela` |

The English identity of the word is discarded at the Devanagari step and cannot
be recovered by any downstream transform, because `कंप्यूटर` and a genuinely
Hindi word are indistinguishable to a script converter.

This matters more than the schwa problem because Hinglish is overwhelmingly
English content words on Hindi grammatical scaffolding. A technical user
dictating about work will hit this in nearly every sentence.

**No improvement to the transliteration step can fix this.** The information is
already gone. It has to be fixed at the acoustic model, which is why
[03-plan.md](03-plan.md) recommends a Hinglish-native model over a better
romanizer.

---

<a name="f3"></a>
## Finding 3 — The active model is English-only (Critical)

From this machine's preferences:

```
ZenVoice.selectedModelID     whisper-medium-en
ZenVoice.languageProfile     {"outputMode":"spokenLanguage","inputLanguageCode":"en"}
```

`whisper-medium-en` is an English-only Whisper checkpoint. Those models are
trained solely on English and cannot emit Devanagari. The selected profile is
also plain English, not Hinglish.

So the Hinglish path described above **is not even active right now**. Hindi
speech is being fed to an English-only model, which will do the only thing it
can: hallucinate English words that sound vaguely similar. That alone explains
output quality far worse than any of the transliteration defects.

`LanguageProfile.isCompatible(with:)` already exists to express this constraint:

```swift
public func isCompatible(with capability: ModelLanguageCapability) -> Bool {
    capability == .multilingual || !requiresMultilingualModel
}
```

**Open question — needs verification:** whether that check is *enforced* at the
point where a profile and model are combined, or only used to filter UI lists. If
a user can end up with `hinglish` + an `.en` model, that combination should be
impossible to select and should self-correct on load.

---

<a name="f4"></a>
## Finding 4 — The model catalog stops at `medium` (High)

[`VerifiedModelCatalog.swift`](../../Sources/ZenVoiceCore/VerifiedModelCatalog.swift)
offers exactly six models: tiny, base, and medium, each in `.en` and multilingual
form. There is no `large-v3` and no `large-v3-turbo`.

Whisper's Hindi quality improves sharply with model size, and code-switched
speech is precisely the regime where smaller models degrade fastest. Capping at
`medium` leaves a large amount of accuracy unclaimed for a user willing to spend
the disk and latency. `large-v3-turbo` is particularly relevant: it is designed
for roughly 6× faster inference than `large-v3` at a small accuracy cost, which
suits a dictation tool where latency is felt directly.

---

<a name="f5"></a>
## Finding 5 — Greedy decoding, no fallback (High)

[`WhisperTranscriber.swift`](../../Sources/ZenVoiceRuntime/WhisperTranscriber.swift):

```swift
var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
```

Nothing else about decoding is configured. That means no beam search, and no use
of whisper.cpp's temperature-fallback machinery (`entropy_thold`,
`logprob_thold`, `temperature_inc`), which exists specifically to detect and
retry low-confidence or repetitive output.

Code-switched audio is exactly the case where the decoder is least certain — the
model is choosing between two languages' token distributions at every switch
point. Greedy decoding commits to the first guess at each step with no ability to
recover. Beam search plus temperature fallback is the standard mitigation and
requires no new model.

**Caveat:** beam search costs latency proportional to beam width. For a
push-to-talk dictation tool this is a real trade-off, not a free win, and should
be measured rather than assumed ([04-evaluation.md](04-evaluation.md)).

---

<a name="f6"></a>
## Finding 6 — The refinement guard forbids the repairs Hinglish needs (High)

ZenVoice already runs a local LLM (Qwen 2.5 1.5B) over transcripts. It cannot
help here, because of this guard in
[`VerifiedRefinementModelCatalog.swift`](../../Sources/ZenVoiceCore/VerifiedRefinementModelCatalog.swift):

```swift
guard tokens(in: candidate) == tokens(in: original) else {
    return nil
}
```

The candidate is rejected unless its word sequence is *identical* to the input,
case- and diacritic-insensitively. The model may only adjust punctuation,
capitalization and spacing.

This is a good guard for its actual job — it stops a small model from silently
dropping a "not" or rewriting meaning. But it means the existing refinement path
is structurally incapable of turning `kampyutara` into `computer`, since that is
by definition a word change.

A Hinglish normalization pass therefore cannot reuse this path. It needs a
separate route with its own, differently-shaped safety property — see
[03-plan.md](03-plan.md#phase-3).

The system prompt is also English-centric and says nothing about script or
code-mixing:

> "You clean speech transcripts. Keep the original language and meaning. Do not
> add, replace, translate, or invent words."

---

<a name="f7"></a>
## Finding 7 — There is no way to tell whether a change helped (High)

`ZenVoiceCoreChecks` covers language *profiles* — that `.hinglish` round-trips
through preferences, that it is incompatible with English-only models. Nothing
measures transcription *quality*.

There is no Hinglish audio fixture, no reference transcript, no WER computation,
and no regression gate. Every proposal in [03-plan.md](03-plan.md) is currently
unfalsifiable.

This is listed as High rather than Medium because it blocks everything else:
without it, a change that makes Hinglish worse is indistinguishable from one that
makes it better. [04-evaluation.md](04-evaluation.md) treats this as Phase 0.

---

<a name="f8"></a>
## Finding 8 — `initial_prompt` is not used for priming (Medium)

whisper.cpp accepts an `initial_prompt` that conditions decoding. ZenVoice passes
one, but only carries forward "next dictation context":

```swift
let contextPrompt = NextDictationContext.sanitized(initialPrompt ?? "")
```

Whisper's prompt conditioning is known to influence *style and script* of the
output, not just vocabulary. A prompt written in the target register is a
standard, zero-cost lever. It is Medium rather than High because prompt
conditioning is unreliable — Whisper may ignore it, and an overlong prompt can
displace audio context — so it is a cheap experiment, not a dependable fix.

---

## What is not wrong

Worth stating so effort is not wasted:

- **Audio capture.** 16 kHz mono Float32 is exactly Whisper's expected input, and
  the format is validated in `loadSamples`.
- **GPU/Metal.** `use_gpu` and `flash_attn` are both enabled.
- **`TranscriptCleaner`.** Small and script-agnostic; not implicated.
- **The Hinglish concept.** A dedicated profile that outputs Latin script is the
  right product decision. Only its implementation is wrong.

## Summary of causes, ranked by contribution

1. **Wrong model selected** (`whisper-medium-en`) — nothing else matters until fixed
2. **Devanagari→Latin architecture** destroys English loanwords irreversibly
3. **Schwa/diacritic handling** makes even pure Hindi words look misspelled
4. **Model size ceiling** at `medium`
5. **Greedy decoding** with no fallback on the hardest possible input
6. **No measurement**, so none of the above can be confirmed or tracked
