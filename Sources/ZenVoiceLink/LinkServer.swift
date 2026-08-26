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
import Network
#if canImport(ZenVoiceCore)
import ZenVoiceCore
#endif

/// What the Mac allows a paired device to do.
public struct LinkServerPolicy: Sendable {
    /// Remote decisions are a separate switch from the link itself: watching
    /// progress from the phone and being able to approve from it are different
    /// amounts of trust.
    public var allowsRemoteDecisions: Bool
    /// Never true in v1. High-risk steps are Mac-sheet-only by the
    /// non-coercion rule, and this exists to make that a named policy rather
    /// than an implicit gap.
    public var allowsRemoteHighRiskDecisions: Bool

    public init(
        allowsRemoteDecisions: Bool = true,
        allowsRemoteHighRiskDecisions: Bool = false
    ) {
        self.allowsRemoteDecisions = allowsRemoteDecisions
        self.allowsRemoteHighRiskDecisions = allowsRemoteHighRiskDecisions
    }
}

public struct LinkServerHandlers: Sendable {
    public var decide: @Sendable (ApprovalDecision) async -> Bool
    public var cancel: @Sendable (UUID) async -> Bool
    public var connectionsChanged: @Sendable ([LinkDeviceIdentity]) async -> Void

    public init(
        decide: @escaping @Sendable (ApprovalDecision) async -> Bool,
        cancel: @escaping @Sendable (UUID) async -> Bool,
        connectionsChanged: @escaping @Sendable ([LinkDeviceIdentity]) async -> Void = { _ in }
    ) {
        self.decide = decide
        self.cancel = cancel
        self.connectionsChanged = connectionsChanged
    }
}

/// The Mac end of the companion link.
///
/// One listener, N paired devices. Every session is TLS-PSK, so authentication
/// happened before the first frame arrives; the checks in here are about
/// *authorisation* (what a paired device may ask for) and liveness.
public actor LinkServer {
    private final class Session {
        let id = UUID()
        let connection: NWConnection
        var device: LinkDeviceIdentity?
        var subscribedGoalID: UUID?
        var subscribesToActiveGoal = false
        var buffer = Data()
        var broadcastToken: UUID?

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private let broadcaster: GoalEventBroadcaster
    private let hostName: String
    private var policy: LinkServerPolicy
    private let handlers: LinkServerHandlers
    private let queue = DispatchQueue(
        label: "com.zenvoice.app.link.server"
    )

    private var listener: NWListener?
    private var sessions: [UUID: Session] = [:]
    private(set) public var port: UInt16?

    public init(
        broadcaster: GoalEventBroadcaster,
        hostName: String,
        policy: LinkServerPolicy = LinkServerPolicy(),
        handlers: LinkServerHandlers
    ) {
        self.broadcaster = broadcaster
        self.hostName = hostName
        self.policy = policy
        self.handlers = handlers
    }

    public func connectedDevices() -> [LinkDeviceIdentity] {
        sessions.values.compactMap(\.device)
    }

    /// Starts listening. `advertises` controls Bonjour: the iOS Simulator
    /// reaches the host over loopback and does not need it, and a check does
    /// not want to publish a service on the user's network.
    public func start(
        key: LinkPairingKey,
        port requestedPort: UInt16 = ZenVoiceLink.defaultPort,
        advertises: Bool = true
    ) async throws {
        await stop()
        let parameters = LinkParameters.make(key: key)
        let listener: NWListener
        do {
            if let endpointPort = NWEndpoint.Port(rawValue: requestedPort) {
                listener = try NWListener(using: parameters, on: endpointPort)
            } else {
                listener = try NWListener(using: parameters)
            }
        } catch {
            throw LinkTransportError.connectionFailed(error.localizedDescription)
        }
        if advertises {
            listener.service = NWListener.Service(
                name: hostName,
                type: ZenVoiceLink.bonjourServiceType
            )
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            Task { await self.accept(connection) }
        }
        self.listener = listener

        let resumer = LinkOnceResumer()
        let startQueue = queue
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            resumer.succeed(continuation)
                        case .failed(let error):
                            resumer.fail(
                                continuation,
                                with: LinkTransportError.connectionFailed(
                                    error.localizedDescription
                                )
                            )
                        case .cancelled:
                            resumer.fail(
                                continuation,
                                with: LinkTransportError.timedOut
                            )
                        default:
                            break
                        }
                    }
                    listener.start(queue: startQueue)
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                listener.cancel()
                throw LinkTransportError.timedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
        self.port = listener.port?.rawValue
    }

    public func stop() async {
        let activeSessions = Array(sessions.values)
        sessions.removeAll()
        for session in activeSessions {
            if let token = session.broadcastToken {
                await broadcaster.unsubscribe(token)
            }
            session.connection.stateUpdateHandler = nil
            session.connection.cancel()
        }
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        port = nil
        await handlers.connectionsChanged([])
    }

    /// Pushes the current plan view to every device watching this goal.
    public func publishGoal(_ summary: LinkGoalSummary) async {
        await broadcaster.setGoal(summary)
        for session in sessions.values
        where session.subscribesToActiveGoal
            || session.subscribedGoalID == summary.goalID {
            await send(.goal(summary), on: session)
        }
    }

    private func accept(_ connection: NWConnection) async {
        let session = Session(connection: connection)
        let sessionID = session.id
        sessions[sessionID] = session
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed, .cancelled:
                Task { await self.close(sessionID: sessionID) }
            default:
                break
            }
        }
        connection.start(queue: queue)
        await receive(sessionID: sessionID)
    }

    /// Reads by session id rather than by object: the read callback is
    /// `@Sendable`, the session is mutable actor state, and the id is the only
    /// part safe to carry across that boundary.
    private func receive(sessionID: UUID) async {
        guard let session = sessions[sessionID] else { return }
        session.connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: ZenVoiceLink.maximumFrameBytes
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    await self.ingest(data, sessionID: sessionID)
                }
                if isComplete || error != nil {
                    await self.close(sessionID: sessionID)
                } else {
                    await self.receive(sessionID: sessionID)
                }
            }
        }
    }

    private func ingest(_ data: Data, sessionID: UUID) async {
        guard let session = sessions[sessionID] else { return }
        session.buffer.append(data)
        let payloads: [Data]
        do {
            payloads = try LinkCodec.drain(buffer: &session.buffer)
        } catch {
            await send(.error(LinkError(refusal: .frameTooLarge)), on: session)
            await close(sessionID: session.id)
            return
        }
        for payload in payloads {
            guard let frame = try? LinkCodec.decode(payload) else {
                await send(
                    .error(LinkError(refusal: .malformedFrame)),
                    on: session
                )
                continue
            }
            await handle(frame, on: session)
        }
    }

    private func handle(_ frame: LinkFrame, on session: Session) async {
        switch frame {
        case .hello(let hello):
            guard hello.protocolVersion == ZenVoiceLink.protocolVersion else {
                await send(
                    .error(LinkError(refusal: .unsupportedProtocolVersion)),
                    on: session
                )
                await close(sessionID: session.id)
                return
            }
            session.device = hello.device
            let active = await broadcaster.activeGoal()
            await send(
                .welcome(
                    LinkWelcome(hostName: hostName, activeGoal: active)
                ),
                on: session
            )
            await handlers.connectionsChanged(connectedDevices())

        case .subscribe(let subscription):
            session.subscribesToActiveGoal = subscription.goalID == nil
            let resolved: UUID?
            if let requested = subscription.goalID {
                resolved = requested
            } else {
                resolved = await broadcaster.activeGoal()?.goalID
            }
            session.subscribedGoalID = resolved
            if let token = session.broadcastToken {
                await broadcaster.unsubscribe(token)
            }
            let registration = await broadcaster.subscribe(
                goalID: subscription.goalID,
                after: subscription.afterSequence
            ) { [weak self] events in
                guard let self else { return }
                await self.deliver(events, sessionID: session.id)
            }
            session.broadcastToken = registration.token
            if !registration.replay.isEmpty {
                await send(.events(registration.replay), on: session)
            }
            await broadcaster.activate(registration.token)
            guard let resolved else { return }
            if let summary = await broadcaster.goal(resolved) {
                await send(.goal(summary), on: session)
            }

        case .decision(let decision):
            await apply(decision, on: session)

        case .cancel(let goalID):
            // Cancellation is always allowed from a paired device: stopping
            // work can only reduce what runs, and a Stop the user cannot reach
            // is worse than a remote Stop they can.
            let accepted = await handlers.cancel(goalID)
            await send(
                .ack(LinkAck(goalID: goalID, accepted: accepted)),
                on: session
            )

        case .welcome, .goal, .events, .ack, .error:
            // Server-only frames; a client sending one is confused.
            await send(.error(LinkError(refusal: .malformedFrame)), on: session)
        }
    }

    private func apply(_ decision: ApprovalDecision, on session: Session) async {
        guard policy.allowsRemoteDecisions else {
            await send(
                .error(LinkError(refusal: .remoteDecisionsDisabled)),
                on: session
            )
            return
        }
        guard session.device != nil else {
            await send(.error(LinkError(refusal: .notPaired)), on: session)
            return
        }
        // The decision names a plan; the session names the goal it is
        // watching. Both must agree, so a device cannot decide a goal it never
        // subscribed to by guessing a plan id.
        let watched: LinkGoalSummary?
        if session.subscribesToActiveGoal {
            watched = await broadcaster.activeGoal()
        } else if let goalID = session.subscribedGoalID {
            watched = await broadcaster.goal(goalID)
        } else {
            await send(.error(LinkError(refusal: .notSubscribed)), on: session)
            return
        }
        guard let summary = watched, summary.plan.id == decision.planID else {
            await send(.error(LinkError(refusal: .unknownGoal)), on: session)
            return
        }
        guard summary.planSHA256 == decision.planSHA256,
              summary.planVersion == decision.planVersion else {
            await send(.error(LinkError(refusal: .planChanged)), on: session)
            return
        }
        if decision.action == .approved {
            let touchesHighRisk = summary.plan.steps.contains {
                decision.coveredStepNumbers.contains($0.number)
                    && $0.computedRisk == .high
            }
            guard summary.isRemotelyDecidable,
                  !touchesHighRisk || policy.allowsRemoteHighRiskDecisions
            else {
                await send(
                    .error(LinkError(refusal: .highRiskRequiresMac)),
                    on: session
                )
                return
            }
        }
        let accepted = await handlers.decide(decision)
        await send(
            .ack(LinkAck(goalID: summary.goalID, accepted: accepted)),
            on: session
        )
    }

    private func deliver(_ events: [GoalStatusEvent], sessionID: UUID) async {
        guard let session = sessions[sessionID] else { return }
        await send(.events(events), on: session)
    }

    private func send(_ frame: LinkFrame, on session: Session) async {
        guard let data = try? LinkCodec.encode(frame) else { return }
        await withCheckedContinuation { continuation in
            session.connection.send(
                content: data,
                completion: .contentProcessed { _ in
                    continuation.resume()
                }
            )
        }
    }

    private func close(sessionID: UUID) async {
        guard let session = sessions.removeValue(forKey: sessionID) else {
            return
        }
        if let token = session.broadcastToken {
            await broadcaster.unsubscribe(token)
        }
        session.connection.stateUpdateHandler = nil
        session.connection.cancel()
        await handlers.connectionsChanged(connectedDevices())
    }
}
