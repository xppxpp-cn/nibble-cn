import Foundation

final class TestClock {
    var jobs: [(TimeInterval, () -> Void)] = []
    func schedule(_ delay: TimeInterval, _ work: @escaping () -> Void) { jobs.append((delay, work)) }
    func next() { if !jobs.isEmpty { jobs.removeFirst().1() } }
}

final class StatefulMouse: HIDPPTransport {
    var onReport: (([UInt8]) -> Void)?
    var onRemoval: (() -> Void)?
    var table = Array(UInt8(1)...UInt8(16))
    var diverted: Set<UInt16> = []
    var spy = false
    var offline = false
    var failStart = false
    var writes = 0
    var calls = 0
    var mx = false
    var featureIndex: UInt8?
    var seenFeatures: [UInt8] = []
    func roundTrip(request p: [UInt8], preferLong: Bool, timeout: TimeInterval,
                   match: ([UInt8]) -> Bool) throws -> [UInt8] {
        calls += 1
        seenFeatures.append(p[1])
        if offline { throw HIDPPError.timeout }
        let fn = p[2] >> 4
        var r: [UInt8] = [0, 0, 0]
        if p[1] == 0 { r = [featureIndex ?? (mx ? 7 : 6), 0, 0] }
        else if mx {
            let cid = UInt16(p[3]) << 8 | UInt16(p[4])
            if fn == 3 {
                writes += 1
                if p[5] & 1 != 0 { diverted.insert(cid) } else { diverted.remove(cid) }
            } else if fn == 2 { r = [p[3], p[4], diverted.contains(cid) ? 1 : 0] }
        } else {
            switch fn {
            case 1: if failStart { throw HIDPPError.timeout }; spy = true; writes += 1
            case 2: spy = false; writes += 1
            case 3: r = table
            case 4: table = Array(p.dropFirst(3)); writes += 1
            default: break
            }
        }
        let response = Array(p.prefix(3)) + r
        expect(match(response), "fake response matches request")
        return response
    }
}

func pumpRecovery() {
    let end = Date().addingTimeInterval(0.6)
    while Date() < end { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
}

func runRecoveryTests() {
    let realStateURL = EngineState.url
    let stateURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nibble-test-state-\(UUID().uuidString).json")
    EngineState.url = stateURL
    defer {
        _ = EngineState.read() // drain asynchronous diagnostics before restoring the real URL
        EngineState.url = realStateURL
        try? FileManager.default.removeItem(at: stateURL)
    }
    section("recovery state machine")
    do {
        let clock = TestClock()
        var applies = 0, reconnects = 0
        var fail = true
        var states: [Bool] = []
        let recovery = RemapRecovery(schedule: clock.schedule, apply: {
            applies += 1
            if fail { throw HIDPPError.timeout }
        }, state: { ok, _ in states.append(ok) }, reconnect: { reconnects += 1 })
        recovery.request(reason: "0x41")
        recovery.request(reason: "duplicate wake")
        expectEqual(clock.jobs.count, 1, "duplicate recovery signals coalesce")
        clock.next()
        expect(!recovery.healthy, "failure does not report active")
        expectEqual(clock.jobs.first?.0, 4, "first retry backs off four seconds")
        clock.next()
        expectEqual(clock.jobs.first?.0, 8, "second retry backs off eight seconds")
        fail = false; clock.next()
        expect(recovery.healthy, "successful reapply becomes healthy")
        expectEqual(reconnects, 0, "successful recovery keeps the transport")
        expectEqual(applies, 3, "only scheduled attempts execute")
        recovery.request(reason: "wake")
        recovery.stop(); clock.next()
        expectEqual(applies, 3, "stopped generation ignores delayed callbacks")
    }
    do {
        let clock = TestClock()
        var reconnects = 0
        let recovery = RemapRecovery(schedule: clock.schedule, apply: { throw HIDPPError.timeout },
                                     state: { _, _ in }, reconnect: { reconnects += 1 })
        recovery.request(reason: "dead transport")
        clock.next(); clock.next(); clock.next()
        expectEqual(reconnects, 1, "three failures request a fresh transport once")
        recovery.request(reason: "old callback")
        expectEqual(clock.jobs.count, 0, "retired recovery never schedules again")
    }
    do {
        let queue = HIDWorkQueue()
        var order: [Int] = []
        queue.submit { order.append(1); queue.submit { order.append(3) }; order.append(2) }
        expectEqual(order, [1, 2, 3], "nested run loop work cannot overlap a HID transaction")
        var gate = RemapActivityGate(startedAt: 0)
        expect(gate.activity(at: 300).rearm, "first input after long idle rearms without 0x41")
        for t in 301...359 { expect(!gate.activity(at: Double(t)).check, "input flood does not poll HID") }
        expect(gate.activity(at: 360).check, "active read check is capped at once per minute")
        expect(gate.activity(at: 900).rearm, "later idle/resume rearms again")
    }
    do {
        let clock = TestClock()
        var applies = 0
        let recovery = RemapRecovery(schedule: clock.schedule, apply: { applies += 1 },
                                     state: { _, _ in }, reconnect: {})
        recovery.request(reason: "queued before sleep")
        recovery.suspend(); clock.next()
        recovery.request(reason: "late 0x41 while sleeping")
        expectEqual(applies, 0, "sleep cancels pending I/O and ignores late signals")
        recovery.resume(); recovery.request(reason: "wake"); clock.next()
        expectEqual(applies, 1, "wake permits a fresh recovery")
    }
    section("G and MX session recovery")
    for mx in [false, true] {
        do {
            let tr = StatefulMouse(); tr.mx = mx
            let dev = HIDPPDevice(transport: tr, index: 1)
            let action = ButtonAction(type: "disable")
            let engine: RemapEngineProtocol = mx
                ? MXRemapEngine(transport: tr, dev: dev, mappings: [0x53: action])!
                : RemapEngine(transport: tr, dev: dev, mappings: [6: action])!
            var fired = 0
            if let e = engine as? RemapEngine { e.executeAction = { _ in fired += 1 } }
            if let e = engine as? MXRemapEngine { e.executeAction = { _ in fired += 1 } }
            try engine.start()
            let press: [UInt8] = mx ? [1, 7, 0, 0, 0x53] : [1, 6, 0, 0, 0x40]
            tr.onReport?(press); tr.onReport?(press)
            expectEqual(fired, 1, "duplicate held events only execute once")
            let writes = tr.writes
            try engine.checkHealth(rearm: false)
            expectEqual(tr.writes, writes, "healthy checks do not rewrite mouse state")
            // Mouse resets its runtime state without sending a connection notification.
            tr.table = Array(UInt8(1)...UInt8(16)); tr.diverted = []
            tr.table[8] = 12 // a profile's unowned slot must not be overwritten
            tr.featureIndex = mx ? 10 : 9
            try engine.checkHealth(rearm: false)
            expect(!engine.active, "lost device state invalidates active")
            pumpRecovery()
            expect(engine.active, "no-0x41 state loss recovers automatically")
            expect(tr.seenFeatures.contains(mx ? 10 : 9), "recovery resolves moved feature indexes afresh")
            if !mx { expectEqual(tr.table[8], 12, "recovery preserves unowned profile slots") }
            expect(mx ? tr.diverted.contains(0x53) : tr.table[6] == 0 && tr.spy,
                   "recovery restores the actual mouse state")
            expectEqual(Array(tr.table.prefix(2)), [1, 2], "primary buttons remain untouched")
            var sessionChanges = 0
            engine.onReconnect = { restore in
                expect(!restore, "new receiver session never restores the old mouse table")
                sessionChanges += 1
            }
            let beforeSessionChange = tr.writes
            let oldCallback = tr.onReport
            tr.onReport?([1, 0x41, 0, 0, 0])
            expectEqual(sessionChanges, 1, "0x41 requests fresh device discovery")
            expectEqual(tr.writes, beforeSessionChange, "session invalidation performs no stale device writes")
            engine.stop()
            let stoppedWrites = tr.writes
            oldCallback?([1, 0x41, 0, 0, 0]); pumpRecovery()
            expectEqual(tr.writes, stoppedWrites, "stop invalidates queued and captured old callbacks")
            expect(tr.onReport == nil, "stop detaches report subscription")
            let newTr = StatefulMouse(); newTr.mx = mx
            let newDev = HIDPPDevice(transport: newTr, index: 1)
            let replacement: RemapEngineProtocol = mx
                ? MXRemapEngine(transport: newTr, dev: newDev, mappings: [0x53: action])!
                : RemapEngine(transport: newTr, dev: newDev, mappings: [6: action])!
            try replacement.start()
            expect(replacement.active, "replacement transport starts a new session at the same index")
            replacement.stop()
        } catch { expect(false, "session recovery unexpectedly threw: \(error)") }
    }
    do {
        let tr = StatefulMouse(); tr.failStart = true
        let dev = HIDPPDevice(transport: tr, index: 1)
        let e = RemapEngine(transport: tr, dev: dev, mappings: [6: ButtonAction(type: "disable")])!
        do { try e.start(); expect(false, "failed spy start must propagate") } catch {}
        expect(!e.active && tr.onReport == nil, "partial start never reports active or retains subscription")
        expectEqual(tr.table[6], 7, "partial start restores original table")
    }
}
