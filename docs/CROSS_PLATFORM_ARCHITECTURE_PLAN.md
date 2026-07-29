# ZenVoice Cross-Platform Architecture and Delivery Plan

- Status: Approved architecture; XP0 platform assumptions pending approval
- Date: 2026-07-29
- Decision: [ADR 0003](decisions/0003-cross-platform-rust-core-and-native-adapters.md)
- Existing architecture: [Architecture](ARCHITECTURE.md)
- Existing delivery sequence: [Build Order](BUILD_ORDER.md)
- Privacy baseline: [Privacy](PRIVACY.md)
- Model evidence baseline:
  [Language and Model Benchmark](LANGUAGE_MODEL_BENCHMARK_2026-07-26.md)

## 1. Purpose

This document defines how ZenVoice will expand from a native macOS application
to Apple silicon Mac, Intel Mac, iOS, Android, Windows, and Linux without
discarding the working macOS product or weakening its local-first privacy
contract.

The long-term architecture is:

```text
Native platform application
    │
    ├── UI, audio, permissions, shortcuts, insertion, secure key storage
    │
    ▼
Versioned ZenVoice FFI
    │
    ▼
Shared Rust product core
    │
    ├── deterministic transcript behavior
    ├── dictation lifecycle
    ├── model governance and recommendations
    ├── encrypted-storage policy and portable schema
    └── runtime session orchestration
    │
    ▼
Narrow internal C boundary
    │
    ▼
Pinned whisper.cpp
    │
    └── benchmarked platform-specific acceleration or CPU fallback
```

This is an incremental migration plan, not authorization for an immediate
rewrite.

## 2. Outcomes

The program succeeds when:

1. one reviewed Rust implementation owns each migrated platform-independent
   behavior;
2. the macOS application remains usable and releasable during every migration
   phase;
3. each native application observes the same transcript, language, model,
   storage, privacy, and recovery contracts where the operating system permits
   them;
4. normal recording, transcription, refinement, storage, and delivery need no
   cloud service, account, analytics endpoint, or remote text processor;
5. every advertised platform passes real-device accuracy, latency, memory,
   security, privacy, accessibility, lifecycle, packaging, and distribution
   gates; and
6. capability differences are documented rather than hidden behind a false
   promise of feature parity.

## 3. Non-Goals

The cross-platform program does not include:

- cloud transcription or cloud refinement;
- accounts, login, remote sync, or cross-device history;
- telemetry or behavioral analytics;
- a browser application;
- an immediate replacement of SwiftUI on macOS;
- identical UI layouts on every device;
- identical input behavior where an operating system prohibits it;
- arbitrary third-party model execution;
- automatic model promotion from model-card claims;
- a plug-in marketplace;
- support for every Linux distribution or desktop environment in the first
  Linux release;
- 32-bit desktop operating systems; or
- public release before the existing legal, signing, notarization, store, and
  manual QA decisions are complete.

Any later proposal for these items needs its own product decision, privacy
review, threat model, and delivery plan.

## 4. Operating Principles

### 4.1 Preserve the working product

- The current Swift application remains the macOS source of truth until a
  migrated path passes parity and platform QA.
- Each migration must be reversible with a build-time or internal
  implementation switch until the new path is accepted.
- No milestone combines a core-language migration with an unrelated redesign.
- Existing M0–M17 evidence remains historical evidence; cross-platform work
  does not retroactively change its status.

### 4.2 Share behavior, not operating-system assumptions

Shared code owns deterministic product rules. Native code owns operating-system
interactions.

The core may decide that a dictation is ready for insertion. It must not assume
that every platform can insert it. The platform adapter reports whether it
inserted, copied, committed through an input method, or failed.

### 4.3 Fail closed at every trust boundary

- Unknown model metadata is rejected.
- Invalid FFI input is rejected before allocation or side effects.
- An unavailable secure key store disables encrypted persistence rather than
  writing plaintext.
- A permission error falls back only to an explicitly safe capability, such as
  Copy, and never silently expands access.
- A runtime panic or C error terminates the affected session without exposing
  stale pointers or corrupting the vault.

### 4.4 Evidence before platform claims

Source support, simulator support, physical-device support, packaged builds,
and public-release readiness are different states and must be reported
separately.

## 5. Capability Contract

### 5.1 Capability levels

| Level | Meaning |
| --- | --- |
| Core-capable | The Rust core and pinned runtime build and pass deterministic checks. |
| App-capable | A native app completes record → transcribe → refine → result locally. |
| Integration-capable | The platform can deliver text to another application through a documented path. |
| Device-verified | Required flows pass on declared physical hardware and OS versions. |
| Distribution-verified | The exact signed package passes store or direct-distribution gates. |
| Supported | Device and distribution evidence are complete and published accurately. |

No platform is called supported at an earlier level.

### 5.2 Initial platform contract

| Platform | Primary experience | Text delivery | Initial architecture target |
| --- | --- | --- | --- |
| macOS Apple silicon | Menu-bar desktop dictation | Accessibility paste, clipboard fallback | Existing SwiftUI/AppKit shell |
| macOS Intel | Same as Apple silicon with hardware-appropriate models | Accessibility paste, clipboard fallback | Universal macOS application |
| Windows | Tray desktop dictation | Native insertion where permitted, clipboard fallback | Native Windows shell over Rust core |
| Linux | Desktop dictation on declared environments | Portal/native path where available, clipboard fallback | GTK/Rust shell or approved thin desktop shell |
| Android | ZenVoice voice input method plus settings app | `InputConnection.commitText` | Kotlin/Compose app and `InputMethodService` |
| iOS | In-app local recorder, editor, History, Copy, and Share | Explicit Copy/Share; optional insertion of pre-produced text | SwiftUI containing app |

### 5.3 Explicit platform limitations

#### iOS

- A third-party custom keyboard extension cannot directly access the
  microphone.
- ZenVoice must not market system-wide live voice-keyboard parity on iOS.
- The containing app may record, transcribe, refine, save, copy, and share.
- An optional keyboard extension may insert text already available through an
  approved app-group flow only after a separate privacy and extension-memory
  review.

#### Android

- The voice keyboard must detect password and sensitive input types.
- It must not store surrounding text from the target application.
- Private Dictation behavior must be available directly from the IME.
- The containing app and IME must use an explicit, minimal shared-data
  contract.

#### Windows

- Text injection into higher-integrity processes can fail.
- The clipboard fallback is part of the supported contract, not an error
  hidden from the user.
- Administrator privileges must not be requested merely to bypass normal
  integrity isolation.

#### Linux

- Wayland, X11, desktop environment, compositor, portal implementation, and
  packaging format affect global shortcuts and text insertion.
- The first release supports a declared matrix rather than “all Linux.”
- Clipboard delivery is the guaranteed baseline when direct insertion is
  unavailable.

## 6. Target Repository Structure

The migration should converge on this structure:

```text
.
├── apps/
│   ├── apple/
│   │   ├── macos/                 Existing SwiftUI/AppKit application
│   │   └── ios/                   SwiftUI containing application
│   ├── android/                   Kotlin/Compose app and IME
│   ├── windows/                   Native Windows shell
│   └── linux/                     Declared Linux desktop shell
├── crates/
│   ├── zenvoice-domain/           Pure deterministic product behavior
│   ├── zenvoice-lifecycle/        Platform-neutral session state machine
│   ├── zenvoice-models/           Catalogue, verification, recommendations
│   ├── zenvoice-runtime/          Safe orchestration over whisper.cpp
│   ├── zenvoice-storage/          Portable schema and encryption policy
│   ├── zenvoice-ffi/              UniFFI and stable C exports
│   └── zenvoice-test-support/     Fixtures, fake adapters, parity helpers
├── native/
│   └── whisper/                   Pinned source/build definitions and patches
├── fixtures/
│   ├── transcript-parity/
│   ├── lifecycle/
│   ├── storage-migrations/
│   └── audio/                     Redistributable or generated fixtures only
├── platform/
│   ├── apple/
│   ├── android/
│   ├── windows/
│   └── linux/
├── Scripts/
├── docs/
└── Package.swift                 Retained during the Swift migration
```

This structure is a destination. Files move only when a milestone needs the
new boundary; there is no preliminary mass rename.

## 7. Module Responsibilities

### 7.1 `zenvoice-domain`

Owns:

- transcript normalization and cleanup;
- meaning-preserving Instant Refine rules and guards;
- spoken structure and local voice-command interpretation;
- personal correction matching and language scoping;
- language profiles and output-mode validation;
- application-profile policy expressed with platform-neutral identifiers;
- model recommendation policy using normalized hardware facts;
- share-summary eligibility and privacy-safe aggregate types; and
- serializable value types used at FFI boundaries.

Must not import or call:

- operating-system UI frameworks;
- clipboard or synthetic-input APIs;
- microphone APIs;
- key stores;
- file pickers;
- HTTP clients; or
- raw `whisper.cpp` bindings.

### 7.2 `zenvoice-lifecycle`

Owns the authoritative session state machine:

```text
idle
  → preparing
  → listening
  → stopping
  → transcribing
  → refining
  → persisting
  → delivering
  → success | error | cancelled
  → idle
```

Requirements:

- invalid transitions are rejected;
- a session identifier scopes every command and event;
- stale completion events cannot mutate a newer session;
- cancellation is idempotent;
- privacy changes can revoke persistence for in-flight work;
- delivery records `inserted`, `committed`, `copiedOnly`, or `failed`;
- recoverable partial text remains distinguishable from a completed result;
  and
- no transcript text is included in diagnostic event descriptions.

### 7.3 `zenvoice-models`

Owns:

- model manifest schema;
- publisher, source, pinned revision, licence, attribution, format, size, and
  SHA-256 requirements;
- platform and architecture compatibility;
- language capability;
- minimum RAM and storage requirements;
- download-state transitions;
- partial-file cleanup and atomic installation;
- model selection validation; and
- content-free local benchmark summaries.

The model layer treats weights as untrusted data. It never executes downloaded
scripts, shared libraries, or repository code.

### 7.4 `zenvoice-runtime`

Owns:

- the narrow unsafe wrapper over the pinned `whisper.cpp` C API;
- model-context creation and destruction;
- per-session language, translation, prompt, and decoding configuration;
- bounded audio ingestion;
- serialized access to a retained model context;
- cancellation and deadline handling;
- conversion into safe Rust result types;
- backend capability reporting; and
- deterministic cleanup after errors or panic containment.

The runtime does not own microphone permission or device selection.

### 7.5 `zenvoice-storage`

Owns:

- a versioned SQLite schema;
- record and correction-rule serialization;
- field-bound authenticated encryption;
- migrations;
- recovery expiry;
- key rotation and cryptographic Delete All;
- local insight queries over decrypted-in-process records;
- transactional lifecycle updates; and
- storage-invariant checks.

The host provides an opaque vault key through a `SecureKeyProvider`. The Rust
core never writes a raw vault key to preferences, logs, the database, or a
model directory.

### 7.6 `zenvoice-ffi`

Owns the public binary contract used by native applications.

Requirements:

- every exported type is explicitly versioned or backward-compatible;
- no raw pointers representing long-lived objects, borrowed strings,
  Rust-specific collections, or C++ objects cross the public boundary;
- pointer-bearing C byte-buffer structs are the only exception and have
  explicit length, ownership, and ZenVoice release functions;
- byte buffers have explicit ownership and length;
- all errors map to documented, non-sensitive error codes;
- panics are caught before crossing FFI;
- callbacks are coarse-grained and safe to dispatch onto the host UI thread;
- cancellation handles are idempotent;
- long-running calls never block the platform main thread; and
- compatibility tests load the produced artifact from each host language.

UniFFI is the preferred Swift/Kotlin binding generator. A stable C ABI is used
where generated bindings are unsuitable.

### 7.7 FFI protocol specification

XP3 must commit an FFI specification before the pilot becomes a production
dependency. The specification includes:

#### Version negotiation

- The binary exports a stable `zenvoice_ffi_abi_version()` symbol.
- The host passes its minimum and maximum supported ABI versions during
  initialization.
- Initialization fails with `incompatibleVersion` before creating state when
  the ranges do not overlap.
- The Rust crate version, FFI ABI version, storage schema version, model
  catalogue version, and `whisper.cpp` revision are separate reported values.
- UniFFI, binding-generator, Rust, and host integration versions are pinned in
  the build manifest.

#### Handles and ownership

- Public C functions use integer-sized opaque handles, never addresses exposed
  as host-language objects.
- Handles include generation protection so a stale handle cannot refer to a
  newly allocated session.
- The core owns every object behind a handle until an idempotent
  `release(handle)` succeeds.
- A released, unknown, or wrong-type handle returns a documented error without
  dereferencing memory.
- Buffers returned through the C ABI include pointer, length, capacity, and
  allocator identity internally and are released only through the matching
  exported ZenVoice free function.
- UniFFI-managed values follow the pinned generator's ownership rules and
  receive integration tests after every generator update.

#### Calls, callbacks, and threads

- Exported calls document whether they are immediate, blocking worker calls,
  or asynchronous.
- Blocking inference is never invoked on the host main thread.
- Callbacks carry a core instance, session identifier, and monotonically
  increasing event sequence.
- Hosts can unregister callbacks; teardown waits for or invalidates queued
  callbacks before releasing host state.
- Callback re-entry into the same mutable core operation is rejected unless
  the operation is explicitly documented as re-entrant.
- Callbacks arrive on a Rust worker thread; the host binding dispatches UI work
  onto the native UI thread.

#### Errors and panic containment

- The C ABI returns a stable numeric error code and an optional bounded,
  sanitized diagnostic message.
- Host bindings map codes into typed native errors.
- Rust panics are caught at every exported boundary.
- A panic invalidates the affected operation or instance according to the
  specification; execution never continues through possibly poisoned state.
- C/C++ exceptions are not allowed to cross the `whisper.cpp` C boundary.

#### Compatibility policy

- Additive fields use defaults or explicit capability checks.
- Removing or changing the meaning of an exported operation requires a new ABI
  major version.
- Release packages support the ABI they were built with; dynamic substitution
  of an arbitrary newer core library is not supported.
- CI loads the release-mode artifact from Swift, Kotlin, the Windows host
  language, and the Linux host before an ABI change is accepted.

## 8. Platform Adapter Contracts

The exact host-language shape may differ, but each platform must implement the
same semantic contracts.

### 8.1 Audio capture

```text
listInputs() -> inputs
requestPermission() -> permission state
startCapture(session, input, format) -> capture handle
stopCapture(handle) -> bounded audio source
cancelCapture(handle)
observeLevels(handle) -> content-free level samples
```

Rules:

- produce mono PCM normalized to the runtime's reviewed format;
- keep waveform levels content-free;
- never send one FFI call per audio sample;
- use bounded chunks, a ring buffer, or a finalized local file;
- handle device disconnection explicitly;
- delete temporary audio according to the established lifecycle; and
- keep Audio Doctor separate from History.

### 8.2 Secure key provider

| Platform | Initial provider |
| --- | --- |
| macOS/iOS | Keychain |
| Android | Android Keystore-backed key protection |
| Windows | DPAPI or approved Windows credential protection |
| Linux | Secret Service-compatible keyring on the declared desktop |

If secure storage is unavailable, encrypted History is unavailable. ZenVoice
must not silently fall back to a plaintext key file.

### 8.3 Text delivery

```text
captureTarget() -> opaque target identity
canDeliver(target, context) -> capability
deliver(text, target) -> inserted | committed | copiedOnly | failed
copy(text) -> result
```

Rules:

- the target identity is captured when dictation starts;
- secure or password fields default to the safest behavior;
- focus changes cannot redirect commit-on-pause silently;
- clipboard fallback is visible;
- clipboard contents are never logged; and
- surrounding application text is not collected.

### 8.4 Shortcut and trigger adapter

The host owns shortcut registration because key naming, reserved shortcuts,
permissions, IME behavior, and hold events differ.

The core receives semantic actions:

- toggle dictation;
- begin hold dictation;
- end hold dictation;
- cancel;
- paste or commit last result; and
- toggle Private Dictation.

### 8.5 Application context

The platform may provide only:

- stable local application identifier;
- display name;
- whether the target is a secure field;
- broad delivery capability; and
- user-configured profile mapping.

It must not provide window titles, browser URLs, document contents,
surrounding text, recipients, or location.

### 8.6 Secure-field behavior

Secure-field handling is a product rule, not an adapter preference.

| Target state | Capture | Transcribe/refine | History/learning | Clipboard | Direct delivery | Recovery |
| --- | --- | --- | --- | --- | --- | --- |
| Known non-secure | Allowed after normal user trigger | Allowed locally | Follow normal or Private Dictation setting | Allowed as visible fallback | Allowed when permission and target lock pass | Follow normal policy |
| Known password/secure | Reject before capture | Not started | Forbidden | Forbidden | Forbidden | Forbidden |
| Becomes secure during session | Stop and cancel | Discard any unfinished result | Forbidden | Forbidden | Forbidden | Delete session audio and partial record |
| Sensitivity unavailable | Allowed only under the platform's documented normal contract | Allowed locally | Follow normal or Private Dictation setting | Allowed only as an explicit visible action/fallback | No commit-on-pause; final delivery requires the platform's normal target check | Follow normal policy |

Additional rules:

- Android derives known secure state from reviewed `EditorInfo` input types.
- macOS combines secure-input state with a reviewed Accessibility-role check
  before claiming secure-field protection.
- Windows and Linux implement the strongest reliable target check available
  and report when sensitivity cannot be determined.
- iOS initial scope delivers only into ZenVoice's own non-secure editor, then
  through explicit Copy or Share.
- ZenVoice never records the field value or surrounding text to make this
  decision.
- The user cannot override the known-secure prohibition.

## 9. Inference and Hardware Strategy

### 9.1 Common baseline

- Pin one reviewed `whisper.cpp` release and source revision.
- Build from reviewed source in the new runtime pipeline when reproducibility
  is ready; until then, preserve the current checksum-pinned Apple artifact.
- Keep the C surface allowlisted to the functions ZenVoice uses.
- Use CPU inference as the correctness baseline.
- Enable an accelerated backend only after the same model passes accuracy,
  latency, memory, cancellation, and lifecycle tests on that backend.
- Runtime backend detection must fail back to a reviewed baseline.

### 9.2 Initial backend matrix

| Platform | Correctness baseline | Candidate acceleration |
| --- | --- | --- |
| Apple silicon macOS | CPU/Accelerate | Metal and reviewed Core ML assets |
| Intel macOS | x86 CPU/Accelerate | OpenVINO only after benchmark evidence |
| iOS | ARM CPU | Metal/Core ML when memory and thermal gates pass |
| Android | ARM64 CPU | Vulkan only on an explicit tested device allowlist |
| Windows | x86-64 CPU | Vulkan, OpenVINO, or CUDA as separately tested packages |
| Linux | x86-64 CPU | Vulkan, OpenVINO, or CUDA as separately tested packages |

The first release on a platform does not need every accelerator. A dependable
CPU path is more valuable than an unverified backend matrix.

### 9.3 Model catalogue changes

Each entry gains:

- supported operating systems;
- supported CPU architectures;
- required runtime backend or companion artifacts;
- estimated peak memory by verified device class;
- platform-specific file set and hash;
- minimum compatible core/runtime version; and
- redistribution decision.

Apple Core ML encoders, OpenVINO files, or other companion artifacts are
separate verified catalogue assets. A GGML file's verification does not verify
its companion acceleration asset.

### 9.4 Catalogue and download trust protocol

The first cross-platform implementation uses an embedded catalogue, not a
remotely mutable manifest.

Trust model:

- The versioned catalogue is compiled into the reviewed Rust core and covered
  by the signed application package.
- Catalogue changes require source review, licence/provenance review,
  deterministic checks, and a new application/core release.
- There is no runtime catalogue-signing key, remote configuration service, or
  arbitrary model URL input.
- Developer-only local model overrides remain separate, visibly unsafe
  development behavior and never become release defaults.

Download rules:

- A catalogue entry contains an exact HTTPS URL, expected origin, byte size,
  SHA-256, model identity, and artifact role.
- Only default HTTPS port 443 is accepted unless a reviewed entry explicitly
  records another port.
- Redirects are disabled by default. A reviewed exception may follow at most
  two redirects when every hop remains HTTPS and the final origin is on the
  entry's explicit allowlist.
- Resolution for the original request and every allowed redirect rejects
  loopback, private, link-local, multicast, and cloud-metadata address ranges;
  the request cannot change protocol after validation.
- Credentials, cookies, ambient proxy authentication, and URL user-info are
  not used for public model downloads.
- Response bodies are streamed into a random `.partial` file inside the final
  model directory with user-only permissions.
- The downloader enforces the expected maximum bytes even if
  `Content-Length` is absent or false.
- Size and SHA-256 are verified before `fsync` and atomic rename.
- Cancellation, mismatch, timeout, or crash leaves no selectable model.
- A verified installed model remains usable offline.

Update, rollback, and revocation:

- The catalogue has a monotonically increasing schema/catalogue version.
- The app never silently replaces a verified installed model with different
  bytes under the same identifier.
- An older application refuses a catalogue or model requiring a newer core; it
  does not delete the newer artifact automatically.
- A revoked artifact is marked in a signed application/core update. ZenVoice
  blocks new selection and download, explains the reason without exposing
  private data, and offers explicit removal.
- Emergency revocation without an app update is not claimed. Adding such a
  channel later requires a signed-manifest key hierarchy, rotation and
  recovery procedure, replay protection, availability policy, and new threat
  review.

## 10. Storage and Privacy Architecture

### 10.1 Local-only remains the default

Every platform must preserve:

- no account requirement;
- no audio or transcript upload;
- no analytics endpoint;
- local model execution;
- explicit export and share actions;
- encrypted History;
- Private Dictation;
- failed-audio recovery bounded to 24 hours;
- immediate cancellation cleanup;
- user-controlled deletion; and
- content-free diagnostic logging.

### 10.2 Portable database, platform-protected key

The schema and ciphertext format may be shared, but each installation has its
own platform-protected key. Cross-device database copying is not a supported
sync feature.

Encryption requirements:

- authenticated encryption with a reviewed algorithm;
- random nonces generated by a cryptographically secure generator;
- record and field identity included as associated data;
- transaction-safe migration;
- no plaintext indexes over transcript content;
- key rotation for Delete All;
- no keys in crash reports; and
- known-answer and tamper tests on every target.

### 10.3 Logs and diagnostics

Allowed:

- session identifiers that are random and local;
- state transitions;
- durations;
- model identifier;
- backend identifier;
- content-free error code;
- audio format metadata; and
- memory/performance measurements.

Forbidden:

- transcript text;
- prompt/context text;
- correction phrases;
- clipboard contents;
- audio samples or paths containing personal names;
- encryption keys or ciphertext dumps;
- full application document context; and
- download credentials.

### 10.4 Storage migration and rollback state machine

Every schema migration follows:

```text
preflight
  → encrypted backup
  → migration journal
  → transactional migration
  → integrity and decrypt checks
  → activate new schema
  → verified post-migration open
  → remove backup and journal
```

Rules:

- Preflight verifies schema versions, secure-key access, free space, database
  integrity, and the availability of the required migrator.
- The backup stays inside private application storage with user-only
  permissions and uses the existing encrypted database bytes. The raw key is
  not copied.
- The backup filename contains only schema version and a random identifier,
  not a user, transcript, or application name.
- The migration journal contains versions and states but no transcript text,
  key, or ciphertext dump.
- Migration uses a transaction or a new-database-and-atomic-swap strategy.
- Activation occurs only after schema invariants, ciphertext authentication,
  record counts, recovery paths, and representative decrypt checks pass.
- On failure before activation, the original remains active. On failure after
  swap but before verification, the migrator atomically restores the backup.
- The backup is removed after the first verified post-migration reopen.
- Delete All removes active databases, migration backups, journals, and
  recovery audio before rotating or destroying the vault key.
- Storage remnants are treated according to the documented SSD limitations;
  key rotation makes leftover encrypted bytes unreadable.
- An older application presented with a newer schema refuses to open it and
  gives recovery guidance. Automatic downgrade is forbidden.
- Migration, restore, failed restore, process kill at every state, Delete All,
  backup cleanup, and downgrade refusal have deterministic tests.

## 11. Native Application Plans

### 11.1 macOS Apple silicon and Intel

The macOS shell remains SwiftUI/AppKit.

Work:

1. audit the app, embedded runtime, resources, build scripts, signing, and
   third-party libraries for `arm64` and `x86_64`;
2. build every executable and nested library as Universal 2;
3. remove or conditionalize Apple-silicon-only assumptions;
4. provide Intel-appropriate model recommendations;
5. test CPU feature detection and safe fallback on older supported Intel
   hardware;
6. run the full model and lifecycle suites on physical Intel and Apple silicon
   Macs;
7. verify microphone and Accessibility permissions survive correctly signed
   updates on both architectures; and
8. package, sign, notarize, and clean-install the exact universal artifact
   before claiming distribution readiness.

The Intel milestone can ship before Rust adoption if it passes independently.

### 11.2 Windows

Initial scope:

- tray application;
- native settings;
- microphone selection and Audio Doctor;
- configurable global shortcut;
- ZenBar-equivalent compact overlay;
- local transcription and deterministic refinement;
- encrypted History, Recovery, Models, Languages, Voice Profile, and Privacy;
- insertion where permitted;
- explicit clipboard fallback; and
- signed installer and clean-device removal test.

Security considerations:

- do not request elevation for normal operation;
- respect integrity-level insertion failures;
- scope named pipes or IPC to the current user if multiple processes are used;
- reject DLL search-path hijacking;
- protect the vault key with an approved Windows mechanism;
- sign the executable, runtime libraries, and installer; and
- test Windows Defender reputation and false-positive behavior without
  weakening security controls.

Initial support target:

- Windows 11 x86-64.

Windows on ARM and Windows 10 are separate support decisions after the x86-64
path is stable.

### 11.3 Android

Components:

- containing application for onboarding, permissions, models, History,
  Recovery, Languages, Voice Profile, Audio Doctor, and Privacy;
- `InputMethodService` for dictation and direct text commit;
- foreground microphone indicator and user-controlled start/stop;
- minimal app-group-equivalent storage contract between app and IME service;
- ARM64 native Rust/`whisper.cpp` library; and
- Android Keystore-backed vault-key protection.

IME requirements:

- never record until the user explicitly starts dictation;
- show listening, processing, success, and error states;
- stop immediately when the user cancels or the input session ends;
- inspect input type only to protect sensitive fields;
- never retain or analyze surrounding target text;
- disable History or require explicit safe behavior in password fields;
- commit only to the current `InputConnection`;
- preserve Copy as a recovery action; and
- remain usable when the containing settings app is not running.

Initial support target:

- Android ARM64 devices on a declared API range chosen during XP0;
- physical low-, mid-, and high-memory device classes; and
- CPU baseline before any GPU allowlist.

### 11.4 Linux

Initial scope:

- one declared distribution and desktop environment;
- tray or background application supported by that environment;
- native microphone capture;
- XDG portal global shortcuts on Wayland where available;
- explicit X11 and Wayland paths;
- compact overlay;
- local transcription;
- encrypted History using a declared Secret Service provider;
- clipboard fallback; and
- one primary package format.

Recommended initial matrix:

- Ubuntu 24.04 LTS;
- GNOME;
- Wayland;
- X11 fallback;
- x86-64.

Expansion to KDE, additional distributions, ARM64, Flatpak, AppImage, Debian,
RPM, or Snap happens only after the first matrix is stable.

Linux must expose a capability report so support can diagnose:

- session type;
- desktop environment;
- portal backend and version;
- global-shortcut availability;
- insertion method;
- audio backend;
- keyring availability; and
- selected inference backend.

The report must contain no transcript or audio content.

### 11.5 iOS

Initial scope:

- SwiftUI containing application;
- explicit microphone recording;
- local transcription and refinement;
- editable result;
- encrypted History and Recovery consistent with iOS lifecycle limits;
- Models, Languages, Voice Profile, Audio Doctor, and Privacy;
- Copy and Share;
- background-interruption recovery where permitted; and
- physical-device memory, thermal, and battery measurements.

Not in initial scope:

- a claim of system-wide voice keyboard behavior;
- continuous background listening;
- automatic insertion into other applications; or
- a keyboard extension that attempts to access the microphone.

An optional keyboard extension is a later milestone only if it inserts
pre-produced text through a minimal app-group contract and passes a separate
privacy, extension-memory, and App Store review.

## 12. Build and Packaging Strategy

### 12.1 Produced core artifacts

| Target | Core artifact |
| --- | --- |
| macOS/iOS | Static libraries packaged for Xcode, plus generated Swift bindings |
| Android | ABI-specific `.so` libraries packaged into an AAR, plus Kotlin bindings |
| Windows | Reviewed DLL or static library with stable C ABI |
| Linux | Versioned shared or static library packaged with the application |

The build must record:

- Rust toolchain version;
- Cargo lockfile;
- target triple;
- `whisper.cpp` revision;
- enabled backend flags;
- compiler and linker versions;
- artifact SHA-256;
- dependency licences; and
- source commit.

### 12.2 Build-host matrix

| Artifact | Required host |
| --- | --- |
| macOS/iOS | macOS with pinned Xcode |
| Android | macOS or Linux with pinned JDK, SDK, NDK, and Rust targets |
| Windows | Windows with pinned MSVC toolchain |
| Linux | Oldest supported Linux build image or controlled container |

Cross-compilation is allowed only where the resulting artifact is still tested
on its real target.

### 12.3 Supply-chain controls

- Commit `Cargo.lock` for application builds.
- Pin Git dependencies to immutable revisions.
- Prefer registry releases with reviewed provenance over arbitrary branches.
- Generate an SBOM for release candidates.
- Run licence review before adding a dependency.
- Deny known vulnerable or unmaintained dependencies according to an approved
  policy.
- Pin CI actions to immutable commits.
- Never use `curl | sh` in release automation.
- Never download executable inference plug-ins at runtime.
- Keep signing credentials outside source, logs, and ordinary CI artifacts.

## 13. Test Strategy

### 13.1 Deterministic parity suite

Before porting a Swift behavior:

1. capture approved input/output fixtures from the current implementation;
2. include language, Unicode, punctuation, empty, long, malformed, and
   adversarial cases;
3. run Swift and Rust implementations on the same fixtures;
4. require exact output parity unless an intentional difference is documented;
5. review semantic-safety differences manually; and
6. retain the fixture after migration as a permanent regression test.

Priority fixture sets:

- transcript cleanup;
- Instant Refine;
- spoken commands;
- repetition and restart handling;
- language validation;
- corrections and language scope;
- model recommendations;
- share-card summary eligibility;
- lifecycle transitions; and
- model manifest rejection.

### 13.2 Rust core tests

- unit tests;
- property tests for lifecycle and serialization invariants;
- fuzz tests for FFI decoding, manifests, transcript transforms, SQLite
  migrations, and the narrow C wrapper;
- concurrency and cancellation tests;
- memory leak and sanitizer runs where supported;
- tamper tests for encrypted fields and model assets; and
- deterministic tests that require no microphone or network.

### 13.3 Host binding tests

Each host language must test:

- loading the real built library;
- creating and destroying a core instance repeatedly;
- Unicode and empty values;
- large but bounded buffers;
- cancellation;
- callbacks after host lifecycle changes;
- error mapping;
- panic containment; and
- library/core version mismatch.

Mocks alone do not satisfy this gate.

### 13.4 Runtime and model tests

For every supported platform/model/backend combination:

- model size and SHA-256;
- cold and warm model load;
- two sequential transcriptions through one retained context;
- cancellation during load and decode;
- audio-format rejection;
- peak memory;
- p50 and p95 stop-to-result latency;
- real-time factor;
- WER/CER or the appropriate language metric;
- unexpected-script and repetition safety;
- device sleep, interruption, and low-storage behavior;
- backend failure and CPU fallback; and
- thermal/battery behavior on mobile.

The existing benchmark is the starting methodology, not transferable proof for
new hardware.

### 13.5 Platform lifecycle tests

Common:

- permission denied, later granted, and revoked;
- microphone removed during capture;
- model removed or changed between sessions;
- process killed while recording, transcribing, persisting, and delivering;
- disk full;
- secure key store unavailable;
- corrupt database;
- corrupt or partial model;
- Private Dictation toggled in flight;
- Delete All during idle and after failed work;
- clock/time-zone change during recovery expiry; and
- accessibility/reduced-motion behavior.

Platform-specific physical QA is mandatory for advertised integration paths.

### 13.6 Numerical acceptance budgets

XP0 must create a versioned acceptance table before a platform alpha begins.
It records, per platform, device class, model, language suite, and backend:

- maximum p50 and p95 stop-to-result latency;
- maximum real-time factor;
- maximum peak resident memory;
- maximum model and installed-package size;
- minimum WER, CER, loanword preservation, or other language-appropriate
  accuracy;
- zero-tolerance semantic-safety violations;
- maximum mobile battery and thermal impact for the declared session length;
- maximum cold-model-load time;
- cancellation deadline; and
- minimum free-storage headroom.

Deterministic migrated behavior requires exact parity unless an intentional
change is reviewed and recorded. Platform performance and accuracy do not use
one invented universal number: each budget must be justified against the
current macOS baseline, physical target hardware, and the experience advertised
for that device class.

### 13.7 Gate registry and evidence

XP0 creates `docs/cross-platform/GATE_REGISTRY.md`. Every milestone exit gate
must reference one or more rows with:

| Field | Required content |
| --- | --- |
| Gate ID | Stable identifier such as `XP3-FFI-01` |
| Requirement | One observable pass/fail statement |
| Metric | Exact measurement or deterministic assertion |
| Threshold | Numeric limit or explicit zero-tolerance rule |
| Fixture/device | Corpus, hardware, architecture, OS, and backend |
| Runs | Required repetitions, duration, and cold/warm conditions |
| Command/procedure | Reproducible automated command or manual checklist |
| Evidence path | Committed summary or protected release evidence location |
| Approver | Founder plus specialist review where required |
| Expiry | When OS, runtime, model, hardware, or code change invalidates it |
| Waiver | Written residual risk, scope limit, approver, and expiry |

Words such as “acceptable,” “dependable,” “full workflow,” or “stabilization
cycle” do not close a gate unless their registry row defines them.

Initial evidence layout:

```text
docs/cross-platform/
├── GATE_REGISTRY.md
├── CAPABILITY_LEDGER.md
├── infrastructure/
├── parity/
├── runtime/
├── storage/
└── platforms/
    ├── macos/
    ├── windows/
    ├── android/
    ├── linux/
    └── ios/
```

Private transcript/audio fixtures and credentials never enter these evidence
directories.

## 14. CI and Verification Matrix

### 14.1 Pull-request gates

Every pull request:

- formatting and static analysis;
- secret and risky-file scan;
- Rust unit, property, and deterministic parity checks;
- Swift checks while the Swift implementation remains;
- generated-binding drift check;
- platform compile for affected targets;
- dependency and licence policy check;
- `git diff --check`; and
- documentation consistency for changed contracts.

### 14.2 Scheduled gates

Nightly or scheduled:

- sanitizer jobs;
- fuzzing with stored crash artifacts that contain no private user data;
- broader model smoke tests;
- Windows and Linux package installation tests;
- Android emulator matrix;
- iOS simulator lifecycle tests;
- dependency vulnerability audit; and
- reproducibility comparison where available.

### 14.3 Release-candidate gates

Release candidates require:

- exact source commit;
- clean dependency lock;
- signed provenance/SBOM;
- platform-specific signing;
- physical-device QA;
- model and language benchmark evidence;
- privacy inventory verification;
- clean install, upgrade, downgrade policy, and uninstall;
- accessibility review;
- crash recovery and data deletion;
- no secret in source or artifacts;
- distribution-channel review; and
- founder approval.

CI artifacts are verification builds, not release proof.

## 15. Milestone Plan

Milestones use the prefix `XP` to avoid rewriting the completed M0–M17 history.
Only one milestone is in implementation at a time unless its dependencies and
files are demonstrably independent.

### XP0 — Scope and capability baseline

**Goal:** Turn “cross-platform” into testable platform contracts.

Tasks:

- [ ] Confirm that the XP0 assumptions in this plan are approved or amend them.
- [ ] Choose the first supported OS/architecture version for every platform.
- [ ] Confirm Windows 11 x86-64 as the first Windows target or record a
      different decision.
- [ ] Confirm the initial Android API range and device-memory classes.
- [ ] Confirm Ubuntu 24.04/GNOME/x86-64 as the first Linux matrix or record a
      different decision.
- [ ] Confirm iOS as an in-app companion rather than system-wide live
      dictation.
- [ ] Create a platform capability ledger using the levels in section 5.
- [ ] Record per-platform distribution and licence questions.
- [ ] Record supported model tiers by device class as unknown until measured.
- [ ] Define the numerical accuracy, latency, memory, size, cancellation, and
      mobile thermal/battery budgets required by section 13.6.
- [ ] Create the gate registry and evidence directories from section 13.7.
- [ ] Record the canonical initial framework, host language, build system,
      minimum version, package format, and device matrix in one short
      platform ADR per target.
- [ ] Inventory CI runners, physical devices, responsible owner, signing
      boundary, credential store, artifact retention, and unavailable
      infrastructure.
- [ ] Define failure handling when a required runner or physical device is
      unavailable; the gate remains pending rather than silently skipped.

Exit gate:

- every target has an explicit initial capability, non-capability, hardware
  matrix, and evidence requirement;
- platform ADRs, the gate registry, capability ledger, and CI/device inventory
  exist;
- no product copy claims identical behavior; and
- unresolved choices are visible blockers, not implicit assumptions.

Rollback:

- documentation-only; no runtime behavior changes.

### XP0F — Platform feasibility probes

**Goal:** Test the highest-risk operating-system assumptions before building
full application shells.

Each probe is bounded to a minimal harness and a written result. Probe code is
not production architecture unless a later milestone adopts it explicitly.

Windows probe:

- [ ] capture audio from a selectable device;
- [ ] register and unregister one global shortcut;
- [ ] show a minimal overlay;
- [ ] insert fixed non-sensitive text into a normal target;
- [ ] demonstrate and surface higher-integrity failure; and
- [ ] exercise the proposed secure-key mechanism.

Android probe:

- [ ] load a minimal native Rust library on ARM64;
- [ ] record only after an explicit IME action;
- [ ] commit fixed non-sensitive text through `InputConnection`;
- [ ] detect reviewed password input types;
- [ ] survive IME/app process recreation; and
- [ ] measure native-library and one candidate model memory on physical low-
      and mid-memory devices.

Linux probe:

- [ ] detect Wayland and X11 sessions on the proposed initial matrix;
- [ ] request a global shortcut through the selected portal path;
- [ ] capture audio through the proposed backend;
- [ ] copy and attempt direct delivery through the proposed approach;
- [ ] exercise Secret Service availability and denial; and
- [ ] record compositor/portal limitations.

iOS probe:

- [ ] load a minimal Rust/`whisper.cpp` artifact in a Swift host;
- [ ] transcribe a bundled non-private fixture on a physical iPhone;
- [ ] measure cold load, peak memory, thermal state, and cancellation;
- [ ] exercise protected-data and interruption behavior; and
- [ ] confirm the containing-app Copy/Share product boundary.

Exit gate:

- each platform has a committed feasibility report;
- every claimed OS API works on the proposed physical or desktop matrix;
- memory and lifecycle evidence supports proceeding; and
- any failure results in an explicit scope reduction, alternate adapter
  decision, or stopped platform—not a hidden workaround.

May run with:

- XP1 and XP2 after XP0 decisions are complete.

Rollback:

- discard probe code; retain the evidence and decision.

### XP1 — Universal macOS foundation

**Goal:** Support Intel and Apple silicon without waiting for the Rust
migration.

Tasks:

- [ ] Audit architecture slices for the application and every nested binary.
- [ ] Produce a reviewed `x86_64` `whisper.cpp` runtime.
- [ ] Produce a Universal 2 release build.
- [ ] Add architecture inspection to packaging checks.
- [ ] Add Intel-safe backend and model recommendations.
- [ ] Run deterministic, runtime, model, memory, and lifecycle checks on real
      Intel hardware.
- [ ] Run the same release candidate on Apple silicon.
- [ ] Update requirements and model documentation only after evidence passes.

Exit gate:

- `arm64` and `x86_64` slices exist in every required binary;
- a physical Intel Mac completes the full workflow;
- benchmark and memory results support the advertised model defaults; and
- the universal package passes the applicable macOS release gates.

Rollback:

- retain the last verified Apple-silicon-only package while Intel remains
  unadvertised.

### XP2 — Swift portability seam

**Goal:** Separate portable behavior from macOS frameworks before translating
it.

Tasks:

- [ ] Inventory every type in `ZenVoiceCore`, `ZenVoiceRuntime`, and
      `ZenVoiceStorage`.
- [ ] Label each type `domain`, `runtime`, `storage`, `platform adapter`, or
      `UI`.
- [ ] Move AppKit, ApplicationServices, Carbon, Security, AVFoundation, and
      other OS imports behind explicit adapters.
- [ ] Define platform-neutral value types for language, model, transcript,
      lifecycle, and delivery state.
- [ ] Build deterministic golden fixtures from current Swift behavior.
- [ ] Add fake adapters for lifecycle checks.
- [ ] Preserve all existing macOS behavior and tests.

Exit gate:

- pure Swift domain checks run without AppKit, Carbon, AVFoundation, Security,
  or UI imports;
- macOS behavior remains unchanged;
- parity fixtures cover every candidate for Rust migration; and
- no storage or privacy regression is open.

Rollback:

- adapter extraction is performed in reviewable commits; revert the affected
  seam without changing stored data.

### XP3 — Rust toolchain and pilot

**Goal:** Prove the build, FFI, testing, and rollback approach with low-risk
logic.

Pilot scope:

- transcript cleanup;
- language/profile validation; and
- one model-manifest validation path.

Tasks:

- [ ] Add pinned Rust toolchain policy and committed lockfile.
- [ ] Create the minimal Cargo workspace.
- [ ] Implement the pilot without new product behavior.
- [ ] Generate Swift bindings.
- [ ] Call the Rust pilot from a non-production/internal path.
- [ ] Run Swift-versus-Rust parity fixtures.
- [ ] Add panic, Unicode, malformed input, concurrency, and lifecycle tests.
- [ ] Measure library size, call overhead, build time, and memory.
- [ ] Complete a focused unsafe/FFI security review.
- [ ] Document how to disable the Rust path.

Exit gate:

- exact parity passes;
- the real Swift app loads and unloads the library safely;
- no transcript crosses logs or crash diagnostics;
- overhead is acceptable relative to transcription cost;
- the build is reproducible on CI; and
- the Swift implementation remains available for rollback.

Stop condition:

- if FFI lifecycle, packaging, debugging, or performance remains unreliable
  after the bounded pilot, pause broader Rust migration and reassess the
  boundary instead of forcing adoption.

### XP4 — Shared deterministic domain

**Goal:** Move the approved deterministic candidates into Rust.

Order:

1. transcript cleanup;
2. meaning and repetition guards;
3. Instant Refine;
4. spoken structure and commands;
5. language profiles;
6. personal correction matching;
7. model recommendation policy;
8. share-summary eligibility; and
9. lifecycle state machine.

For each item:

- [ ] add or expand parity fixtures;
- [ ] implement in Rust;
- [ ] expose a coarse FFI operation;
- [ ] run both implementations;
- [ ] review intentional differences;
- [ ] switch the macOS caller;
- [ ] keep a rollback switch through one stabilization cycle; and
- [ ] remove the duplicate only after acceptance.

Exit gate:

- one Rust implementation owns all listed behavior;
- the macOS suite and benchmark gates pass;
- no duplicate production implementation remains without an explicit
  temporary reason; and
- generated interfaces are documented.

### XP5 — Shared `whisper.cpp` runtime

**Goal:** Replace the Apple-only runtime binding with a portable Rust-managed
runtime contract while preserving results.

Tasks:

- [ ] Pin reviewed `whisper.cpp` source and build definitions.
- [ ] Create a minimal allowlisted C binding.
- [ ] Wrap every unsafe operation in `zenvoice-runtime`.
- [ ] Define owned audio, configuration, result, and error types.
- [ ] Preserve retained-context serialization.
- [ ] Implement cancellation, deadlines, model replacement, and stale-session
      isolation.
- [ ] Package Apple, Android, Windows, and Linux smoke artifacts.
- [ ] Add a minimal release-mode host harness for macOS, iOS, Android,
      Windows, and Linux. A harness must load the real library, initialize a
      core, transcribe a bundled redistributable fixture, cancel a second
      operation, and release every handle.
- [ ] Add sanitizers, leak checks, and fuzzing around the C boundary.
- [ ] Compare the macOS Swift runtime and Rust runtime on identical audio.
- [ ] Confirm output, latency, and memory acceptance thresholds before
      switching macOS.

Exit gate:

- the Rust runtime performs two sequential local transcriptions through the
  real host harness on macOS, Windows, and Linux;
- the iOS and Android host harnesses perform one completed transcription plus
  cancellation on physical ARM64 devices identified in the gate registry;
- macOS output and semantic-safety parity pass;
- cancellation and destruction are leak-free under the available tools;
- backend fallback is deterministic; and
- no UI thread executes inference.

Rollback:

- retain the existing pinned Apple XCFramework path until the Rust-managed
  runtime completes the stabilization runs defined in its gate-registry row.

### XP6 — Portable encrypted storage

**Goal:** Share schema, encryption policy, History, Recovery, corrections, and
local-insight behavior without weakening platform key protection.

Tasks:

- [ ] Specify the portable schema and migration version.
- [ ] Define the secure-key-provider contract.
- [ ] Implement and migrate the macOS Keychain provider as the reference.
- [ ] Create a provider conformance suite that XP7–XP10 must run against their
      native key-store implementation.
- [ ] Port field-bound AES-GCM behavior with known-answer fixtures.
- [ ] Port lifecycle transactions and recovery expiry.
- [ ] Port corrections, Delete All, and key rotation.
- [ ] Port local insight queries.
- [ ] Test database migration from the current macOS schema.
- [ ] Test tampering, swapped fields, corrupt ciphertext, missing key, disk
      full, and interrupted migration.
- [ ] Define backup and downgrade behavior.

Exit gate:

- current macOS data migrates without plaintext export;
- the macOS reference and provider conformance harness pass
  encryption/tamper fixtures;
- unavailable secure storage fails closed;
- Delete All removes records and rotates the key; and
- no raw key is stored outside the platform provider.

Rollback:

- take a transaction-safe, encrypted-compatible backup before migration;
- never downgrade automatically if the older app cannot understand the schema;
  and
- provide explicit recovery guidance rather than risking corruption.

### XP7 — Windows alpha

**Goal:** Deliver the first non-Apple desktop workflow.

Tasks:

- [ ] Build the native shell and tray lifecycle.
- [ ] Implement WASAPI capture and device selection.
- [ ] Implement global shortcuts.
- [ ] Implement ZenBar-equivalent state UI.
- [ ] Implement DPAPI/approved secure-key provider.
- [ ] Pass the XP6 provider conformance suite.
- [ ] Implement insertion and visible clipboard fallback.
- [ ] Integrate models, History, Recovery, Languages, Voice Profile, and
      Privacy.
- [ ] Add signed installer, upgrade, uninstall, and data-retention choices.
- [ ] Test standard and higher-integrity target applications.
- [ ] Run real-device language/model benchmarks.
- [ ] Complete Windows threat model and accessibility QA.

Exit gate:

- Windows 11 x86-64 completes the declared capability contract;
- protected/elevated target limitations are correctly surfaced;
- package installation and removal are verified;
- physical-device evidence is recorded; and
- the build is labelled alpha until distribution gates pass.

### XP8 — Android alpha

**Goal:** Deliver local dictation through an Android input method.

Tasks:

- [ ] Build containing app and onboarding.
- [ ] Build the `InputMethodService`.
- [ ] Integrate ARM64 Rust and `whisper.cpp` artifacts.
- [ ] Implement explicit microphone lifecycle and visible state.
- [ ] Implement safe `InputConnection` commit.
- [ ] Implement Android Keystore-backed vault protection.
- [ ] Pass the XP6 provider conformance suite.
- [ ] Implement model storage, download verification, and low-storage handling.
- [ ] Implement secure-field and Private Dictation policy.
- [ ] Test IME switching, process death, rotation, backgrounding, calls, audio
      focus, and target-app changes.
- [ ] Benchmark low-, mid-, and high-memory physical devices.
- [ ] Complete Play policy, privacy disclosure, and accessibility review.

Exit gate:

- physical devices complete the declared IME workflow;
- password fields and surrounding text pass privacy review;
- model recommendations are evidence-backed by device class;
- lifecycle interruptions do not leak audio or text; and
- the build is labelled alpha until Play distribution gates pass.

### XP9 — Linux beta

**Goal:** Deliver a truthful, bounded Linux desktop release.

Tasks:

- [ ] Implement the declared Ubuntu/GNOME shell.
- [ ] Implement PipeWire/PulseAudio capture according to the chosen stack.
- [ ] Implement XDG Global Shortcuts portal support.
- [ ] Implement explicit Wayland and X11 delivery paths.
- [ ] Implement Secret Service key provider.
- [ ] Pass the XP6 provider conformance suite.
- [ ] Implement clipboard fallback.
- [ ] Add the content-free capability report.
- [ ] Choose and verify one package format.
- [ ] Test clean install, upgrade, uninstall, autostart, and desktop logout.
- [ ] Test on real Wayland and X11 sessions.
- [ ] Run x86-64 model benchmarks.

Exit gate:

- every supported matrix cell is tested;
- unsupported compositor or portal behavior is surfaced clearly;
- clipboard delivery remains dependable;
- no plaintext key fallback exists; and
- other distributions/desktops remain explicitly unsupported until tested.

### XP10 — iOS companion

**Goal:** Deliver the strongest honest iOS experience permitted by the
platform.

Tasks:

- [ ] Build SwiftUI app shell.
- [ ] Integrate the Rust core and iOS `whisper.cpp` artifact.
- [ ] Implement AVFoundation capture and interruption handling.
- [ ] Implement iOS Keychain provider.
- [ ] Pass the XP6 provider conformance suite.
- [ ] Implement local Models, History, Recovery, Languages, Voice Profile,
      Audio Doctor, and Privacy.
- [ ] Implement editor, Copy, and Share.
- [ ] Test app suspension, termination, calls, route changes, low storage, and
      protected-data availability.
- [ ] Benchmark physical iPhones across declared memory classes.
- [ ] Measure thermal and battery behavior.
- [ ] Complete VoiceOver, Dynamic Type, reduced-motion, and App Store privacy
      review.

Exit gate:

- physical iPhones complete the in-app contract;
- product copy does not claim unavailable system-wide microphone behavior;
- lifecycle and protected-data handling pass;
- model recommendations fit measured memory and thermal limits; and
- the build is labelled companion alpha until App Store gates pass.

### XP11 — Multi-platform release program

**Goal:** Move individually verified platform builds from alpha/beta to
supported releases.

Tasks per platform:

- [ ] choose distribution channel and pricing/licence implications;
- [ ] complete legal and model redistribution review;
- [ ] sign every executable and nested artifact;
- [ ] complete store/notarization/reputation requirements;
- [ ] publish exact supported OS, architecture, device, and capability matrix;
- [ ] publish privacy behavior and data locations;
- [ ] publish uninstall and Delete All behavior;
- [ ] complete clean-device accessibility and lifecycle QA;
- [ ] archive SBOM, hashes, benchmark report, and approval; and
- [ ] establish update and vulnerability-response procedures.

Exit gate:

- each platform independently satisfies `Supported` in section 5;
- no platform inherits another platform's release evidence; and
- support claims match the exact shipped artifact.

## 16. Canonical Execution and Dependency Order

For one primary maintainer, the preferred implementation sequence is:

```text
XP0 → XP0F → XP1 → XP2 → XP3 → XP4 → XP5 → XP6
    → XP7 → XP8 → XP9 → XP10 → XP11
```

This order prioritizes early feasibility evidence, preserves the current Mac
product, proves the migration boundary before expanding it, and limits the
number of platform alphas requiring simultaneous maintenance.

The dependency table is normative; the preferred sequence may be changed only
when the `May run with` column proves the work is independent.

| Milestone | Depends on | May run with | Required result |
| --- | --- | --- | --- |
| XP0 | None | None | Platform ADRs, budgets, capability and infrastructure ledgers |
| XP0F | XP0 | XP1, XP2 | Feasibility report for each target |
| XP1 | XP0 | XP0F, XP2 | Verified Universal 2 macOS path |
| XP2 | XP0 | XP0F, XP1 | Pure Swift seam and golden fixtures |
| XP3 | XP2 and required CI infrastructure | None | Bounded Rust/FFI pilot |
| XP4 | XP3 | None | Shared deterministic Rust domain |
| XP5 | XP4 and XP0F reports | XP6 | Portable runtime and real host harnesses |
| XP6 | XP4 and XP0F secure-store reports | XP5 | Portable encrypted storage and provider conformance kit |
| XP7 | XP0F Windows, XP5, XP6 | None by default | Windows alpha |
| XP8 | XP0F Android, XP5, XP6 | None by default | Android alpha |
| XP9 | XP0F Linux, XP5, XP6 | None by default | Linux beta |
| XP10 | XP0F iOS, XP5, XP6 | None by default | iOS companion alpha |
| XP11 | The platform milestone being released | Other platform release reviews only when independently staffed | Independently supported release |

```text
XP0 ─┬─► XP0F ─────────────────────────────┐
     ├─► XP1                               │
     └─► XP2 ─► XP3 ─► XP4 ─┬─► XP5 ─────┤
                             └─► XP6 ─────┼─► XP7  ─┐
                                         │   XP8  ─┤
                                         │   XP9  ─┤─► XP11
                                         └─► XP10 ─┘
```

Interpretation:

- Universal macOS can proceed after capability scope is accepted.
- Feasibility probes must pass or reduce scope before a platform alpha.
- Rust adoption starts only after the Swift portability seam and fixtures.
- Platform shells may prototype UI earlier, but they cannot claim an integrated
  alpha before the required shared runtime and privacy boundaries pass.
- XP5 and XP6 can proceed independently after the domain contracts stabilize.
- Platform-shell prototypes may begin earlier, but an integrated XP7–XP10
  alpha requires both the shared runtime and portable encrypted-storage gates.
- Data migration remains an independently reviewable change even when a
  platform shell depends on it.

## 17. Pull Request Strategy

Prefer small vertical slices.

Examples:

1. documentation and capability ledger;
2. architecture-slice packaging check;
3. one extracted Swift platform adapter;
4. Rust workspace plus one no-op binding smoke test;
5. one transcript-cleaner parity fixture set;
6. one migrated deterministic operation;
7. one `whisper.cpp` lifecycle wrapper;
8. one platform secure-key provider;
9. one Windows record-to-copy slice;
10. one Android IME record-to-commit slice.

Every pull request states:

- scope and exclusions;
- affected platforms;
- trust boundaries;
- tests run;
- physical-device evidence, if any;
- data migration impact;
- rollback;
- unresolved limitations; and
- whether support status changed.

Do not combine:

- framework migration and visual redesign;
- database migration and unrelated feature work;
- new model approval and runtime replacement;
- platform launch and cross-device sync;
- release signing and large code changes.

## 18. Security Review Plan

Each new boundary requires an updated threat model.

Minimum threats:

- malformed FFI input and use-after-free;
- C/C++ memory corruption;
- malicious or partial model files;
- path traversal during model install;
- model-download SSRF or source substitution;
- downgrade to an incompatible core or schema;
- plaintext fallback after secure-store failure;
- database/ciphertext swapping and tampering;
- transcript exposure through logs, clipboard, crash reports, backups, or
  notifications;
- cross-app text delivery to the wrong target;
- Android IME access to sensitive fields or surrounding text;
- Windows DLL hijacking and unsafe IPC;
- Linux portal spoofing or keyring absence;
- extension/app-group over-sharing on iOS;
- dependency and CI compromise; and
- leaked signing credentials.

Security acceptance requires:

- authentication and ownership checks for any local IPC;
- strict schema and length validation before side effects;
- parameterized SQLite operations;
- path resolution and allowed-root checks;
- HTTPS host allowlist plus pinned manifest metadata;
- sanitized user-facing errors;
- redacted security-event logging;
- least-privilege permissions;
- lockfile and dependency audit;
- fuzz/sanitizer evidence for unsafe boundaries; and
- documented residual risk.

## 19. Risk Register

| Risk | Impact | Mitigation | Trigger to reconsider |
| --- | --- | --- | --- |
| Flag-day rewrite destabilizes macOS | High | Strangler migration with parity and rollback | Mac regression cannot be isolated |
| FFI creates lifecycle bugs | High | Coarse API, owned buffers, panic containment, binding tests | Repeated leaks/crashes after XP3 |
| `whisper.cpp` backend differs by hardware | High | CPU correctness baseline and per-backend benchmarks | Output or safety parity fails |
| Mobile models exceed memory/thermal limits | High | Device tiers, quantized models, bounded contexts | App termination or unacceptable heat |
| iOS cannot match desktop insertion | High product risk | Companion scope and honest copy | Product requires live system-wide keyboard |
| Wayland prevents dependable insertion | High product risk | Portal support and clipboard baseline | Target desktop cannot meet minimum contract |
| Windows insertion fails into elevated apps | Medium | Visible clipboard fallback; no elevation workaround | Full elevated-app insertion becomes mandatory |
| Secure storage differs by platform | High | Platform provider and fail-closed History | A target lacks acceptable protected key storage |
| Duplicate Swift/Rust behavior drifts | Medium | Short coexistence, parity fixtures, removal gate | Dual paths remain beyond stabilization |
| Cross-platform scope overwhelms maintenance | High | Sequential XP milestones and bounded matrices | Two platform alphas cannot be supported honestly |
| Dependency growth weakens supply chain | Medium | YAGNI, lockfile, audit, SBOM, licence review | Unmaintained critical crate/runtime |
| Model licences differ by artifact | High | Per-artifact provenance and redistribution review | Licence or source cannot be verified |

## 20. Decision Points Requiring Human Approval

Implementation pauses for explicit approval when:

- choosing minimum OS/API versions;
- choosing Windows/Linux UI frameworks;
- choosing a new licence or distribution channel;
- adding a model or accelerated companion artifact;
- changing encrypted schema compatibility or downgrade policy;
- changing the local-only privacy promise;
- introducing accounts, sync, telemetry, or any network text processing;
- enabling a new runtime backend by default;
- adding an iOS keyboard extension;
- broadening the Linux support matrix;
- dropping Intel Mac support; or
- declaring any platform publicly supported.

Normal implementation details inside an accepted milestone do not require
reapproval when they preserve these contracts.

## 21. Definition of Done

The cross-platform architecture program is complete only when:

- [ ] ADR 0003 remains the implemented architecture;
- [ ] the shared Rust core owns the approved platform-neutral behavior;
- [ ] `whisper.cpp` is pinned, wrapped narrowly, and verified for every
      supported target;
- [ ] the macOS application runs natively on supported Apple silicon and Intel
      Macs;
- [ ] Windows satisfies its declared desktop contract;
- [ ] Android satisfies its declared IME contract;
- [ ] Linux satisfies every declared matrix cell;
- [ ] iOS satisfies its declared companion contract;
- [ ] every platform uses protected local keys and encrypted History;
- [ ] Private Dictation, recovery expiry, Delete All, and model verification
      pass independently on every platform;
- [ ] all advertised model/language claims have platform-specific benchmark
      evidence;
- [ ] physical-device accessibility and lifecycle QA are complete;
- [ ] each exact release artifact is signed and distribution-verified;
- [ ] limitations are present in product and support documentation; and
- [ ] no required work is represented by a silent TODO or an unsupported
      marketing claim.

## 22. Immediate Next Actions

Do these next, in order:

1. Review and approve the XP0 platform/version assumptions.
2. Create the capability ledger.
3. Begin the Universal macOS binary and dependency audit.
4. Inventory every current Swift type by architecture responsibility.
5. Extract deterministic parity fixtures before translating code.
6. Run the bounded XP3 Rust pilot.

Do not begin all platform applications at once. The first engineering proof is
not a Windows or Android screen; it is a clean portability seam, exact
behavioral fixtures, and a Rust library that the existing macOS app can load,
exercise, and disable safely.
