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

/// Tokenizer for the Cohere Transcribe INT8 ONNX export.
///
/// The companion `tokens.txt` file lists one `"<token> <id>"` per line.
/// Decoded output uses the SentencePiece word-piece marker `▁` to mark
/// the start of words; it is replaced with a space during detokenization.
struct CohereTokenizer {
    let idToToken: [Int: String]
    let tokenToID: [String: Int]

    init(contentsOf url: URL) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        var idToToken: [Int: String] = [:]
        var tokenToID: [String: Int] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.rsplit(separator: " ", maxSplits: 1)
            guard parts.count == 2,
                  let id = Int(parts[1].trimmingCharacters(in: .whitespaces))
            else {
                continue
            }
            let token = String(parts[0]).trimmingCharacters(in: .whitespaces)
            idToToken[id] = token
            tokenToID[token] = id
        }
        guard !idToToken.isEmpty else {
            throw CohereTokenizerError.emptyVocabulary
        }
        self.idToToken = idToToken
        self.tokenToID = tokenToID
    }

    func token(for id: Int) -> String? {
        idToToken[id]
    }

    func id(for token: String) -> Int? {
        tokenToID[token]
    }

    /// Converts generated token IDs to a human-readable transcript.
    func decode(_ ids: [Int], skipSpecial: Bool = true) -> String {
        let tokens = ids.compactMap { idToToken[$0] }
        let cleaned: [String]
        if skipSpecial {
            cleaned = tokens.filter { !$0.hasPrefix("<|") }
        } else {
            cleaned = tokens
        }
        let joined = cleaned
            .map { $0.replacingOccurrences(of: "\u{2581}", with: " ") }
            .joined()
        return joined.trimmingCharacters(in: .whitespaces)
    }
}

enum CohereTokenizerError: LocalizedError {
    case emptyVocabulary

    var errorDescription: String? {
        switch self {
        case .emptyVocabulary:
            return "The Cohere tokenizer vocabulary file is empty or malformed."
        }
    }
}

private extension String {
    /// Split from the right, matching Python's `rsplit(sep, maxSplits)`.
    func rsplit(separator: Character, maxSplits: Int) -> [Substring] {
        var result: [Substring] = []
        var remaining = self[...]
        var splits = 0
        while let index = remaining.lastIndex(of: separator) {
            if splits >= maxSplits {
                break
            }
            result.insert(remaining[index...].dropFirst(), at: 0)
            remaining = remaining[..<index]
            splits += 1
        }
        result.insert(remaining, at: 0)
        return result
    }
}
