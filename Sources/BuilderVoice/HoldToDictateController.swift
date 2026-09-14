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
import BuilderVoiceCore

@MainActor
final class HoldToDictateController {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var isPressed = false
    private(set) var isEnabled: Bool
    private(set) var key: HoldKeyChoice

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    init(isEnabled: Bool, key: HoldKeyChoice) {
        self.isEnabled = isEnabled
        self.key = key
        installMonitors()
    }

    func update(isEnabled: Bool, key: HoldKeyChoice) {
        if isPressed {
            isPressed = false
            onRelease?()
        }
        self.isEnabled = isEnabled
        self.key = key
        reinstallMonitors()
    }

    private func installMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handle(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    private func handle(_ event: NSEvent) {
        guard isEnabled else {
            return
        }
        guard let pressed = key.pressTransition(
            eventKeyCode: event.keyCode,
            flags: event.modifierFlags.rawValue,
            currentlyPressed: isPressed
        ) else {
            return
        }
        isPressed = pressed
        if pressed {
            onPress?()
        } else {
            onRelease?()
        }
    }

    private func reinstallMonitors() {
        removeMonitors()
        installMonitors()
    }

    private func removeMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }

    deinit {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
    }
}
