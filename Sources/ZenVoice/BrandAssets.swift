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

enum BrandAssets {
    static let zenLogo: NSImage? = {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("ZenLogo.png"),
            URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent("Resources/Brand/ZenLogo.png")
        ].compactMap { $0 }

        guard let url = candidates.first(where: {
            fileManager.fileExists(atPath: $0.path(percentEncoded: false))
        }) else {
            return nil
        }

        return NSImage(contentsOf: url)
    }()
}
