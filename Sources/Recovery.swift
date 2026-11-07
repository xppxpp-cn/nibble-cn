import Foundation

/// Main-run-loop operations can reenter while HID++ waits pump that same run loop.
/// Queue whole transactions, not individual packets, so stop/start and recovery never overlap.
final class HIDWorkQueue {
    static let shared = HIDWorkQueue()
    private var running = false
    private var pending: [() -> Void] = []
    func submit(_ work: @escaping () -> Void) {
        pending.append(work)
        guard !running else { return }
        running = true
        while !pending.isEmpty { pending.removeFirst()() }
        running = false
    }
}

/// No timer while healthy. Signals coalesce; failures back off and eventually ask the
/// owner for a fresh transport. Injected scheduling makes all races testable offline.
final class RemapRecovery {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> Void
    private let schedule: Schedule
    private let apply: () throws -> Void
    private let state: (Bool, String) -> Void
    private let reconnect: () -> Void
    private var generation = 0
    private var stopped = false
    private var suspended = false
    private var pending = false
    private var failures = 0
    private(set) var healthy = true

    init(schedule: @escaping Schedule = { delay, work in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            HIDWorkQueue.shared.submit(work)
        }
    }, apply: @escaping () throws -> Void,
       state: @escaping (Bool, String) -> Void, reconnect: @escaping () -> Void) {
        self.schedule = schedule; self.apply = apply; self.state = state; self.reconnect = reconnect
    }

    func request(reason: String, delay: TimeInterval = 0.5) {
        guard !stopped, !suspended, !pending else { return }
        healthy = false; pending = true
        state(false, reason)
        let ticket = generation
        schedule(delay) { [weak self] in
            guard let self, !self.stopped, self.generation == ticket else { return }
            // Keep pending set during apply: roundTrip pumps the run loop.
            do {
                try self.apply()
                guard !self.stopped, self.generation == ticket else { return }
                self.pending = false; self.failures = 0; self.healthy = true
                self.state(true, "running")
            } catch {
                guard !self.stopped, self.generation == ticket else { return }
                self.pending = false; self.failures += 1
                self.state(false, "recovery failed: \(error)")
                if self.failures >= 3 { self.stop(); self.reconnect() }
                else { self.request(reason: "retry after: \(error)", delay: pow(2, Double(self.failures + 1))) }
            }
        }
    }

    func suspend() { suspended = true; generation += 1; pending = false; healthy = false }
    func resume() { suspended = false }

    func stop() { stopped = true; generation += 1; pending = false; healthy = false }
}

/// Input only signals possible activity, never proves which physical mouse is awake
/// (Deskflow may synthesize input). At most one read check per minute of activity;
/// a >=60s gap also rearms spy once because 0x8110 has no subscription readback.
struct RemapActivityGate {
    private var lastInput: TimeInterval?
    init(startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) { lastInput = startedAt }
    private var lastCheck: TimeInterval = -.infinity
    mutating func activity(at now: TimeInterval) -> (check: Bool, rearm: Bool) {
        let idle = lastInput.map { now - $0 >= 60 } ?? false
        lastInput = now
        guard now - lastCheck >= 60 else { return (false, false) }
        lastCheck = now
        return (true, idle)
    }
}
