import Foundation

final class FakeLaunchd {
    var jobs: Set<String> = []
    var commands: [[String]] = []
    var failBootstrap = 0
    var failBootout = false
    func run(_ command: [String]) -> CommandResult {
        commands.append(command)
        let operation = command[1]
        let label = command[2].components(separatedBy: "/").last!
        if operation == "print" { return CommandResult(status: jobs.contains(label) ? 0 : 113, output: "fake job") }
        if operation == "bootout" {
            if failBootout { return CommandResult(status: 5, output: "fake bootout denied") }
            jobs.remove(label); return CommandResult(status: 0, output: "")
        }
        if operation == "bootstrap" {
            if failBootstrap > 0 { failBootstrap -= 1; return CommandResult(status: 5, output: "fake bootstrap denied") }
            let data = try? Data(contentsOf: URL(fileURLWithPath: command[3]))
            if let label = replayDictionary(data)?["Label"] as? String { jobs.insert(label) }
            return CommandResult(status: 0, output: "")
        }
        return CommandResult(status: 64, output: "unexpected command")
    }
}

func runReplayTests() {
    section("Replay transaction and ownership")
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("nibble-replay-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    func setup(_ name: String) -> (ReplayManager, FakeLaunchd) {
        let fake = FakeLaunchd()
        var env = ReplayEnvironment()
        env.directory = root.appendingPathComponent(name + "/agents")
        env.logs = root.appendingPathComponent(name + "/logs")
        env.domain = "gui/fake"
        env.run = fake.run
        env.isChineseExecutable = { $0 == "/trusted/中文/Nibble.app/Contents/MacOS/nibble" }
        try! FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        return (ReplayManager(env: env), fake)
    }
    func legacy(_ exe: String) -> Data {
        try! PropertyListSerialization.data(fromPropertyList: ["Label": Distribution.legacyReplayLabel,
            "ProgramArguments": [exe, "apply"], "RunAtLoad": true], format: .xml, options: 0)
    }
    do {
        var (manager, fake) = setup("write-failure")
        let old = try manager.data(executable: "/bin/echo")
        try old.write(to: manager.env.plist)
        fake.jobs.insert(Distribution.replayLabel)
        manager.env.write = { _, _ in throw ReplayFailure("fake disk full") }
        do { _ = try manager.install(executable: "/bin/echo"); expect(false, "write must fail") } catch {}
        expect(!fake.commands.contains { $0[1] == "bootout" }, "write failure never stops existing service")
        expect(fake.jobs.contains(Distribution.replayLabel), "existing job survives write failure")
        expectEqual(try Data(contentsOf: manager.env.plist), old, "old plist remains intact")
    } catch { expect(false, "write-failure fixture: \(error)") }
    do {
        let (manager, fake) = setup("registration-failure")
        let old = try manager.data(executable: "/bin/echo")
        try old.write(to: manager.env.plist); fake.jobs.insert(Distribution.replayLabel)
        fake.failBootstrap = 1
        do { _ = try manager.install(executable: "/bin/cat"); expect(false, "registration failure propagates") }
        catch { expect("\(error)".contains("fake bootstrap denied"), "launchctl stderr is retained") }
        expectEqual(try Data(contentsOf: manager.env.plist), old, "registration failure restores previous plist")
        expect(fake.jobs.contains(Distribution.replayLabel), "registration failure reloads previous job")
    } catch { expect(false, "registration-failure fixture: \(error)") }
    do {
        let (manager, fake) = setup("new-registration-failure")
        fake.failBootstrap = 1
        do { _ = try manager.install(executable: "/bin/echo"); expect(false, "new registration failure propagates") } catch {}
        expect(!FileManager.default.fileExists(atPath: manager.env.plist.path), "failed first install removes unregistered plist")
    }
    do {
        let (manager, fake) = setup("bootout-failure")
        let old = try manager.data(executable: "/bin/echo")
        try old.write(to: manager.env.plist); fake.jobs.insert(Distribution.replayLabel); fake.failBootout = true
        do { _ = try manager.install(executable: "/bin/cat"); expect(false, "bootout failure propagates") } catch {}
        expectEqual(try Data(contentsOf: manager.env.plist), old, "failed bootout restores old file")
        expect(fake.jobs.contains(Distribution.replayLabel), "failed bootout leaves loaded job intact")
    } catch { expect(false, "bootout-failure fixture: \(error)") }
    do {
        let (manager, fake) = setup("upstream-coexistence")
        let upstream = legacy("/Applications/Nibble-en.app/Contents/MacOS/nibble")
        try upstream.write(to: manager.env.legacyPlist); fake.jobs.insert(Distribution.legacyReplayLabel)
        let warnings = try manager.install(executable: "/bin/echo")
        expectEqual(warnings.count, 1, "ambiguous legacy ownership warns")
        expectEqual(try Data(contentsOf: manager.env.legacyPlist), upstream, "upstream plist preserved")
        expect(fake.jobs.contains(Distribution.legacyReplayLabel), "upstream loaded job preserved")
        try manager.uninstall()
        expect(fake.jobs.contains(Distribution.legacyReplayLabel), "Chinese uninstall never removes upstream job")
    } catch { expect(false, "coexistence fixture: \(error)") }
    do {
        let (manager, fake) = setup("Chinese-migration")
        try legacy("/trusted/中文/Nibble.app/Contents/MacOS/nibble").write(to: manager.env.legacyPlist)
        fake.jobs.insert(Distribution.legacyReplayLabel)
        expect(try manager.install(executable: "/bin/echo").isEmpty, "verified Chinese agent migrates")
        expect(!fake.jobs.contains(Distribution.legacyReplayLabel), "verified old job stops after new registration")
        expect(!FileManager.default.fileExists(atPath: manager.env.legacyPlist.path), "verified legacy plist removed")
        let index = fake.commands.firstIndex { $0[1] == "bootstrap" }!
        let removal = fake.commands.firstIndex { $0[1] == "bootout" }!
        expect(index < removal, "new agent is registered before legacy removal")
    } catch { expect(false, "migration fixture: \(error)") }
    do {
        let (manager, fake) = setup("ZIP-upgrade")
        let p = try manager.data(executable: "/bin/echo")
        var old = replayDictionary(p)!
        old["NibbleExecutableSHA256"] = "old-version"
        try PropertyListSerialization.data(fromPropertyList: old, format: .xml, options: 0).write(to: manager.env.plist)
        fake.jobs.insert(Distribution.replayLabel)
        try manager.reconcile(executable: "/bin/echo")
        expectEqual(replayDictionary(try Data(contentsOf: manager.env.plist))?["NibbleExecutableSHA256"] as? String,
                    try manager.fingerprint("/bin/echo"), "ZIP replacement reconciles same installed path")
        fake.commands = []
        try manager.reconcile(executable: "/bin/echo")
        expect(fake.commands.isEmpty, "unchanged executable never re-registers")
        try manager.reconcile(executable: "/bin/cat")
        expect(fake.commands.isEmpty, "another executable path never takes over registration")
    } catch { expect(false, "upgrade fixture: \(error)") }
    do {
        var (manager, fake) = setup("concurrent")
        let other = manager
        var rejected = false
        manager.env.write = { data, url in
            do { _ = try other.install(executable: "/bin/echo") }
            catch { rejected = true }
            try data.write(to: url, options: .atomic)
        }
        _ = try manager.install(executable: "/bin/echo")
        expect(rejected, "concurrent install is rejected before touching launchd")
        expectEqual(fake.commands.filter { $0[1] == "bootstrap" }.count, 1, "only one transaction registers")
    } catch { expect(false, "concurrent fixture: \(error)") }
    let (manager, _) = setup("XML")
    expect(!manager.legacyOwned(legacy("/unverifiable/CLI/nibble")), "legacy CLI without verifiable identity is preserved")
    expectEqual(Distribution.replayLabel, "com.xppxpp.nibblecn.replay", "CLI uses fixed Chinese identity without Bundle.main")
}
