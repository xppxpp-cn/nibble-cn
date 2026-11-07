// L10n.swift — machine-readable output helpers.
// 用户可见诊断使用简体中文，命令、配置键和 JSON 字段保持兼容。
import Foundation

/// `--json`: read commands emit machine-readable output for scripts and agents.
var jsonMode = false

func emitJSON(_ obj: [String: Any]) {
    let data = try? JSONSerialization.data(withJSONObject: obj,
                                           options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(data: data ?? Data("{}".utf8), encoding: .utf8) ?? "{}")
}

/// Errors are machine-readable too: {"error":…,"code":…} in JSON mode, plain text otherwise.
func emitError(_ message: String, code: String) {
    if jsonMode { emitJSON(["error": message, "code": code]) } else { print("❌ \(message)") }
}
