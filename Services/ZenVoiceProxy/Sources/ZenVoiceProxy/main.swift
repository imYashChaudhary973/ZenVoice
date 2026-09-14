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

guard let token = ProcessInfo.processInfo.environment["ZENVOICE_PROXY_TOKEN"],
      !token.isEmpty
else {
    fputs("ZENVOICE_PROXY_TOKEN is required\n", stderr)
    exit(1)
}

let port = UInt16(ProcessInfo.processInfo.environment["ZENVOICE_PROXY_PORT"] ?? "") ?? 8787
let server = ProxyServer(token: token, port: port)
do {
    try server.start()
} catch {
    fputs("failed to start: \(error)\n", stderr)
    exit(1)
}

withExtendedLifetime(server) {
    dispatchMain()
}
