import Foundation
import ServiceManagement
import Security
import CryptoKit

enum Distribution {
    static let bundleID = "com.xppxpp.nibblecn"
    static let replayLabel = bundleID + ".replay"
    static let legacyReplayLabel = "com.ben0128.nibble.replay"
}

struct CommandResult {
    var status: Int32
    var output: String
}

/// Capture errors rather than hiding launchctl stderr. A temporary regular file
/// avoids a pipe filling while waitUntilExit waits for the child.
func runCommand(_ args: [String]) -> CommandResult {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    guard FileManager.default.createFile(atPath: url.path, contents: nil),
          let out = try? FileHandle(forWritingTo: url) else {
        return CommandResult(status: -1, output: "cannot create command output file")
    }
    defer { try? out.close(); try? FileManager.default.removeItem(at: url) }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: args[0]); process.arguments = Array(args.dropFirst())
    process.standardOutput = out; process.standardError = out
    do { try process.run(); process.waitUntilExit() }
    catch { return CommandResult(status: -1, output: "\(error)") }
    return CommandResult(status: process.terminationStatus,
                         output: (try? String(contentsOf: url, encoding: .utf8)) ?? "")
}

struct ReplayFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// All side effects are injectable. Tests only use a temp directory and fake launchctl.
struct ReplayEnvironment {
    var directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
    var logs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NibbleCN")
    var domain = "gui/\(getuid())"
    var run: ([String]) -> CommandResult = runCommand
    var write: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    var isChineseExecutable: (String) -> Bool = chineseExecutable
    var plist: URL { directory.appendingPathComponent(Distribution.replayLabel + ".plist") }
    var legacyPlist: URL { directory.appendingPathComponent(Distribution.legacyReplayLabel + ".plist") }
    var result: URL { logs.appendingPathComponent("last-replay.json") }
}

func chineseExecutable(_ executable: String) -> Bool {
    let url = URL(fileURLWithPath: executable).resolvingSymlinksInPath()
    let app = url.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    guard app.pathExtension == "app", let bundle = Bundle(url: app),
          bundle.bundleIdentifier == Distribution.bundleID,
          bundle.executableURL?.resolvingSymlinksInPath() == url else { return false }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
          SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess else { return false }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let dict = info as? [String: Any] else { return false }
    return dict[kSecCodeInfoIdentifier as String] as? String == Distribution.bundleID
}

func replayDictionary(_ data: Data?) -> [String: Any]? {
    guard let data else { return nil }
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
}

struct ReplayManager {
    var env = ReplayEnvironment()
    private func launch(_ args: [String]) -> CommandResult { env.run(["/bin/launchctl"] + args) }
    func loaded(label: String = Distribution.replayLabel) -> Bool {
        launch(["print", "\(env.domain)/\(label)"]).status == 0
    }
    func fingerprint(_ executable: String) throws -> String {
        SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: executable))).map {
            String(format: "%02x", $0)
        }.joined()
    }

    /// Called by the bundled menu bar after a ZIP replacement, only for our own
    /// previously installed agent at this same executable path. Never opts users in.
    func reconcile(executable: String) throws {
        let old = try? Data(contentsOf: env.plist)
        guard ownsCurrent(old), let p = replayDictionary(old),
              let args = p["ProgramArguments"] as? [String], args.first == executable else { return }
        if p["NibbleExecutableSHA256"] as? String != (try fingerprint(executable)) {
            _ = try install(executable: executable)
        }
    }

    func data(executable: String) throws -> Data {
        guard executable.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: executable) else {
            throw ReplayFailure("Replay 可执行文件不存在或不可执行：\(executable)")
        }
        let payload: [String: Any] = [
            "Label": Distribution.replayLabel,
            "ProgramArguments": [executable, "replay", "run"],
            "RunAtLoad": true,
            "AssociatedBundleIdentifiers": [Distribution.bundleID],
            "StandardOutPath": env.logs.appendingPathComponent("replay.log").path,
            "StandardErrorPath": env.logs.appendingPathComponent("replay-error.log").path,
            "NibbleDistribution": Distribution.bundleID,
            "NibbleExecutableSHA256": try fingerprint(executable),
        ]
        return try PropertyListSerialization.data(fromPropertyList: payload, format: .xml, options: 0)
    }
    func legacyOwned(_ old: Data?) -> Bool {
        guard let p = replayDictionary(old), p["Label"] as? String == Distribution.legacyReplayLabel,
              let args = p["ProgramArguments"] as? [String], args.count == 2, args[1] == "apply" else { return false }
        // A label, file name, directory name or a claimed marker is insufficient.
        // Unverifiable historical/CLI binaries are preserved, including upstream builds.
        return env.isChineseExecutable(args[0])
    }
    func ownsCurrent(_ old: Data?) -> Bool {
        guard let p = replayDictionary(old), p["Label"] as? String == Distribution.replayLabel,
              p["NibbleDistribution"] as? String == Distribution.bundleID,
              let args = p["ProgramArguments"] as? [String], args.count == 3,
              Array(args.dropFirst()) == ["replay", "run"] else { return false }
        return true
    }

    /// Prepare + atomic publish BEFORE taking down an existing loaded job. If any
    /// later step fails, restore both the previous plist and its loaded state.
    private func withLock<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        let lock = env.directory.appendingPathComponent("." + Distribution.replayLabel + ".lock")
        let fd = open(lock.path, O_CREAT | O_WRONLY, 0o600)
        guard fd >= 0 else { throw ReplayFailure("无法打开 Replay 操作锁：\(errno)") }
        defer { close(fd) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { throw ReplayFailure("另一个 Replay 操作正在执行，请稍后重试") }
        defer { flock(fd, LOCK_UN) }
        return try work()
    }

    func install(executable: String) throws -> [String] {
        try withLock { try installLocked(executable: executable) }
    }

    private func installLocked(executable: String) throws -> [String] {
        let next = try data(executable: executable)
        try FileManager.default.createDirectory(at: env.directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: env.logs, withIntermediateDirectories: true)
        let old = try? Data(contentsOf: env.plist)
        if FileManager.default.fileExists(atPath: env.plist.path), !ownsCurrent(old) {
            throw ReplayFailure("目标 plist 归属不明，已保留：\(env.plist.path)")
        }
        let wasLoaded = loaded()
        if wasLoaded && old == nil { throw ReplayFailure("job 已加载但缺少可回退的 plist；未作更改") }
        // Writing can fail due to sandbox, disk space or permissions. No bootout yet.
        try env.write(next, env.plist)
        if wasLoaded {
            let result = launch(["bootout", "\(env.domain)/\(Distribution.replayLabel)"])
            if result.status != 0 {
                if let old { try env.write(old, env.plist) }
                throw ReplayFailure("停止旧 Replay 失败，已保留旧配置：\(result.output)")
            }
        }
        let result = launch(["bootstrap", env.domain, env.plist.path])
        if result.status != 0 {
            var rollback = ""
            do {
                if let old { try env.write(old, env.plist) }
                else { try FileManager.default.removeItem(at: env.plist) }
                if wasLoaded {
                    let restored = launch(["bootstrap", env.domain, env.plist.path])
                    if restored.status != 0 { rollback = "；旧 job 恢复失败：\(restored.output)" }
                }
            } catch { rollback = "；回退失败：\(error)" }
            throw ReplayFailure("注册 Replay 失败（\(result.status)）：\(result.output)\(rollback)")
        }
        var warnings: [String] = []
        if let legacy = try? Data(contentsOf: env.legacyPlist) {
            if legacyOwned(legacy) {
                if loaded(label: Distribution.legacyReplayLabel) {
                    let removal = launch(["bootout", "\(env.domain)/\(Distribution.legacyReplayLabel)"])
                    guard removal.status == 0 else {
                        throw ReplayFailure("新 Replay 已安装，但旧中文版 job 停止失败，旧文件保留：\(removal.output)")
                    }
                }
                try FileManager.default.removeItem(at: env.legacyPlist)
            } else {
                warnings.append("旧 Replay 归属无法确认，已保留（可能属于英文版）：\(env.legacyPlist.path)")
            }
        }
        return warnings
    }

    func uninstall() throws { try withLock { try uninstallLocked() } }

    private func uninstallLocked() throws {
        let old = try? Data(contentsOf: env.plist)
        guard old != nil else {
            if loaded() { throw ReplayFailure("Replay 已加载但 plist 缺失，归属无法验证；未删除 job") }
            return
        }
        guard ownsCurrent(old) else { throw ReplayFailure("Replay plist 归属不明，未删除") }
        if loaded() {
            let result = launch(["bootout", "\(env.domain)/\(Distribution.replayLabel)"])
            guard result.status == 0 else { throw ReplayFailure("停止 Replay 失败：\(result.output)") }
        }
        try FileManager.default.removeItem(at: env.plist)
    }

    func diagnostics() -> [String: Any] {
        let exists = FileManager.default.fileExists(atPath: env.plist.path)
        let status = SMAppService.statusForLegacyPlist(at: env.plist)
        let authorization: String
        switch status {
        case .enabled: authorization = "enabled"
        case .requiresApproval: authorization = "requiresApproval"
        case .notRegistered: authorization = "notRegistered"
        case .notFound: authorization = "notFound"
        @unknown default: authorization = "unknown"
        }
        let job = launch(["print", "\(env.domain)/\(Distribution.replayLabel)"])
        let last = (try? Data(contentsOf: env.result)).flatMap {
            (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any]
        }
        return ["plistExists": exists, "authorization": authorization,
                "loaded": job.status == 0, "launchctl": job.output,
                "lastRun": last.map { $0 as Any } ?? NSNull(), "plist": env.plist.path]
    }
}

/// Explicit service teardown for uninstall. It must run from the installed Chinese
/// bundle so SMAppService.mainApp unregisters that exact app, not a naked CLI.
func cmdUninstallServices() -> Int32 {
    guard runningFromAppBundle(), Bundle.main.bundleIdentifier == Distribution.bundleID else {
        emitError("请从待卸载的中文版 app 执行：/Applications/Nibble.app/Contents/MacOS/nibble uninstall-services", code: "not-bundled")
        return 2
    }
    guard !menuBarRunning() else {
        emitError("请先退出菜单栏程序，再解除后台服务", code: "menubar-running"); return 2
    }
    do {
        // Stop on errors. The app must not be deleted with registration left behind.
        try ReplayManager().uninstall()
        if LoginItem.status != .notRegistered && LoginItem.status != .notFound {
            try LoginItem.set(false)
        }
        print("✅ 已解除中文版 Replay 与登录启动；用户配置保留")
        return 0
    } catch { emitError("\(error)", code: "uninstall-failed"); return 2 }
}
