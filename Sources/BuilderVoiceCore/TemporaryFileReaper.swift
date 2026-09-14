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

/// Owns temporary files for a multi-step operation. `removeAll()` deletes
/// everything still retained — including files registered after close, so a
/// late-arriving part cannot leak.
public final class TemporaryFileReaper: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    private var closed = false
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func retain(_ url: URL) {
        lock.lock()
        if closed {
            lock.unlock()
            try? fileManager.removeItem(at: url)
            return
        }
        urls.append(url)
        lock.unlock()
    }

    public func forget(_ url: URL) {
        lock.lock()
        urls.removeAll { $0 == url }
        lock.unlock()
    }

    public func removeAll() {
        lock.lock()
        closed = true
        let leftover = urls
        urls = []
        lock.unlock()
        for url in leftover {
            try? fileManager.removeItem(at: url)
        }
    }
}
