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

import Foundation
import SwiftUI

/// The kind of on-screen overlay ZenVoice can show.
///
/// `.zenBar` preserves the existing compact dictation bar. The live-preview
/// variants are new in Phase 4 and provide larger, notch-aware transcription
/// feedback.
public enum OverlayKind: String, Codable, CaseIterable, Sendable {
    case zenBar
    case livePreviewPill
    case livePreviewMedium
    case livePreviewLarge

    public var displayName: String {
        switch self {
        case .zenBar:
            return "ZenBar"
        case .livePreviewPill:
            return "Live Preview Pill"
        case .livePreviewMedium:
            return "Live Preview Medium"
        case .livePreviewLarge:
            return "Live Preview Large"
        }
    }

    public var detail: String {
        switch self {
        case .zenBar:
            return "Compact dictation bar at the bottom of the screen."
        case .livePreviewPill:
            return "One-line transcription pill near the notch or menu bar."
        case .livePreviewMedium:
            return "Two to three lines of live transcription, top-center."
        case .livePreviewLarge:
            return "Five to six lines of live transcription, top-center."
        }
    }

    /// Whether this overlay is a live preview variant rather than the ZenBar.
    public var isLivePreview: Bool {
        switch self {
        case .zenBar:
            return false
        case .livePreviewPill, .livePreviewMedium, .livePreviewLarge:
            return true
        }
    }

    /// The number of visible transcription lines this overlay is designed for.
    public var lineCount: Int {
        switch self {
        case .zenBar:
            return 1
        case .livePreviewPill:
            return 1
        case .livePreviewMedium:
            return 3
        case .livePreviewLarge:
            return 6
        }
    }

    /// Default size for a live-preview panel of this kind.
    ///
    /// ZenBar keeps its original dimensions — the widest bar state plus the
    /// margin its shadow needs — so switching to the generic panel controller
    /// does not clip it.
    public var defaultSize: CGSize {
        switch self {
        case .zenBar:
            return CGSize(
                width: ZenBarView.maximumBarWidth
                    + (ZenBarView.shadowInset * 2),
                height: ZenBarView.barHeight
                    + (ZenBarView.shadowInset * 2)
            )
        case .livePreviewPill:
            return CGSize(width: 420, height: 40)
        case .livePreviewMedium:
            return CGSize(width: 520, height: 96)
        case .livePreviewLarge:
            return CGSize(width: 640, height: 160)
        }
    }
}
