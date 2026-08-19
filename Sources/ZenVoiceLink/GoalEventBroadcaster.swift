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

    private var rings: [UUID: Ring] = [:]
    private var goals: [UUID: LinkGoalSummary] = [:]
    private var activeGoalID: UUID?
    private var subscribers: [UUID: (goalID: UUID?, deliver: Subscriber)] = [:]

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
        for (_, subscriber) in subscribers
        where subscriber.goalID == nil || subscriber.goalID == event.goalID {
            await subscriber.deliver([event])
        }
    }

    /// Events a consumer has not seen yet. `after` is exclusive; `nil` means
    /// "everything still in the ring".
    public func replay(goalID: UUID, after sequence: Int?) -> [GoalStatusEvent] {
        let events = rings[goalID]?.events ?? []
        guard let sequence else { return events }
        return events.filter { $0.sequence > sequence }
    }

    @discardableResult
    public func subscribe(
        goalID: UUID?,
        deliver: @escaping Subscriber
    ) -> UUID {
        let token = UUID()
        subscribers[token] = (goalID: goalID, deliver: deliver)
        return token
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
