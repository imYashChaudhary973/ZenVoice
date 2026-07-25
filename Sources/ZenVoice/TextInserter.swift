import AppKit
import ApplicationServices
import Foundation

final class TextInserter {
    enum InsertResult {
        case pasted
        case copiedOnly
    }

    enum ReplaceResult {
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
    func replaceTextBeforeCaret(
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
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return .unsupported
        }
        // swiftlint:disable:next force_cast
        let element = focusedValue as! AXUIElement

        var caretValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &caretValue
        ) == .success,
        CFGetTypeID(caretValue) == AXValueGetTypeID() else {
            return .unsupported
        }
        var caretRange = CFRange()
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(caretValue as! AXValue, .cfRange, &caretRange)
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

    func insert(_ text: String) -> InsertResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission()
            return .copiedOnly
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
        keyUp.post(tap: .cghidEventTap)
        return .pasted
    }

    func requestAccessibilityPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
