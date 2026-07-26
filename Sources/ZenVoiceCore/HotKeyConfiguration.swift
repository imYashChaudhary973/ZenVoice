import Foundation

public struct HotKeyModifiers: OptionSet, Codable, Sendable {
    public let rawValue: UInt

    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    public static let command = HotKeyModifiers(rawValue: 1 << 0)
    public static let control = HotKeyModifiers(rawValue: 1 << 1)
    public static let option = HotKeyModifiers(rawValue: 1 << 2)
    public static let shift = HotKeyModifiers(rawValue: 1 << 3)
    public static let supported: HotKeyModifiers = [
        .command, .control, .option, .shift
    ]

    public var containsOnlySupportedModifiers: Bool {
        rawValue & ~Self.supported.rawValue == 0
    }
}

public struct HotKeyConfiguration: Codable, Equatable, Sendable {
    public let keyCode: UInt32
    public let modifiers: HotKeyModifiers
    public let keyLabel: String

    public init(
        keyCode: UInt32,
        modifiers: HotKeyModifiers,
        keyLabel: String
    ) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public static let dictationDefault = HotKeyConfiguration(
        keyCode: 49,
        modifiers: [.control, .option],
        keyLabel: "Space"
    )

    public static let pasteLastDefault = HotKeyConfiguration(
        keyCode: 9,
        modifiers: [.control, .option],
        keyLabel: "V"
    )

    public static let privateModeDefault = HotKeyConfiguration(
        keyCode: 35,
        modifiers: [.control, .option],
        keyLabel: "P"
    )

    public var displayName: String {
        var symbols: [String] = []
        if modifiers.contains(.control) {
            symbols.append("⌃")
        }
        if modifiers.contains(.option) {
            symbols.append("⌥")
        }
        if modifiers.contains(.shift) {
            symbols.append("⇧")
        }
        if modifiers.contains(.command) {
            symbols.append("⌘")
        }
        symbols.append(keyLabel)
        return symbols.joined(separator: " ")
    }

    // A previous revision additionally required Command or Control here, on
    // the theory that Option is the alternate-character modifier and so
    // Option-only shortcuts are swallowed by the text input system in any app
    // with a focused text field. Measurement disproved it: a Carbon hot key
    // registered on ⌥Space was delivered in Dia and in a terminal alike. The
    // rule only had the effect of invalidating shortcuts people were already
    // using, which `HotKeyPreferences` then silently replaced with the
    // default — so the user's own key stopped responding while the settings
    // screen still displayed it. Do not reintroduce it without evidence.
    public var isValid: Bool {
        !modifiers.isEmpty
            && modifiers.containsOnlySupportedModifiers
            && keyLabel == Self.canonicalLabel(forKeyCode: keyCode)
    }

    public static func canonicalLabel(forKeyCode keyCode: UInt32) -> String? {
        labelsByKeyCode[keyCode]
    }

    private static let labelsByKeyCode: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G",
        6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K",
        41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Escape", 65: ".", 67: "*", 69: "+", 71: "Clear",
        75: "/", 76: "Enter", 78: "-", 81: "=", 82: "0", 83: "1",
        84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7",
        91: "8", 92: "9", 96: "F5", 97: "F6", 98: "F7",
        99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10",
        111: "F12", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2",
        121: "Page Down", 122: "F1", 123: "←", 124: "→",
        125: "↓", 126: "↑"
    ]
}

public enum HoldKeyChoice: String, Codable, CaseIterable, Hashable, Sendable {
    case function
    case leftCommand
    case rightCommand
    case leftOption
    case rightOption
    case leftControl
    case rightControl
    case leftShift
    case rightShift

    public static let `default`: HoldKeyChoice = .function

    public var keyCode: UInt16 {
        switch self {
        case .function: 63
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        case .leftShift: 56
        case .rightShift: 60
        }
    }

    public var displayName: String {
        switch self {
        case .function: "Fn"
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .leftControl: "Left Control"
        case .rightControl: "Right Control"
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        }
    }

    public init?(keyCode: UInt16) {
        guard let choice = Self.allCases.first(where: {
            $0.keyCode == keyCode
        }) else {
            return nil
        }
        self = choice
    }
}
