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
#if canImport(ZenVoiceCore)
import ZenVoiceCore
#endif

/// Fan-out for goal status events, with the replay window the status contract
/// promises a late consumer.
///
/// Nothing in execution depends on a consumer keeping up: publishing appends to
/// a bounded ring and hands each subscriber a copy. A phone that reconnects
/// asks for everything `after:` the last sequence it saw and gets the tail from
/// the ring, so a dropped connection costs ordering, not content.
public actor GoalEventBroadcaster {
    public static let ringCapacity = 500

    public typealias Subscriber = @Sendable ([GoalStatusEvent]) async -> Void

    private struct Ring {
        var events: [GoalStatusEvent] = []

        mutating func append(_ event: GoalStatusEvent) {
            events.append(event)
            if events.count > GoalEventBroadcaster.ringCapacity {
                events.removeFirst(events.count - GoalEventBroadcaster.ringCapacity)
            }
        }
    }

    private struct Subscription {
        let goalID: UUID?
        let deliver: Subscriber
        var active = false
        var pending: [GoalStatusEvent] = []
    }

    private var rings: [UUID: Ring] = [:]
    private var goals: [UUID: LinkGoalSummary] = [:]
    private var activeGoalID: UUID?
    private var subscribers: [UUID: Subscription] = [:]

    public init() {}

    /// Records the plan-level view a companion needs to render or decide. The
    /// server pushes the resulting `goal` frame; the broadcaster only holds it
    /// so a late subscriber can be told what it is looking at.
    public func setGoal(_ summary: LinkGoalSummary) {
        goals[summary.goalID] = summary
        if summary.state.isTerminal {
            if activeGoalID == summary.goalID { activeGoalID = nil }
        } else {
            activeGoalID = summary.goalID
        }
    }

    public func goal(_ goalID: UUID) -> LinkGoalSummary? {
        goals[goalID]
    }

    public func activeGoal() -> LinkGoalSummary? {
        activeGoalID.flatMap { goals[$0] }
    }

    public func publish(_ event: GoalStatusEvent) async {
        rings[event.goalID, default: Ring()].append(event)
        if var summary = goals[event.goalID] {
            summary = LinkGoalSummary(
                goalID: summary.goalID,
                state: summary.state,
                plan: summary.plan,
                planVersion: summary.planVersion,
                planSHA256: summary.planSHA256,
                lastSequence: event.sequence,
                awaitingPlanApproval: summary.awaitingPlanApproval,
                awaitingStepNumber: summary.awaitingStepNumber
            )
            goals[event.goalID] = summary
        }
        let matchingTokens = subscribers.compactMap { token, subscriber in
            subscriber.goalID == nil || subscriber.goalID == event.goalID
                ? token
                : nil
        }
        for token in matchingTokens {
            guard var subscriber = subscribers[token] else { continue }
            if subscriber.active {
                await subscriber.deliver([event])
            } else {
                subscriber.pending.append(event)
                subscribers[token] = subscriber
            }
        }
    }

    /// Events a consumer has not seen yet. `after` is exclusive; `nil` means
    /// "everything still in the ring".
    public func replay(goalID: UUID, after sequence: Int?) -> [GoalStatusEvent] {
        let events = rings[goalID]?.events ?? []
        guard let sequence else { return events }
        return events.filter { $0.sequence > sequence }
    }

    /// Registers a subscriber and captures its replay tail atomically. If
    /// registration and replay are separate actor calls, events published in
    /// between can arrive live and then again in the replay, out of order.
    public func subscribe(
        goalID: UUID?,
        after sequence: Int?,
        deliver: @escaping Subscriber
    ) -> (token: UUID, replay: [GoalStatusEvent]) {
        let token = UUID()
        let replayGoalID = goalID ?? activeGoalID
        let replay: [GoalStatusEvent]
        if let replayGoalID {
            let events = rings[replayGoalID]?.events ?? []
            replay = sequence.map { sequence in
                events.filter { $0.sequence > sequence }
            } ?? events
        } else {
            replay = []
        }
        subscribers[token] = Subscription(
            goalID: goalID,
            deliver: deliver
        )
        return (token, replay)
    }

    /// Delivers anything published while the caller sent its replay, then
    /// switches the subscriber to live delivery without an ordering gap.
    public func activate(_ token: UUID) async {
        while var subscriber = subscribers[token] {
            guard !subscriber.pending.isEmpty else {
                subscriber.active = true
                subscribers[token] = subscriber
                return
            }
            let pending = subscriber.pending
            subscriber.pending.removeAll()
            subscribers[token] = subscriber
            await subscriber.deliver(pending)
        }
    }

    public func unsubscribe(_ token: UUID) {
        subscribers[token] = nil
    }

    public func subscriberCount() -> Int {
        subscribers.count
    }

    /// Drops a finished goal's ring once no consumer can still be catching up.
    public func forget(goalID: UUID) {
        rings[goalID] = nil
        goals[goalID] = nil
        if activeGoalID == goalID { activeGoalID = nil }
    }
}
