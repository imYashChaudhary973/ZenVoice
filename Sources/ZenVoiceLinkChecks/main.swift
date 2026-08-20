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

// ZenVoiceLinkChecks — exercises the cross-device link over a real loopback
// TLS-PSK session.
//
// Running a real listener and a real client, rather than calling the frame
// codec directly, is the point: the security property is in the transport. A
// wrong pairing key must fail the handshake, not an application-level check
// that a later change could forget. No network beyond 127.0.0.1 is used.

import Foundation
import ZenVoiceCore
import ZenVoiceLink

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    exit(1)
}

func require(_ condition: Bool, _ message: String) {
    if !condition { fail(message) }
}

/// A port well outside the product default, randomised per run so a lingering
/// socket from a previous run cannot fail the suite.
func checkPort() -> UInt16 {
    UInt16(20_000 + Int.random(in: 0..<20_000))
}

func makePlan(
    title: String,
    risks: [RiskLevel],
    id: UUID = UUID()
) -> GoalPlan {
    GoalPlan(
        id: id,
        title: title,
        transcript: "run the checks and notify me",
        steps: risks.enumerated().map { index, risk in
            GoalStep(
                number: index + 1,
                agent: risk == .high ? .shell : .codex,
                command: risk == .high ? "git push origin main" : "Run checks.",
                description: "Step \(index + 1)",
                workingDirectory: FileManager.default
                    .homeDirectoryForCurrentUser
                    .appendingPathComponent("Developer", isDirectory: true).path,
                dependsOn: index == 0 ? [] : [index],
                plannedRisk: risk,
                computedRisk: risk
            )
        }
    )
}

func makeSummary(
    for plan: GoalPlan,
    goalID: UUID,
    state: GoalState = .awaitingApproval,
    lastSequence: Int = 0,
    awaitingPlanApproval: Bool = true,
    awaitingStepNumber: Int? = nil
) -> LinkGoalSummary {
    LinkGoalSummary(
        goalID: goalID,
        state: state,
        plan: plan,
        planVersion: 1,
        planSHA256: GoalPlanDigest.sha256(plan),
        lastSequence: lastSequence,
        awaitingPlanApproval: awaitingPlanApproval,
        awaitingStepNumber: awaitingStepNumber
    )
}

func makeEvent(
    goalID: UUID,
    sequence: Int,
    type: GoalEventType = .stepOutput,
    message: String = "working"
) -> GoalStatusEvent {
    GoalStatusEvent(
        goalID: goalID,
        sequence: sequence,
        event: type,
        step: 1,
        message: message
    )
}

/// Records what the Mac side was asked to do, so a check can assert that a
/// refused frame never reached the orchestrator at all.
actor HandlerRecorder {
    private(set) var decisions: [ApprovalDecision] = []
    private(set) var cancellations: [UUID] = []

    func recordDecision(_ decision: ApprovalDecision) -> Bool {
        decisions.append(decision)
        return true
    }

    func recordCancel(_ goalID: UUID) -> Bool {
        cancellations.append(goalID)
        return true
    }

    func decisionCount() -> Int { decisions.count }
    func lastDecision() -> ApprovalDecision? { decisions.last }
    func cancelledGoals() -> [UUID] { cancellations }
}

func makeServer(
    broadcaster: GoalEventBroadcaster,
    recorder: HandlerRecorder,
    policy: LinkServerPolicy = LinkServerPolicy()
) -> LinkServer {
    LinkServer(
        broadcaster: broadcaster,
        hostName: "ZenVoice Checks",
        policy: policy,
        handlers: LinkServerHandlers(
            decide: { decision in await recorder.recordDecision(decision) },
            cancel: { goalID in await recorder.recordCancel(goalID) }
        )
    )
}

func waitFor(
    _ description: String,
    timeoutSeconds: Double = 5,
    condition: () async -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
    fail("timed out waiting for \(description)")
}

// MARK: - 1. Pairing keys and codes

do {
    let key = LinkPairingKey.generate()
    let recovered = try LinkPairingKey(pairingCode: key.pairingCode)
    require(recovered == key, "pairing code did not round-trip to the same key")
    require(
        key.pairingCode.contains("-"),
        "pairing code is not grouped for reading aloud"
    )

    // Characters people mistype are folded rather than rejected.
    let folded = try LinkPairingKey(
        pairingCode: key.pairingCode.replacingOccurrences(of: "0", with: "O")
    )
    require(folded == key, "ambiguous characters were not folded")

    do {
        _ = try LinkPairingKey(pairingCode: "not a code")
        fail("an invalid pairing code was accepted")
    } catch LinkPairingError.invalidPairingCode {
    } catch LinkPairingError.invalidKey {}

    do {
        _ = try LinkPairingKey(material: Data(repeating: 0x11, count: 16))
        fail("a short key was accepted")
    } catch LinkPairingError.invalidKey {}

    let store = InMemoryLinkPairingKeyStore()
    require(try store.loadKey() == nil, "an empty store returned a key")
    try store.saveKey(key)
    require(try store.loadKey() == key, "the store lost the key")
    try store.deleteKey()
    require(try store.loadKey() == nil, "the store kept a deleted key")
}

print("ZenVoiceLinkChecks: pairing keys and codes passed")

// MARK: - 2. Framing

do {
    let goalID = UUID()
    let frame = LinkFrame.events([makeEvent(goalID: goalID, sequence: 1)])
    var buffer = try LinkCodec.encode(frame)
    let payloads = try LinkCodec.drain(buffer: &buffer)
    require(payloads.count == 1, "one frame did not drain to one payload")
    require(buffer.isEmpty, "draining left bytes behind")
    require(
        try LinkCodec.decode(payloads[0]) == frame,
        "frame did not round-trip"
    )

    // Coalesced frames plus a partial tail is the normal TCP case.
    var stream = try LinkCodec.encode(frame)
    stream.append(try LinkCodec.encode(.cancel(goalID)))
    let partial = try LinkCodec.encode(frame).prefix(6)
    stream.append(contentsOf: partial)
    let drained = try LinkCodec.drain(buffer: &stream)
    require(drained.count == 2, "coalesced frames did not split")
    require(
        stream.count == partial.count,
        "partial frame was not retained for the next read"
    )

    // A decision is bound to a plan hash, so its bytes must survive exactly.
    let decision = ApprovalDecision(
        planID: UUID(),
        planSHA256: "0f1e2d3c",
        planVersion: 3,
        action: .approved,
        mode: .all,
        coveredStepNumbers: [1, 2],
        decidedAt: Date(timeIntervalSince1970: 1_700_000_000.123_456)
    )
    var decisionBuffer = try LinkCodec.encode(.decision(decision))
    let decisionPayloads = try LinkCodec.drain(buffer: &decisionBuffer)
    require(
        try LinkCodec.decode(decisionPayloads[0]) == .decision(decision),
        "approval decision changed across the wire"
    )

    var oversized = Data([0x00, 0x20, 0x00, 0x00])
    oversized.append(Data(repeating: 0x41, count: 8))
    do {
        _ = try LinkCodec.drain(buffer: &oversized)
        fail("an oversized frame length was accepted")
    } catch LinkTransportError.refused(.frameTooLarge) {}
}

print("ZenVoiceLinkChecks: framing passed")

// MARK: - 3. Paired session, ordering, remote decision

let lowPlan = makePlan(title: "Run checks", risks: [.low, .medium])
let lowGoalID = UUID()
let broadcaster = GoalEventBroadcaster()
let recorder = HandlerRecorder()
let server = makeServer(broadcaster: broadcaster, recorder: recorder)
let serverKey = LinkPairingKey.generate()
let port = checkPort()

try await server.start(key: serverKey, port: port, advertises: false)
await server.publishGoal(makeSummary(for: lowPlan, goalID: lowGoalID))

// A device with the wrong code must fail during the handshake, before it can
// send any frame at all.
do {
    let stranger = LinkClient(
        device: LinkDeviceIdentity(deviceID: UUID(), deviceName: "Stranger")
    )
    _ = try await stranger.connect(
        host: "127.0.0.1",
        port: port,
        key: LinkPairingKey.generate(),
        timeoutSeconds: 4
    )
    fail("an unpaired device completed the handshake")
} catch {
    require(
        error is LinkTransportError,
        "unpaired connection failed with an unexpected error: \(error)"
    )
}
require(
    await recorder.decisionCount() == 0,
    "an unpaired device reached the decision handler"
)

let phone = LinkClient(
    device: LinkDeviceIdentity(deviceID: UUID(), deviceName: "iPhone Checks")
)
let welcome = try await phone.connect(
    host: "127.0.0.1",
    port: port,
    key: serverKey
)
require(
    welcome.protocolVersion == ZenVoiceLink.protocolVersion,
    "welcome carried the wrong protocol version"
)
require(welcome.hostName == "ZenVoice Checks", "welcome did not name the host")
require(
    welcome.activeGoal?.goalID == lowGoalID,
    "welcome did not carry the active goal"
)

try await phone.subscribe()
for sequence in 1...3 {
    await broadcaster.publish(makeEvent(goalID: lowGoalID, sequence: sequence))
}
await waitFor("live events to arrive") {
    await phone.currentSnapshot().events.count >= 3
}
let delivered = await phone.currentSnapshot().events.map(\.sequence)
require(
    delivered == delivered.sorted(),
    "events arrived out of order: \(delivered)"
)

let approval = ApprovalDecision(
    planID: lowPlan.id,
    planSHA256: GoalPlanDigest.sha256(lowPlan),
    planVersion: 1,
    action: .approved,
    mode: .all,
    coveredStepNumbers: lowPlan.steps.map(\.number)
)
let ack = try await phone.decide(approval)
require(ack.accepted, "the Mac refused a remotely approvable plan")
require(
    await recorder.lastDecision() == approval,
    "the decision reaching the Mac differed from the one sent"
)

do {
    _ = try await phone.decide(
        ApprovalDecision(
            planID: lowPlan.id,
            planSHA256: "stale-hash",
            planVersion: 1,
            action: .approved,
            mode: .all,
            coveredStepNumbers: lowPlan.steps.map(\.number)
        )
    )
    fail("a stale plan hash was accepted")
} catch LinkTransportError.refused(.planChanged) {}

let cancelAck = try await phone.cancel(goalID: lowGoalID)
require(cancelAck.accepted, "remote cancel was refused")
require(
    await recorder.cancelledGoals() == [lowGoalID],
    "cancel did not reach the Mac exactly once"
)

print("ZenVoiceLinkChecks: paired session, ordering, and remote decision passed")

// MARK: - 4. High-risk approval stays on the Mac

let highPlan = makePlan(title: "Push", risks: [.medium, .high])
let highGoalID = UUID()
require(
    !makeSummary(for: highPlan, goalID: highGoalID).isRemotelyDecidable,
    "a plan containing a high-risk step was marked remotely decidable"
)
await server.publishGoal(makeSummary(for: highPlan, goalID: highGoalID))
await waitFor("the phone to see the high-risk goal") {
    await phone.currentSnapshot().goal?.goalID == highGoalID
}

do {
    _ = try await phone.decide(
        ApprovalDecision(
            planID: highPlan.id,
            planSHA256: GoalPlanDigest.sha256(highPlan),
            planVersion: 1,
            action: .approved,
            mode: .all,
            coveredStepNumbers: highPlan.steps.map(\.number)
        )
    )
    fail("a high-risk plan was approved from the phone")
} catch LinkTransportError.refused(.highRiskRequiresMac) {}

// Rejection is always safe to accept from a remote surface.
let rejectAck = try await phone.decide(
    ApprovalDecision(
        planID: highPlan.id,
        planSHA256: GoalPlanDigest.sha256(highPlan),
        planVersion: 1,
        action: .rejected
    )
)
require(rejectAck.accepted, "a remote rejection was refused")

print("ZenVoiceLinkChecks: high-risk approval stays on the Mac")

// MARK: - 5. Replay window and bounded ring

let replayGoalID = UUID()
let replayPlan = makePlan(title: "Replay", risks: [.low, .low])
await server.publishGoal(
    makeSummary(
        for: replayPlan,
        goalID: replayGoalID,
        state: .running,
        awaitingPlanApproval: false
    )
)
for sequence in 1...5 {
    await broadcaster.publish(
        makeEvent(
            goalID: replayGoalID,
            sequence: sequence,
            message: "chunk \(sequence)"
        )
    )
}

let rejoining = LinkClient(
    device: LinkDeviceIdentity(deviceID: UUID(), deviceName: "iPhone Rejoin")
)
_ = try await rejoining.connect(host: "127.0.0.1", port: port, key: serverKey)
try await rejoining.subscribe(goalID: replayGoalID, resuming: false)
await waitFor("the full tail to replay") {
    await rejoining.currentSnapshot().events.count >= 5
}
require(
    await rejoining.currentSnapshot().events.map(\.sequence) == [1, 2, 3, 4, 5],
    "replay did not return the ring in order"
)
require(
    await broadcaster.replay(goalID: replayGoalID, after: 3).map(\.sequence)
        == [4, 5],
    "after-sequence replay returned the wrong window"
)

let floodGoalID = UUID()
for sequence in 1...(GoalEventBroadcaster.ringCapacity + 10) {
    await broadcaster.publish(makeEvent(goalID: floodGoalID, sequence: sequence))
}
let ring = await broadcaster.replay(goalID: floodGoalID, after: nil)
require(
    ring.count == GoalEventBroadcaster.ringCapacity,
    "the event ring did not stay bounded"
)
require(
    ring.first?.sequence == 11,
    "the ring dropped the wrong end when it rolled over"
)

print("ZenVoiceLinkChecks: replay window and bounded ring passed")

// MARK: - 6. Policy gate and teardown

let strictBroadcaster = GoalEventBroadcaster()
let strictRecorder = HandlerRecorder()
let strictServer = makeServer(
    broadcaster: strictBroadcaster,
    recorder: strictRecorder,
    policy: LinkServerPolicy(allowsRemoteDecisions: false)
)
let strictKey = LinkPairingKey.generate()
let strictPort = checkPort()
try await strictServer.start(key: strictKey, port: strictPort, advertises: false)
await strictServer.publishGoal(makeSummary(for: lowPlan, goalID: lowGoalID))

let strictPhone = LinkClient(
    device: LinkDeviceIdentity(deviceID: UUID(), deviceName: "iPhone Strict")
)
_ = try await strictPhone.connect(
    host: "127.0.0.1",
    port: strictPort,
    key: strictKey
)
try await strictPhone.subscribe()
do {
    _ = try await strictPhone.decide(approval)
    fail("a decision was accepted while remote decisions were switched off")
} catch LinkTransportError.refused(.remoteDecisionsDisabled) {}
require(
    await strictRecorder.decisionCount() == 0,
    "a refused decision still reached the orchestrator"
)

// Cancel stays available with remote decisions off: stopping work can only
// reduce what runs.
let strictCancel = try await strictPhone.cancel(goalID: lowGoalID)
require(
    strictCancel.accepted,
    "cancel was refused while remote decisions were off"
)

await strictPhone.disconnect()
await strictServer.stop()

await phone.disconnect()
await rejoining.disconnect()
await server.stop()
await waitFor("sessions to be released") {
    await broadcaster.subscriberCount() == 0
}

print("ZenVoiceLinkChecks: policy gate and teardown passed")
print("ZenVoiceLinkChecks: 6 checks passed")
