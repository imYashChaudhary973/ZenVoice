# Hinglish spelling personalization

ZenVoice keeps Hinglish Apex as the speech model and improves recurring
spellings with user-approved, local correction rules. It does not apply a
general English spell-checker to Romanized Hindi.

## Correct a spelling

1. Open **History**.
2. Open a saved dictation's `…` menu.
3. Select **Correct spelling…**.
4. Enter the spelling ZenVoice produced and the spelling you prefer.
5. Confirm the Hinglish-only scope and save.

The source and replacement are encrypted in the local vault. The preferred
term is supplied to Whisper on later Hinglish dictations, then the correction
engine applies exact or narrowly bounded matches after refinement. Suggestions
require explicit acceptance and are never learned silently.

Existing rules created before language scoping remain **All languages**. Their
scope is visible in **Voice Profile**.

## Private error corpus

Keep personal recordings outside source control. `PrivateBenchmarks/` is
ignored if a local corpus is temporarily placed inside the repository.

Collect 30–50 representative cases:

```text
~/ZenVoice-Hinglish-Spelling/
├── 001.wav
├── 001.txt
├── 001.raw.txt
├── 001.category.txt
└── ...
```

- `001.wav`: original recording.
- `001.txt`: preferred transcript.
- `001.raw.txt`: uncorrected Apex output.
- `001.category.txt`: one of `technical-term`, `name`,
  `romanized-hindi`, or `unexpected-script`.

Example:

```text
raw:       kal server ka bild verifai karna
preferred: kal server ka build verify karna
```

Do not commit these files: recordings and transcripts may contain private
speech.

## Replay and measure

Run the existing real-speech benchmark against the paired audio and preferred
transcripts. Put approved preferred terms in a local UTF-8 file, one term per
line, to measure Whisper prompt bias:

```bash
.build/release/ZenVoiceLanguageBench \
  --model "$HOME/Library/Application Support/ZenVoice/Models/ggml-hindi2hinglish-apex-q8_0.bin" \
  --suite hinglish \
  --corpus "$HOME/ZenVoice-Hinglish-Spelling" \
  --vocabulary "$HOME/ZenVoice-Hinglish-Spelling/preferred-terms.txt" \
  --limit 50 \
  --clean
```

Use the deterministic app harness for an individual end-to-end insertion:

```bash
ZENVOICE_E2E_AUDIO_FILE="$HOME/ZenVoice-Hinglish-Spelling/001.wav" \
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
swift run ZenVoice
```

Track:

- preferred English and name spellings preserved;
- no unexpected alphabetic script;
- no change to unrelated English or Romanized Hindi words;
- correction p50 and p95 latency;
- Apex loanword preservation against the existing Hinglish suites.

The storage regression check enforces exact replacements, language isolation,
conservative fuzzy controls, encrypted persistence, schema migration, and a
10 ms correction p95 ceiling.
