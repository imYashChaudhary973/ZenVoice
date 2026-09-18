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
import ZenVoiceCore

/// Owns the snippet list for the Snippets screen. Every mutation persists
/// immediately, so the dictation pipeline reads the same store.
@MainActor
final class SnippetsViewModel: ObservableObject {
    @Published private(set) var snippets: [VoiceSnippet]
    /// What the user typed into the TRY IT box.
    @Published var testPhrase = ""

    init() {
        snippets = SnippetPreferences.load()
    }

    /// The snippet that would fire for the current test phrase, if any.
    var testMatch: SnippetMatch? {
        SnippetEngine().match(testPhrase, snippets: snippets)
    }

    func add(name: String, trigger: String, content: String) {
        let snippet = VoiceSnippet(
            name: name.trimmingCharacters(in: .whitespaces),
            trigger: trigger.trimmingCharacters(in: .whitespaces),
            content: content,
            enabled: true
        )
        snippets.append(snippet)
        persist()
    }

    func update(_ snippet: VoiceSnippet) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        snippets[index] = snippet
        persist()
    }

    func delete(_ snippet: VoiceSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        persist()
    }

    func setEnabled(_ snippet: VoiceSnippet, enabled: Bool) {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id })
        else { return }
        snippets[index].enabled = enabled
        persist()
    }

    private func persist() {
        SnippetPreferences.save(snippets)
    }
}
