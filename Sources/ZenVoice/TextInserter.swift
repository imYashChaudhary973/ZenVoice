import AppKit
import ApplicationServices
import Foundation

final class TextInserter {
    enum InsertResult {
        case pasted
        case copiedOnly
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
