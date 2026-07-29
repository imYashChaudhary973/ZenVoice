# ADR 0003: Cross-Platform Rust Core and Native Adapters

- Status: Accepted
- Date: 2026-07-29
- Extends: ADR 0001 and ADR 0002

## Context

ZenVoice is currently a native macOS application implemented with Swift,
SwiftUI, AppKit, AVFoundation, macOS Accessibility APIs, CryptoKit, Keychain,
SQLite, and a pinned `whisper.cpp` XCFramework.

The product is expanding to:

- Apple silicon Macs;
- Intel Macs;
- iOS devices;
- Android devices;
- Windows devices; and
- Linux devices.

The existing deterministic transcript pipeline, model governance, encrypted
history, language profiles, corrections, recovery behavior, and privacy
controls should behave consistently across platforms. Audio capture, global
shortcuts, text insertion, secure key storage, permissions, application
identity, background execution, and distribution are operating-system
boundaries and cannot be implemented honestly as one universal abstraction.

Rewriting the existing macOS application into a cross-platform UI framework
would discard working native behavior before the shared architecture is
proven. Keeping all product logic in Swift would not provide a practical
Android application or a common runtime boundary for every target.

## Decision

ZenVoice will use:

1. a shared Rust core for platform-independent product behavior;
2. the pinned `whisper.cpp` C API as the common local transcription engine;
3. narrow, versioned foreign-function interfaces generated for Swift and
   Kotlin where suitable, plus a stable C ABI where another host language
   requires it; and
4. native platform adapters for user interface and operating-system behavior.

The existing SwiftUI/AppKit macOS application remains the macOS product shell.
It will adopt the Rust core incrementally after behavior-parity tests pass.
There will be no flag-day rewrite.

The first shared Rust candidates are deterministic and low-risk:

- transcript cleanup and meaning-preserving refinement;
- language and profile rules;
- model-catalogue parsing and validation;
- model recommendation policy; and
- the platform-neutral dictation lifecycle state machine.

Platform-specific implementations remain outside the shared core:

- microphone capture and device discovery;
- microphone, accessibility, background, and notification permissions;
- global shortcuts and hold-to-dictate behavior;
- foreground-application discovery and text insertion;
- Keychain, Android Keystore, Windows credential protection, and Linux secret
  storage;
- native windows, overlays, menus, input methods, and app extensions;
- installers, signing, notarization, and store integration.

The Rust core will call `whisper.cpp` only through a narrow internal wrapper.
No raw C or C++ pointers will cross into Swift, Kotlin, or UI code.

## Product Capability Decision

Cross-platform does not mean identical capability.

- macOS and Windows target the complete system-wide desktop dictation
  experience.
- Linux targets the same experience where the active desktop, compositor, and
  portals permit it, with clipboard fallback as a guaranteed baseline.
- Android targets an `InputMethodService` dictation keyboard plus a containing
  application for settings, models, history, and privacy controls.
- iOS targets an in-app local dictation companion with explicit Copy and Share
  actions. A third-party iOS keyboard extension cannot directly access the
  microphone, so system-wide live voice-keyboard parity is not promised.

These distinctions must remain visible in product copy, QA, and release
claims.

## Consequences

- The current `ZenVoiceCore` Swift target must first be split into pure logic
  and macOS adapters; its name does not currently imply portability.
- Swift and Rust implementations will coexist during migration.
- Every migrated function requires deterministic parity fixtures and a
  rollback path to the previous Swift implementation.
- High-frequency audio transport across FFI must use bounded flat buffers or
  file/session handles, not object-per-sample callbacks.
- The shared core reduces duplicated product logic but does not remove native
  platform engineering.
- Rust memory safety does not make `whisper.cpp` safe. The C API remains an
  explicit unsafe trust boundary with focused validation and fuzzing.
- Every platform keeps data local by default. Cross-device sync, accounts,
  cloud transcription, telemetry, and remote refinement remain outside this
  decision and require separate approval and threat review.
- Platform support is earned through real hardware, accuracy, latency, memory,
  lifecycle, accessibility, privacy, and release evidence. Compilation alone
  is not support.

## Rejected Alternatives

### Rewrite every application in Flutter

Flutter covers the requested operating systems, but ZenVoice would still need
native audio, input-method, hotkey, accessibility, secure-storage, inference,
and distribution adapters. Replacing the working SwiftUI macOS shell before
the shared core is proven creates unnecessary product and migration risk.

### Use Tauri for every platform

Tauri is useful as an optional Windows or Linux desktop shell, but a WebView
does not remove Android input-method, iOS extension, macOS accessibility, or
native audio work. ZenVoice will not replace its native macOS interface with a
WebView.

### Share the entire UI with Kotlin Multiplatform

Kotlin Multiplatform is strong for Android and iOS sharing, but it would still
require native desktop integration and would make Kotlin the second shared
domain implementation beside the existing Swift code and `whisper.cpp`.

### Rewrite the product in Qt/C++

Qt supports the target platforms and would integrate directly with
`whisper.cpp`, but it would require a broad C++ rewrite, expand memory-safety
risk, and discard the current native macOS work.

### Keep the shared implementation in Swift

Swift supports Apple platforms, Windows, and Linux, but it does not provide the
most practical common Android and native-integration path for this product.

