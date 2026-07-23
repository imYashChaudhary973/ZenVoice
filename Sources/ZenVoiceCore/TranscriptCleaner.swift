import Foundation

public struct TranscriptCleaner {
    public init() {}

    public func clean(_ transcript: String) -> String {
        var result = transcript
            .replacingOccurrences(of: #"\[[^\]]+\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let fillerPattern = #"(?i)(^|(?<=[.!?]\s))(?:(?:um+|uh+|erm+)[,.\s]+)+"#
        result = result.replacingOccurrences(
            of: fillerPattern,
            with: "$1",
            options: .regularExpression
        )

        guard !result.isEmpty else {
            return ""
        }

        let first = result.prefix(1).uppercased()
        return first + result.dropFirst()
    }
}
