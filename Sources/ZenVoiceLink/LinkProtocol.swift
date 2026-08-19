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

/// Wire contract for the ZenVoice cross-device link.
///
/// The link carries the *existing* agentic envelope — `GoalStatusEvent`,
/// `GoalPlan`, `ApprovalDecision` — rather than a second schema, exactly as
/// [AGENTIC_STATUS_STREAMING.md](../../docs/AGENTIC_STATUS_STREAMING.md) fixed
/// it. Frames are length-prefixed JSON inside a TLS-PSK session, so the
/// pairing key both encrypts and authenticates: an unpaired peer cannot
/// complete the handshake, let alone send a frame.
public enum ZenVoiceLink {
    /// Bumped only for an incompatible frame change. A peer that does not
    /// recognise the version is refused rather than guessed at.
    public static let protocolVersion = 1

    /// Bonjour type used to find the Mac on a local network.
    public static let bonjourServiceType = "_zenvoice-link._tcp"

    /// Default TCP port. Fixed so the companion can be pointed at a Mac by
    /// hand when Bonjour is unavailable (a common case on guest Wi-Fi and in
    /// the iOS Simulator, where the host is reached over loopback).
    public static let defaultPort: UInt16 = 51_789

    /// Hard ceiling on a single frame. Step output is already capped and
    /// chunked upstream; anything larger is a bug or an attack.
    public static let maximumFrameBytes = 1 << 20
}

public struct LinkDeviceIdentity: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let deviceName: String

    public init(deviceID: UUID, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}

public struct LinkHello: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let device: LinkDeviceIdentity

    public init(
        protocolVersion: Int = ZenVoiceLink.protocolVersion,
        device: LinkDeviceIdentity
    ) {
        self.protocolVersion = protocolVersion
        self.device = device
    }
}

public struct LinkWelcome: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let hostName: String
    /// The goal the Mac is working on right now, if any.
    public let activeGoal: LinkGoalSummary?

    public init(
        protocolVersion: Int = ZenVoiceLink.protocolVersion,
        hostName: String,
        activeGoal: LinkGoalSummary?
    ) {
        self.protocolVersion = protocolVersion
        self.hostName = hostName
        self.activeGoal = activeGoal
    }
}

/// What the phone needs to render a goal without holding the Mac's whole
/// record: identity, plan bytes it may be asked to approve, and how far the
/// event stream has advanced.
public struct LinkGoalSummary: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID { goalID }

    public let goalID: UUID
    public let state: GoalState
    public let plan: GoalPlan
    public let planVersion: Int
    public let planSHA256: String
    public let lastSequence: Int
    /// True when the Mac is waiting for a plan-level decision.
    public let awaitingPlanApproval: Bool
    /// Set when the Mac is waiting on a single step's approval.
    public let awaitingStepNumber: Int?

    public init(
        goalID: UUID,
        state: GoalState,
        plan: GoalPlan,
        planVersion: Int,
        planSHA256: String,
        lastSequence: Int,
        awaitingPlanApproval: Bool,
        awaitingStepNumber: Int?
    ) {
        self.goalID = goalID
        self.state = state
        self.plan = plan
        self.planVersion = planVersion
        self.planSHA256 = planSHA256
        self.lastSequence = lastSequence
        self.awaitingPlanApproval = awaitingPlanApproval
        self.awaitingStepNumber = awaitingStepNumber
    }

    /// Whether this plan may be decided from the phone at all.
    ///
    /// Mirrors the non-coercion rule: a remote surface can only approve classes
    /// the user has already accepted as remotely approvable — low and medium.
    /// A high-risk step is Mac-sheet-only, so a plan containing one can never
    /// be approved from the phone, and a per-step prompt for a high-risk step
    /// is never offered remotely.
    public var isRemotelyDecidable: Bool {
        !plan.steps.contains { $0.computedRisk == .high }
    }
}

public struct LinkSubscription: Codable, Equatable, Sendable {
    public let goalID: UUID?
    public let afterSequence: Int?

    public init(goalID: UUID? = nil, afterSequence: Int? = nil) {
        self.goalID = goalID
        self.afterSequence = afterSequence
    }
}

public enum LinkRefusal: String, Codable, Sendable {
    case unsupportedProtocolVersion
    case notPaired
    case frameTooLarge
    case malformedFrame
    case unknownGoal
    case highRiskRequiresMac
    case planChanged
    case remoteDecisionsDisabled
    case notSubscribed

    public var message: String {
        switch self {
        case .unsupportedProtocolVersion:
            return "This ZenVoice companion speaks a different link version."
        case .notPaired:
            return "This device is not paired with the Mac."
        case .frameTooLarge:
            return "The message was larger than the link allows."
        case .malformedFrame:
            return "The message could not be read."
        case .unknownGoal:
            return "That goal is no longer active on the Mac."
        case .highRiskRequiresMac:
            return "High-risk steps must be approved on the Mac."
        case .planChanged:
            return "The plan changed on the Mac; review the new version."
        case .remoteDecisionsDisabled:
            return "Approving from another device is switched off."
        case .notSubscribed:
            return "Subscribe to a goal before sending decisions."
        }
    }
}

public struct LinkError: Codable, Equatable, Sendable {
    public let refusal: LinkRefusal
    public let detail: String?

    public init(refusal: LinkRefusal, detail: String? = nil) {
        self.refusal = refusal
        self.detail = detail
    }
}

public struct LinkAck: Codable, Equatable, Sendable {
    public let goalID: UUID
    public let accepted: Bool

    public init(goalID: UUID, accepted: Bool) {
        self.goalID = goalID
        self.accepted = accepted
    }
}

/// One frame in either direction. Encoded as a single JSON object with a
/// `kind` discriminator so an unknown frame from a newer peer is a clean
/// refusal rather than a decode crash.
public enum LinkFrame: Codable, Equatable, Sendable {
    case hello(LinkHello)
    case welcome(LinkWelcome)
    case subscribe(LinkSubscription)
    case goal(LinkGoalSummary)
    case events([GoalStatusEvent])
    case decision(ApprovalDecision)
    case cancel(UUID)
    case ack(LinkAck)
    case error(LinkError)

    private enum CodingKeys: String, CodingKey {
        case kind
        case hello, welcome, subscribe, goal, events, decision, cancel, ack, error
    }

    private enum Kind: String, Codable {
        case hello, welcome, subscribe, goal, events, decision, cancel, ack, error
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .hello(let value):
            try container.encode(Kind.hello, forKey: .kind)
            try container.encode(value, forKey: .hello)
        case .welcome(let value):
            try container.encode(Kind.welcome, forKey: .kind)
            try container.encode(value, forKey: .welcome)
        case .subscribe(let value):
            try container.encode(Kind.subscribe, forKey: .kind)
            try container.encode(value, forKey: .subscribe)
        case .goal(let value):
            try container.encode(Kind.goal, forKey: .kind)
            try container.encode(value, forKey: .goal)
        case .events(let value):
            try container.encode(Kind.events, forKey: .kind)
            try container.encode(value, forKey: .events)
        case .decision(let value):
            try container.encode(Kind.decision, forKey: .kind)
            try container.encode(value, forKey: .decision)
        case .cancel(let value):
            try container.encode(Kind.cancel, forKey: .kind)
            try container.encode(value, forKey: .cancel)
        case .ack(let value):
            try container.encode(Kind.ack, forKey: .kind)
            try container.encode(value, forKey: .ack)
        case .error(let value):
            try container.encode(Kind.error, forKey: .kind)
            try container.encode(value, forKey: .error)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .hello:
            self = .hello(try container.decode(LinkHello.self, forKey: .hello))
        case .welcome:
            self = .welcome(
                try container.decode(LinkWelcome.self, forKey: .welcome)
            )
        case .subscribe:
            self = .subscribe(
                try container.decode(LinkSubscription.self, forKey: .subscribe)
            )
        case .goal:
            self = .goal(
                try container.decode(LinkGoalSummary.self, forKey: .goal)
            )
        case .events:
            self = .events(
                try container.decode([GoalStatusEvent].self, forKey: .events)
            )
        case .decision:
            self = .decision(
                try container.decode(ApprovalDecision.self, forKey: .decision)
            )
        case .cancel:
            self = .cancel(try container.decode(UUID.self, forKey: .cancel))
        case .ack:
            self = .ack(try container.decode(LinkAck.self, forKey: .ack))
        case .error:
            self = .error(try container.decode(LinkError.self, forKey: .error))
        }
    }
}

/// Length-prefixed JSON framing shared by both ends.
///
/// Whole-microsecond dates in both directions: an `ApprovalDecision` is bound
/// to a plan hash that must survive the crossing byte-for-byte, and decimal
/// seconds do not round-trip a `Date` exactly.
public enum LinkCodec {
    public static func encode(_ frame: LinkFrame) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = AgenticTimestamp.encoding
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(frame)
        var length = UInt32(payload.count).bigEndian
        var framed = Data(
            bytes: &length,
            count: MemoryLayout<UInt32>.size
        )
        framed.append(payload)
        return framed
    }

    public static func decode(_ payload: Data) throws -> LinkFrame {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = AgenticTimestamp.decoding
        return try decoder.decode(LinkFrame.self, from: payload)
    }

    /// Splits a growing byte buffer into whole frames, leaving any partial
    /// frame in `buffer` for the next read.
    public static func drain(
        buffer: inout Data
    ) throws -> [Data] {
        var payloads: [Data] = []
        let headerSize = MemoryLayout<UInt32>.size
        while buffer.count >= headerSize {
            let header = buffer.prefix(headerSize)
            let length = Int(
                header.withUnsafeBytes { raw in
                    UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self))
                }
            )
            guard length > 0, length <= ZenVoiceLink.maximumFrameBytes else {
                throw LinkTransportError.refused(.frameTooLarge)
            }
            guard buffer.count >= headerSize + length else { break }
            let start = buffer.index(buffer.startIndex, offsetBy: headerSize)
            let end = buffer.index(start, offsetBy: length)
            payloads.append(Data(buffer[start..<end]))
            buffer = Data(buffer[end...])
        }
        return payloads
    }
}

public enum LinkTransportError: LocalizedError, Equatable {
    case refused(LinkRefusal)
    case notConnected
    case handshakeFailed(String)
    case connectionFailed(String)
    case timedOut

    public var errorDescription: String? {
        switch self {
        case .refused(let refusal):
            return refusal.message
        case .notConnected:
            return "The companion link is not connected."
        case .handshakeFailed(let reason):
            return "The companion link handshake failed: \(reason)"
        case .connectionFailed(let reason):
            return "The companion link could not connect: \(reason)"
        case .timedOut:
            return "The companion link timed out."
        }
    }
}

/// Resumes a continuation exactly once from `Network.framework` state
/// callbacks.
///
/// A connection can report `ready` and then `failed`, and a cancelled listener
/// reports `cancelled` after either. Resuming a continuation twice is a crash,
/// and a captured `var` is a data race under strict concurrency, so the flag
/// lives behind a lock in one shared place rather than in each call site.
final class LinkOnceResumer: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    private func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if resumed { return false }
        resumed = true
        return true
    }

    func succeed(_ continuation: CheckedContinuation<Void, Error>) {
        guard claim() else { return }
        continuation.resume()
    }

    func fail(
        _ continuation: CheckedContinuation<Void, Error>,
        with error: Error
    ) {
        guard claim() else { return }
        continuation.resume(throwing: error)
    }
}
