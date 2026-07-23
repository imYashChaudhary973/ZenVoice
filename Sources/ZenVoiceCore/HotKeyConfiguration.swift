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

    public var isValid: Bool {
        !modifiers.isEmpty && !keyLabel.isEmpty
    }
}
