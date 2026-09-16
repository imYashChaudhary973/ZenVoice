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
import Foundation
import SwiftUI
import ZenVoiceCore

/// Persistent preferences for the Phase 4 overlay system.

public enum RecordingHUDStyle: String, Codable, CaseIterable, Sendable {
    case notch
    case floatingPanel

    public var displayName: String {
        switch self {
        case .notch: return "Notch"
        case .floatingPanel: return "Floating panel"
        }
    }

    public var detail: String {
        switch self {
        case .notch: return "Hugs the camera housing"
        case .floatingPanel: return "Glass pill, any corner"
        }
    }
}

public enum RecordingHUDPosition: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var displayName: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

public enum RecordingHUDAppearance: String, Codable, CaseIterable, Sendable {
    case dark
    case light
    case system

    public var displayName: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "System"
        }
    }
}

public enum OverlayPreferences {
    public static let activeOverlayKey = "ZenVoice.overlay.activeKind"
    public static let livePreviewEnabledKey = "ZenVoice.overlay.livePreviewEnabled"
    public static let reduceMotionKey = "ZenVoice.overlay.reduceMotion"
    public static let hudStyleKey = "ZenVoice.overlay.hudStyle"
    public static let hudPositionKey = "ZenVoice.overlay.hudPosition"
    public static let hudAppearanceKey = "ZenVoice.overlay.hudAppearance"

    /// Posted whenever an overlay preference changes, so the app delegate can
    /// rebuild the overlay panel against the new selection.
    public static let didChangeNotification = Notification.Name(
        "ZenVoice.overlay.didChange"
    )

    private static func notifyChange() {
        NotificationCenter.default.post(
            name: didChangeNotification,
            object: nil
        )
    }

    /// The currently selected overlay kind. Defaults to `.zenBar` so existing
    /// behavior is unchanged.
    public static func loadActiveOverlay(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> OverlayKind {
        guard let rawValue = defaults.string(forKey: activeOverlayKey),
              let kind = OverlayKind(rawValue: rawValue) else {
            return .zenBar
        }
        return kind
    }

    public static func saveActiveOverlay(
        _ kind: OverlayKind,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(kind.rawValue, forKey: activeOverlayKey)
        notifyChange()
    }

    /// Whether live preview overlays are enabled at all. This is a master toggle
    /// that can disable live previews without changing the selected kind.
    public static func loadLivePreviewEnabled(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        // If the user has never set this, default to false (opt-in).
        if defaults.object(forKey: livePreviewEnabledKey) == nil {
            return false
        }
        return defaults.bool(forKey: livePreviewEnabledKey)
    }

    public static func saveLivePreviewEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(enabled, forKey: livePreviewEnabledKey)
        notifyChange()
    }

    /// Whether to reduce motion in overlay animations. Defaults to the system
    /// Reduced Motion setting when the user has not explicitly chosen.
    public static func loadReduceMotion(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> Bool {
        if defaults.object(forKey: reduceMotionKey) == nil {
            return NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        return defaults.bool(forKey: reduceMotionKey)
    }

    public static func saveReduceMotion(
        _ reduce: Bool,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(reduce, forKey: reduceMotionKey)
        notifyChange()
    }

    public static func loadHUDStyle(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> RecordingHUDStyle {
        guard let raw = defaults.string(forKey: hudStyleKey),
              let style = RecordingHUDStyle(rawValue: raw) else {
            return .notch
        }
        return style
    }

    public static func saveHUDStyle(
        _ style: RecordingHUDStyle,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(style.rawValue, forKey: hudStyleKey)
        notifyChange()
    }

    public static func loadHUDPosition(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> RecordingHUDPosition {
        guard let raw = defaults.string(forKey: hudPositionKey),
              let position = RecordingHUDPosition(rawValue: raw) else {
            return .topRight
        }
        return position
    }

    public static func saveHUDPosition(
        _ position: RecordingHUDPosition,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(position.rawValue, forKey: hudPositionKey)
        notifyChange()
    }

    public static func loadHUDAppearance(
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) -> RecordingHUDAppearance {
        guard let raw = defaults.string(forKey: hudAppearanceKey),
              let appearance = RecordingHUDAppearance(rawValue: raw) else {
            return .dark
        }
        return appearance
    }

    public static func saveHUDAppearance(
        _ appearance: RecordingHUDAppearance,
        defaults: UserDefaults = RuntimeIdentity.userDefaults()
    ) {
        defaults.set(appearance.rawValue, forKey: hudAppearanceKey)
        notifyChange()
    }

    public static func nsAppearance(
        for hud: RecordingHUDAppearance = loadHUDAppearance()
    ) -> NSAppearance? {
        switch hud {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }

    public static func colorScheme(
        for hud: RecordingHUDAppearance = loadHUDAppearance()
    ) -> ColorScheme? {
        switch hud {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }

}
