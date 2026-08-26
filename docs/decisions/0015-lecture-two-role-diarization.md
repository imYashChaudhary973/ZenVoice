# ADR 0015 — Lecture v2: Local Two-Role Diarization

## Status

**Accepted — 2026-08-22.** Phase 0 privacy and identity contract locked.
No diarization feature code in this change.

## Context

Lecture Capture v1 stores one local WAV, one immutable original transcript, and
an optional summary (ADR 0014). It does not know who spoke. Lecture v2 adds a
derived, timestamped view that separates one confirmed main speaker from all
other speakers without turning ZenVoice into an identity or attendance system.

Diarization answers **which anonymous voice spoke when**. It does not identify a
person. Speaking for the longest time is evidence that a cluster may be the main
speaker; it is not evidence that the person is the teacher.

This ADR locks the privacy and identity boundary. It does not select a model or
runtime. A later benchmark must earn that implementation decision.

## Decision

### 1. The original transcript remains immutable

Diarization must never edit, replace, reorder, merge, or relabel
`originalTranscript`. The current encrypted original remains the source record
of what the selected speech engine produced.

Diarization creates a separate derived view containing timed speaker turns. It
may be regenerated or deleted without changing the original transcript, audio,
or summary.

### 2. Speaker turns are per-lecture technical data

A speaker turn contains only what the role view needs:

- start and end time,
- a per-lecture anonymous cluster identifier,
- aligned transcript text,
- confidence sufficient to decide whether to show `Unknown speaker`.

Clusters are displayed as `Speaker 1`, `Speaker 2`, and so on by default.
Cluster numbers have meaning only inside that lecture. ZenVoice must not match,
merge, or learn a person across lectures.

Low-confidence or overlapping alignment is labelled `Unknown speaker`; ZenVoice
does not guess or coerce it into another role. Initial and regeneration failures
follow the rules in **Failure behavior** below.

### 3. Diarization is local only

The WAV is processed on this Mac by the selected local diarization runtime. At
the application-payload layer, the only lecture content that may leave this Mac
is the opted-in Cloud-summary fixed prompt and the allowed role-labelled text in
§6. Provider credentials and protocol-required HTTP/TLS metadata are not
lecture content.

Audio and all diarization-derived data — including audio chunks, speaker
embeddings, cluster centroids, confidence scores, model features, cluster
identifiers, counts, logs, and crash or telemetry payloads — must not leave the
Mac by any route.

Speaker embeddings are biometric-adjacent technical data:

- they are scoped to one lecture,
- they are never used to identify a person,
- they are never compared across lectures,
- they remain in memory where the runtime permits,
- any implementation-required retry cache is encrypted with the lecture vault
  key,
- relaunch never turns cached embeddings into a persistent voiceprint.

No diarization vendor, hosted speaker service, analytics endpoint, licensing
callback carrying lecture data, or ZenVoice proxy is added by v2.

### 4. Main speaker is a suggestion, not an identity

ZenVoice may omit a Main-speaker suggestion. If it presents one, it must select
only the unique longest-speaking cluster after that cluster passes a dominance
threshold fixed by the Phase 1 benchmark. Ties and below-threshold results
produce no suggestion.

A suggestion must not write `Teacher`, change the fixed lecture-summary
instruction, be serialized as confirmation, or be treated as identity. It may
determine only the unconfirmed `Main speaker` / `Others` prefixes in an allowed
summary payload.

### 5. Teacher requires explicit per-lecture confirmation

`Teacher` appears only after the user explicitly confirms a cluster for that
lecture. The user may instead choose another cluster or keep the lecture
anonymous.

Confirmation stores only the chosen per-lecture cluster identifier. It does not
store a name or reusable voiceprint. The user may change or revoke confirmation;
that relabels only the derived role view.

After confirmation:

- the confirmed cluster is labelled `Teacher`,
- every other confidently attributed cluster collapses into `Students`,
- low-confidence or overlapping turns remain `Unknown speaker`.

Before confirmation, if a qualifying Main-speaker suggestion exists, the
two-role view uses `Main speaker` and `Others`, with low-confidence turns kept as
`Unknown speaker`. If no cluster qualifies, the local view retains `Speaker n`
labels and ZenVoice does not create an unconfirmed two-role Cloud summary.

### 6. Cloud summary receives role-labelled text only

The optional summary keeps ADR 0011 and ADR 0014's existing opt-in, BYO-key
Cloud gate. It uses the existing Cloud transport only.

The application payload may contain only:

- the fixed lecture-summary prompt,
- utterance text prefixed with confirmed `Teacher` / `Students`, unconfirmed
  `Main speaker` / `Others`, or `Unknown speaker`.

The payload must not contain audio, embeddings, cluster identifiers, confidence
scores, speaker counts, lecture title, file paths, engine metadata, other
lectures, or device identifiers. `Unknown speaker` text may inform the general
outline but is excluded from role-specific claims and question extraction; it
must not be coerced into `Students` or `Others`.

Questions are extracted from `Students` / `Others` text into a separate summary
section. The provider must use transcript evidence only: no student names, no
invented speakers, and no claim that a question was answered unless the supplied
text contains an answer.

A timeout or provider error is treated as potentially received by the provider.
It leaves the original transcript, role view, and prior summary untouched.
Provider retention and deletion remain governed by ADR 0011 and the provider's
terms; ZenVoice must not claim to recall remotely retained request or response
data without provider confirmation.

### 7. Delete removes the whole local lecture boundary

Deleting a lecture removes every ZenVoice-controlled local artifact derived
from it, including:

- the local WAV and temporary audio chunks,
- encrypted original transcript and encrypted summary,
- timed turns, alignment text, and teacher confirmation,
- diarization status, confidence metadata, failed or partial outputs,
- encrypted retry caches and persisted embedding or model-feature caches,
- work files and app-controlled crash-recovery artifacts.

In-memory embeddings and decoder state are released when processing ends,
cancels, fails, or the lecture is deleted. If removal is partial, ZenVoice keeps
only a visible `Deletion failed` record with an actionable Retry; it does not
restore or expose artifacts already removed and does not report success until
all listed local artifacts are gone.

Lecture deletion cannot recall a Cloud request or response retained by a
provider. Dictation History is a separate store and is never touched.

## Failure behavior

- No suitable local runtime: diarization remains unavailable; v1 lecture capture
  and transcription continue to work.
- Initial diarization failure: discard partial turns and alignment; keep the WAV
  and immutable original; create neither a final role view nor a new
  role-labelled summary; show Retry.
- Regeneration failure: discard only the failed attempt and keep the last
  successful role view and prior summary unchanged. Any required retry cache
  remains encrypted under §3 and is removed by lecture deletion.
- Unknown or overlapping voice: label `Unknown speaker`, never force a role.
- No teacher confirmation: never call anyone Teacher. Without a qualifying Main
  speaker, retain `Speaker n` labels and disable the two-role Cloud summary.
- Cloud failure: keep every local artifact unchanged, show the provider error,
  and disclose that the provider may already have received the request.
- Delete failure: retain a `Deletion failed` record and Retry until all
  ZenVoice-controlled local artifacts are gone.

## Out of scope for v2

- Named speaker identification or asking ZenVoice to infer a person's name
- Reusable teacher or student voiceprints across lectures
- Attendance, participation scoring, or student analytics
- Face recognition, camera, or video processing
- Live diarization while recording
- Cloud diarization or uploading audio / embeddings
- Automatically treating the longest-speaking person as Teacher
- Named student labels; confidently attributed non-teacher clusters collapse
  to Students / Others, while low-confidence turns remain Unknown speaker
- Zoom, Google Meet, Microsoft Teams, or system-audio capture
- Editing or replacing the immutable original transcript
- Choosing a diarization model or adding a runtime before the benchmark gate

## Consequences

- Lecture v1 remains fully usable when diarization is unavailable or fails.
- The role view is derived and disposable; the immutable original remains the
  audit trail.
- Teacher confirmation costs one explicit interaction. That cost prevents a
  probabilistic cluster from becoming a false identity claim.
- Two roles intentionally discard individual-student identity. That is the
  privacy feature and the product scope, not a limitation to work around.
- Implementation phases start only after this ADR is Accepted and a local engine
  passes the benchmark gate.

## Related decisions

- ADR 0001 — Local data and model governance
- ADR 0002 — Default local history and private capture
- ADR 0010 — Audio History
- ADR 0011 — Cloud AI Enhancement
- ADR 0014 — Lecture Capture v1
