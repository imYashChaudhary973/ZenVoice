# ADR 0008 — Command Mode: Voice Control Trust Boundaries

## Status

Accepted — Phase 3 implemented.

## Context

ZenVoice already parses a small set of local voice commands ("new paragraph",
"period", etc.) inside `LocalVoiceCommandEngine`. Phase 3 extends this into
full **Command Mode**: launching apps, running Shortcuts, changing system
settings, and executing user-defined scripts by voice. This is a trust
boundary: voice-driven actions can modify system state and run arbitrary code.

## Decision

Command Mode is **off by default** and requires explicit opt-in per app profile.

1. Built-in action types:
   - `LaunchApp(bundleID: String)` via `NSWorkspace`
   - `RunShortcut(name: String)` via `Shortcuts` framework on macOS 14+, or
     fall back to opening the Shortcuts app
   - `SystemAction(SystemActionType)` for volume, brightness, Do Not Disturb,
     sleep displays, lock screen
   - `RunAppleScript(String)` and `RunShellScript(String)` with explicit user
     approval
2. Every command maps a spoken phrase to exactly one action. The mapping is
   stored in a command manifest and can be per-app.
3. Safety controls:
   - Command Mode is opt-in per profile.
   - Script and URL actions require a first-run confirmation overlay.
   - A kill phrase ("cancel command") stops an in-flight action.
   - Actions that change system state run only if the active app profile allows
     Command Mode.
4. Command parsing uses deterministic phrase matching first, with an optional
   local intent model as a later enhancement.
5. Failed commands are surfaced in ZenBar with a clear error, not silently
   swallowed.

## Consequences

- Power users can automate their Mac by voice without cloud services.
- Script execution is gated by Accessibility permission and an explicit ZenVoice
  approval prompt.
- Built-in system actions avoid shell/AppleScript for common tasks.
- The phrase-to-action manifest is inspectable and editable in Settings.

## Trust boundaries

| Action | Risk | Mitigation |
|---|---|---|
| LaunchApp | Opens an app | No additional gate; user defined the mapping |
| RunShortcut | Runs a user Shortcut | First-run approval; Shortcuts run under user's own permissions |
| SystemAction | Changes system state | Built-in, sandboxed implementation; no arbitrary code |
| RunAppleScript | Arbitrary AppleScript | Accessibility permission + first-run approval + kill phrase |
| RunShellScript | Arbitrary shell command | Accessibility permission + first-run approval + kill phrase |

## Implementation notes

- `Sources/ZenVoiceCore/CommandModeEngine.swift` owns parsing and action
  serialization.
- `Sources/ZenVoiceCore/CommandAction.swift` defines the action types.
- Execution bridges into `ZenVoice` (the app target) for `NSWorkspace`,
  `Shortcuts`, and Accessibility APIs that require a real app bundle.
- Unit tests in `ZenVoiceCoreChecks` cover phrase matching and action
  serialization; manual QA covers live execution.

## Privacy

- Commands are processed locally.
- No command history leaves the Mac.
- Shortcuts and scripts execute with the user's own permissions; ZenVoice does
  not escalate privilege.

## Related decisions

- ADR 0005 — Multi-Engine Speech Architecture
- `docs/PRIVACY.md`
