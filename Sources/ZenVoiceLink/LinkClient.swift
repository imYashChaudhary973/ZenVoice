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

/// The consuming end of the link: the iPhone companion in production, and the
/// link checks on the Mac.
///
/// Deliberately the same type in both places. A phone-only client would be a
/// second implementation of the contract, and the second implementation is
/// where drift lives.
public actor LinkClient {
    public struct Snapshot: Sendable, Equatable {
        public var hostName: String?
        public var goal: LinkGoalSummary?
        public var events: [GoalStatusEvent]
        public var lastRefusal: LinkRefusal?

        public init(
            hostName: String? = nil,
            goal: LinkGoalSummary? = nil,
            events: [GoalStatusEvent] = [],
            lastRefusal: LinkRefusal? = nil
        ) {
            self.hostName = hostName
            self.goal = goal
            self.events = events
            self.lastRefusal = lastRefusal
        }
    }

    public typealias SnapshotHandler = @Sendable (Snapshot) async -> Void

    private let device: LinkDeviceIdentity
    private let queue = DispatchQueue(
        label: "com.zenvoice.app.link.client"
    )

    private var connection: NWConnection?
    private var buffer = Data()
    private var snapshot = Snapshot()
    private var observers: [UUID: SnapshotHandler] = [:]
    private var welcomeContinuation: CheckedContinuation<LinkWelcome, Error>?
    private var ackContinuations: [CheckedContinuation<LinkAck, Error>] = []
    private var pendingWelcome: Result<LinkWelcome, Error>?
    private var pendingAcks: [Result<LinkAck, Error>] = []
    private var lastSeenSequence: Int?

    public init(device: LinkDeviceIdentity) {
        self.device = device
    }

    @discardableResult
    public func observe(_ handler: @escaping SnapshotHandler) -> UUID {
        let token = UUID()
        observers[token] = handler
        return token
    }

    public func currentSnapshot() -> Snapshot {
        snapshot
    }

    /// Connects and completes the handshake. Throws rather than retrying: a
    /// wrong pairing code must read as "wrong code", not as an endless spinner.
    @discardableResult
    public func connect(
        host: String,
        port: UInt16,
        key: LinkPairingKey,
        timeoutSeconds: Double = 10
    ) async throws -> LinkWelcome {
        disconnect()
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        let connection = NWConnection(
            to: endpoint,
            using: LinkParameters.make(key: key)
        )
        self.connection = connection

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                try await self?.waitForReady(connection)
            }
            group.addTask {
                try await Task.sleep(for: .seconds(timeoutSeconds))
                connection.cancel()
                throw LinkTransportError.timedOut
            }
            try await group.next()
            group.cancelAll()
        }

        await receive()
        return try await withThrowingTaskGroup(of: LinkWelcome.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw LinkTransportError.notConnected }
                return try await self.sendHelloAndAwaitWelcome()
            }
            group.addTask { [weak self] in
                try await Task.sleep(for: .seconds(timeoutSeconds))
                await self?.timeoutWelcome()
                throw LinkTransportError.timedOut
            }
            guard let welcome = try await group.next() else {
                throw LinkTransportError.timedOut
            }
            group.cancelAll()
            return welcome
        }
    }

    public func disconnect() {
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        buffer.removeAll()
        pendingWelcome = nil
        pendingAcks.removeAll()
        if let continuation = welcomeContinuation {
            welcomeContinuation = nil
            continuation.resume(throwing: LinkTransportError.notConnected)
        }
        let pending = ackContinuations
        ackContinuations.removeAll()
        for continuation in pending {
            continuation.resume(throwing: LinkTransportError.notConnected)
        }
    }

    public func subscribe(goalID: UUID? = nil, resuming: Bool = true) async throws {
        try await send(
            .subscribe(
                LinkSubscription(
                    goalID: goalID,
                    afterSequence: resuming ? lastSeenSequence : nil
                )
            )
        )
    }

    /// Sends a decision and waits for the Mac's ack, so the phone can show
    /// "approved" only once the Mac has actually accepted it.
    @discardableResult
    public func decide(
        _ decision: ApprovalDecision,
        timeoutSeconds: Double = 10
    ) async throws -> LinkAck {
        try await sendAwaitingAck(
            .decision(decision),
            timeoutSeconds: timeoutSeconds
        )
    }

    @discardableResult
    public func cancel(
        goalID: UUID,
        timeoutSeconds: Double = 10
    ) async throws -> LinkAck {
        try await sendAwaitingAck(
            .cancel(goalID),
            timeoutSeconds: timeoutSeconds
        )
    }

    private func sendAwaitingAck(
        _ frame: LinkFrame,
        timeoutSeconds: Double
    ) async throws -> LinkAck {
        try await send(frame)
        return try await withThrowingTaskGroup(of: LinkAck.self) { group in
            group.addTask { [weak self] in
                guard let self else { throw LinkTransportError.notConnected }
                return try await self.awaitAck()
            }
            group.addTask { [weak self] in
                try await Task.sleep(for: .seconds(timeoutSeconds))
                await self?.timeoutAcks()
                throw LinkTransportError.timedOut
            }
            guard let ack = try await group.next() else {
                throw LinkTransportError.timedOut
            }
            group.cancelAll()
            return ack
        }
    }

    private func awaitAck() async throws -> LinkAck {
        if !pendingAcks.isEmpty {
            return try pendingAcks.removeFirst().get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            ackContinuations.append(continuation)
        }
    }

    private func sendHelloAndAwaitWelcome() async throws -> LinkWelcome {
        try await send(.hello(LinkHello(device: device)))
        if let pendingWelcome {
            self.pendingWelcome = nil
            return try pendingWelcome.get()
        }
        return try await withCheckedThrowingContinuation { continuation in
            welcomeContinuation = continuation
        }
    }

    private func timeoutWelcome() {
        if let continuation = welcomeContinuation {
            welcomeContinuation = nil
            continuation.resume(throwing: LinkTransportError.timedOut)
        }
        connection?.cancel()
    }

    private func timeoutAcks() {
        let pending = ackContinuations
        ackContinuations.removeAll()
        for continuation in pending {
            continuation.resume(throwing: LinkTransportError.timedOut)
        }
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        let resumer = LinkOnceResumer()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
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
                    resumer.fail(continuation, with: LinkTransportError.notConnected)
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func send(_ frame: LinkFrame) async throws {
        guard let connection else { throw LinkTransportError.notConnected }
        let data = try LinkCodec.encode(frame)
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(
                            throwing: LinkTransportError.connectionFailed(
                                error.localizedDescription
                            )
                        )
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    private func receive() async {
        guard let connection else { return }
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: ZenVoiceLink.maximumFrameBytes
        ) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task {
                if let data, !data.isEmpty {
                    await self.ingest(data)
                }
                if isComplete || error != nil {
                    await self.handleDisconnect()
                } else {
                    await self.receive()
                }
            }
        }
    }

    private func handleDisconnect() async {
        disconnect()
        await publishSnapshot()
    }

    private func ingest(_ data: Data) async {
        buffer.append(data)
        let payloads = (try? LinkCodec.drain(buffer: &buffer)) ?? []
        for payload in payloads {
            guard let frame = try? LinkCodec.decode(payload) else { continue }
            await handle(frame)
        }
    }

    private func handle(_ frame: LinkFrame) async {
        switch frame {
        case .welcome(let welcome):
            snapshot.hostName = welcome.hostName
            snapshot.goal = welcome.activeGoal
            if let continuation = welcomeContinuation {
                welcomeContinuation = nil
                continuation.resume(returning: welcome)
            } else {
                pendingWelcome = .success(welcome)
            }
        case .goal(let summary):
            snapshot.goal = summary
        case .events(let events):
            snapshot.events.append(contentsOf: events)
            if snapshot.events.count > GoalEventBroadcaster.ringCapacity {
                snapshot.events.removeFirst(
                    snapshot.events.count - GoalEventBroadcaster.ringCapacity
                )
            }
            if let last = events.map(\.sequence).max() {
                lastSeenSequence = max(lastSeenSequence ?? 0, last)
            }
        case .ack(let ack):
            let pending = ackContinuations
            ackContinuations.removeAll()
            if pending.isEmpty {
                pendingAcks.append(.success(ack))
            } else {
                for continuation in pending {
                    continuation.resume(returning: ack)
                }
            }
        case .error(let error):
            snapshot.lastRefusal = error.refusal
            let refusal = LinkTransportError.refused(error.refusal)
            let pending = ackContinuations
            ackContinuations.removeAll()
            if pending.isEmpty {
                pendingAcks.append(.failure(refusal))
            } else {
                for continuation in pending {
                    continuation.resume(throwing: refusal)
                }
            }
            if let continuation = welcomeContinuation {
                welcomeContinuation = nil
                continuation.resume(throwing: refusal)
            } else if snapshot.hostName == nil {
                pendingWelcome = .failure(refusal)
            }
        case .hello, .subscribe, .decision, .cancel:
            break
        }
        await publishSnapshot()
    }

    private func publishSnapshot() async {
        let current = snapshot
        for handler in observers.values {
            await handler(current)
        }
    }
}
