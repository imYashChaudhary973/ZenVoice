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
import ApplicationServices
import Foundation
import ZenVoiceCore

/// Concrete reader for Write Mode that reads the current selection.
///
/// It tries Accessibility first, then falls back to the clipboard when the
/// caller allows it. This lives in the app target because it needs system
/// permissions.
@MainActor
struct WriteModeTextReaderImpl: WriteModeTextReader {
    func read(_ request: WriteModeReadRequest) async throws -> WriteModeReadResult {
        // Verify frontmost app matches the expected bundle if provided.
        if let expectedBundle = request.sourceBundleIdentifier {
            let frontmostBundle = NSWorkspace.shared.frontmostApplication?
                .bundleIdentifier
            if frontmostBundle != expectedBundle {
                // The user switched apps while dictating. Fall back to
                // clipboard only; do not read from a different app.
                return try fallbackRead(request)
            }
        }

        if let accessibilityText = readAccessibilitySelection() {
            return WriteModeReadResult(
                text: accessibilityText,
                source: .accessibility,
                isVerified: true
            )
        }

        return try fallbackRead(request)
    }

    private func fallbackRead(_ request: WriteModeReadRequest) throws -> WriteModeReadResult {
        guard request.fallbackToClipboard,
              let clipboardText = NSPasteboard.general.string(forType: .string) else {
            throw WriteModeReadError.noSelectionAvailable
        }
        return WriteModeReadResult(
            text: clipboardText,
            source: .clipboard,
            isVerified: false
        )
    }

    private func readAccessibilitySelection() -> String? {
        guard AXIsProcessTrusted() else { return nil }

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(),
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        // swiftlint:disable:next force_cast
        let element = focusedValue as! AXUIElement

        var selectedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        ) == .success,
        let selected = selectedValue as? String else {
            return nil
        }
        return selected
    }
}

/// Errors specific to reading the current selection.
public enum WriteModeReadError: LocalizedError {
    case noSelectionAvailable

    public var errorDescription: String? {
        switch self {
        case .noSelectionAvailable:
            return "No text is selected and the clipboard is empty."
        }
    }
}
