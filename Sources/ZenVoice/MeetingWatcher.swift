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
import Combine
import EventKit
import Foundation
import ZenVoiceCore

/// Calendar + huddle detection. Fires `onDetected` only — never records.
@MainActor
final class MeetingWatcher: ObservableObject {
    struct Detection: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case calendar(eventID: String, url: String?)
            case huddle(bundleID: String)
        }

        let kind: Kind
        let title: String
        let detectedAt: Date
    }

    var onDetected: ((Detection) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var emitted: Set<String> = []

    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(
            withTimeInterval: 5,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.poll()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        Task { [weak self] in
            await self?.requestAccess()
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        emitted.removeAll()
    }

    private func requestAccess() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        if status == .fullAccess { return }
        guard status == .notDetermined else { return }
        _ = try? await store.requestFullAccessToEvents()
    }

    private func poll() {
        var live: Set<String> = []
        pollCalendar(into: &live)
        pollHuddles(into: &live)
        emitted.formIntersection(live)
    }

    private func pollCalendar(into live: inout Set<String>) {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess
        else { return }
        let start = Date()
        let end = start.addingTimeInterval(15 * 60)
        let predicate = store.predicateForEvents(
            withStart: start,
            end: end,
            calendars: nil
        )
        for event in store.events(matching: predicate) {
            let url = meetingURL(in: event)
            guard url != nil else { continue }
            let eventID = event.eventIdentifier ?? event.calendarItemIdentifier
            let key = "cal:\(eventID)"
            emit(
                Detection(
                    kind: .calendar(eventID: eventID, url: url),
                    title: event.title ?? "Meeting",
                    detectedAt: Date()
                ),
                key: key,
                live: &live
            )
        }
    }

    private func pollHuddles(into live: inout Set<String>) {
        // ponytail: running app = huddle; window-title parsing if false positives matter
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier,
                  MeetingDetection.isMeetingApp(bundleID: bundleID)
            else { continue }
            emit(
                Detection(
                    kind: .huddle(bundleID: bundleID),
                    title: app.localizedName ?? bundleID,
                    detectedAt: Date()
                ),
                key: "huddle:\(bundleID)",
                live: &live
            )
        }
    }

    private func meetingURL(in event: EKEvent) -> String? {
        var parts: [String] = []
        if let notes = event.notes { parts.append(notes) }
        if let url = event.url?.absoluteString { parts.append(url) }
        if let location = event.location { parts.append(location) }
        return MeetingDetection.meetingURL(in: parts.joined(separator: "\n"))
    }

    private func emit(
        _ detection: Detection,
        key: String,
        live: inout Set<String>
    ) {
        live.insert(key)
        guard emitted.insert(key).inserted else { return }
        onDetected?(detection)
    }
}
