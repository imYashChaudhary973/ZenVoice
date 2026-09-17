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

import AppKit
import Carbon.HIToolbox
import ApplicationServices
import Foundation

public final class TextInserter {
    /// Best-effort copy of the user's pasteboard contents, taken before
    /// ``insert(_:)`` writes the transcript over them and put back once the
    /// paste has landed. macOS has no atomic swap here — the paste target
    /// reads the pasteboard asynchronously when it handles Command-V — so
    /// this is the same save/write/wait/restore dance clipboard managers
    /// do, and best-effort by nature.
    public struct PasteboardSnapshot: Equatable {
        let changeCount: Int
        let items: [[NSPasteboard.PasteboardType: Data]]
    }

    /// How long to wait after posting the synthetic ⌘V before restoring the
    /// user's clipboard. The paste target reads the pasteboard when it
    /// processes the key event; restoring earlier races that read and the
    /// old contents land instead of the transcript.
    static let pasteboardRestoreDelayMicroseconds: UInt32 = 150_000

    public enum InsertResult: Equatable {
        case pasted
        case copiedOnly
        /// Another application has secure input switched on, so macOS refuses
        /// to deliver the synthetic paste and the accessibility fallback found
        /// nothing writable. The transcript is on the pasteboard.
        case blockedBySecureInput
    }

    public enum ReplaceResult: Equatable {
        /// The expected text was found immediately before the caret and swapped
        /// for the replacement.
        case replaced
        /// The focused control does not expose the text APIs needed to do this
        /// safely.
        case unsupported
        /// What is on screen is not what ZenVoice put there — the user has
        /// typed, moved the caret, or switched fields.
        case mismatch
    }

    /// Replaces text ZenVoice previously inserted with a corrected version.
    ///
    /// Deliberately does *not* simulate backspaces. Blind deletion assumes the
    /// caret is still where ZenVoice left it, and if it is not the app happily
    /// eats whatever the user typed instead. Reading the focused element and
    /// verifying the exact characters before the caret first means a failed
    /// assumption returns ``ReplaceResult/mismatch`` instead of destroying
    /// someone's work.
    public init() {}

    public func replaceTextBeforeCaret(
        _ existing: String,
        with replacement: String
    ) -> ReplaceResult {
        guard AXIsProcessTrusted(), !existing.isEmpty else {
            return .unsupported
        }

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let rawFocused = focusedValue,
        CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
            return .unsupported
        }
        let element = unsafeBitCast(rawFocused, to: AXUIElement.self)

        var caretValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &caretValue
        ) == .success,
        let rawCaret = caretValue,
        CFGetTypeID(rawCaret) == AXValueGetTypeID() else {
            return .unsupported
        }
        var caretRange = CFRange()
        guard AXValueGetValue(unsafeBitCast(rawCaret, to: AXValue.self), .cfRange, &caretRange)
        else {
            return .unsupported
        }

        var textValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &textValue
        ) == .success,
        let text = textValue as? String else {
            return .unsupported
        }

        // Accessibility ranges are in UTF-16 units, so compare in the same
        // units rather than Characters — an emoji or accented letter would
        // otherwise shift every offset.
        let contents = Array(text.utf16)
        let expected = Array(existing.utf16)
        let caret = caretRange.location
        guard caret >= expected.count, caret <= contents.count else {
            return .mismatch
        }
        let start = caret - expected.count
        guard Array(contents[start..<caret]) == expected else {
            return .mismatch
        }

        var replaceRange = CFRange(location: start, length: expected.count)
        guard let rangeValue = AXValueCreate(.cfRange, &replaceRange),
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                rangeValue
              ) == .success,
              AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                replacement as CFTypeRef
              ) == .success else {
            return .unsupported
        }
        return .replaced
    }

    /// Whether some application has switched on secure input.
    ///
    /// While it is on, macOS blocks synthetic keyboard events system-wide, so
    /// the Command-V below is swallowed and nothing arrives. Chromium-based
    /// browsers and Electron apps are the usual cause — they enable it around
    /// password fields and frequently leave it on — which is why dictation
    /// appears to stop working in exactly those apps while the recorder, the
    /// hotkey and the transcript all behave normally.
    ///
    /// The hotkey keeps working throughout because it is a Carbon hot key
    /// rather than an event tap, which is why the failure looks like "the text
    /// vanished" rather than "the app is dead".
    public static var isSecureInputEnabled: Bool {
        IsSecureEventInputEnabled()
    }

    /// Whether an accessibility write is safe for the focused element.
    ///
    /// Secure input normally means a password field has focus. A secure text
    /// field must never receive a transcript, and a generic text field without
    /// a subrole is ambiguous while secure input is active, so this fails
    /// closed. Text areas and explicitly identified non-secure text controls
    /// remain eligible for the best-effort fallback.
    public static func allowsAccessibilityInsertion(
        role: String?,
        subrole: String?
    ) -> Bool {
        guard subrole != kAXSecureTextFieldSubrole as String else {
            return false
        }
        if role == kAXTextAreaRole {
            return true
        }
        // A combo box wraps a text field, so an unidentified one is ambiguous
        // for the same reason a bare text field is. It used to be admitted with
        // no subrole at all, which contradicted the rule above it.
        if role == kAXTextFieldRole || role == kAXComboBoxRole {
            return subrole != nil
        }
        return false
    }

    /// Writes text into the focused control through the accessibility API.
    ///
    /// The escape hatch from secure input: it blocks *synthetic events*, not
    /// accessibility writes, so this still lands when Command-V cannot. Not
    /// the default path because plenty of controls — Chromium's own text
    /// areas among them — expose no writable selected-text attribute, and
    /// pasting is what works everywhere else.
    private func insertViaAccessibility(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let rawFocused = focusedValue,
        CFGetTypeID(rawFocused) == AXUIElementGetTypeID() else {
            return false
        }
        let element = unsafeBitCast(rawFocused, to: AXUIElement.self)
        var roleValue: CFTypeRef?
        let roleStatus = AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        )
        var subroleValue: CFTypeRef?
        let subroleStatus = AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        let role = roleStatus == .success ? roleValue as? String : nil
        let subrole =
            subroleStatus == .success ? subroleValue as? String : nil
        guard Self.allowsAccessibilityInsertion(
            role: role,
            subrole: subrole
        ) else {
            return false
        }
        // Writing the selected text replaces the selection, or inserts at the
        // caret when the selection is empty — the same thing a paste does.
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    /// Final insertion must stay in the app that was frontmost when dictation
    /// started. A nil original target means we never captured one.
    public static func shouldPaste(
        intoFrontmost frontmost: pid_t?,
        originalTarget: pid_t?
    ) -> Bool {
        guard let originalTarget else {
            return true
        }
        return frontmost == originalTarget
    }

    /// Copies every declared type of every pasteboard item. Promised data
    /// that the owning app fails to resolve is skipped — best-effort.
    public static func capturePasteboard(
        _ pasteboard: NSPasteboard
    ) -> PasteboardSnapshot {
        var items: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var contents: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            if !contents.isEmpty {
                items.append(contents)
            }
        }
        return PasteboardSnapshot(
            changeCount: pasteboard.changeCount,
            items: items
        )
    }

    /// Writes a snapshot back, but only while `changeCount` is still the
    /// count observed right after the transcript was written. Anything else
    /// that changed the clipboard in between — a clipboard manager capturing
    /// the transcript, or the user copying — wins over the restore.
    public static func restorePasteboard(
        _ snapshot: PasteboardSnapshot,
        to pasteboard: NSPasteboard,
        ifUnchangedSince changeCount: Int
    ) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        for contents in snapshot.items {
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            pasteboard.writeObjects([item])
        }
    }

    public func insert(_ text: String) -> InsertResult {
        let pasteboard = NSPasteboard.general
        // The transcript replaces the clipboard for the duration of the
        // paste; snapshot the user's contents first so they can go back.
        let snapshot = Self.capturePasteboard(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        pasteboard.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType"))
        let writtenChangeCount = pasteboard.changeCount

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            // `.copiedOnly` is the recovery path — the transcript must stay
            // on the clipboard, so the snapshot is dropped here on purpose.
            return .copiedOnly
        }

        // Secure input swallows the paste silently, so try accessibility
        // first rather than posting an event that cannot arrive. Reporting
        // `.pasted` here was the actual defect: the transcript was on the
        // pasteboard, nothing reached the app, and ZenVoice said it had
        // worked.
        if Self.isSecureInputEnabled {
            let pasted = insertViaAccessibility(text)
            if pasted {
                // The accessibility write never touched the pasteboard, so
                // the user's clipboard can go straight back.
                Self.restorePasteboard(
                    snapshot,
                    to: pasteboard,
                    ifUnchangedSince: writtenChangeCount
                )
            }
            return pasted ? .pasted : .blockedBySecureInput
        }

        let source = CGEventSource(stateID: .hidSystemState)
        // Optional-chaining these posts would report `.pasted` even when the
        // events were never created, so a silent failure looked identical to
        // a successful insertion — including in saved history. The transcript
        // is on the pasteboard either way, so say so honestly instead.
        guard let keyDown = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: true
              ),
              let keyUp = CGEvent(
                keyboardEventSource: source,
                virtualKey: 9,
                keyDown: false
              ) else {
            return .copiedOnly
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        // 15ms hold duration ensures Electron, Chromium, and web compositor
        // event loops reliably capture the synthetic Command+V event without dropping it.
        usleep(15_000)
        keyUp.post(tap: .cghidEventTap)
        // Give the target app time to read the pasteboard before putting the
        // user's clipboard back — see pasteboardRestoreDelayMicroseconds.
        usleep(Self.pasteboardRestoreDelayMicroseconds)
        Self.restorePasteboard(
            snapshot,
            to: pasteboard,
            ifUnchangedSince: writtenChangeCount
        )
        return .pasted
    }

    public func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
