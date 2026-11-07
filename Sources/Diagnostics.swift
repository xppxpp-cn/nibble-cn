import Foundation

func engineReasonLabel(_ reason: String) -> String {
    let labels = [
        "running": "运行中（最近一次应用成功；不代表已验证目标应用收到快捷键）",
        "no mappings configured": "尚未配置按键映射",
        "Accessibility permission not granted": "未授权辅助功能权限",
        "device exposes neither 0x8110 nor 0x1b04": "设备不支持按键映射",
        "device disconnected — waiting for reconnect": "设备已断开，等待重新连接",
        "paused by user": "用户已暂停映射",
        "system sleeping": "系统休眠中",
        "wireless reconnect": "无线设备重新连接，正在恢复",
        "wireless device asleep or disconnected": "无线设备休眠或断开",
        "system wake": "系统已唤醒，正在恢复",
        "input resumed": "检测到输入恢复，正在恢复映射",
        "input resumed after idle": "闲置后输入恢复，正在重新订阅按键事件",
        "spy remapping state lost": "检测到 G 系映射表丢失，正在恢复",
        "divert state lost": "检测到 MX 系 divert 状态丢失，正在恢复",
    ]
    if let label = labels[reason] { return label }
    if reason.hasPrefix("no mappings for ") { return "当前设备没有配置按键映射" }
    for (prefix, label) in [("recovery failed: ", "恢复失败："), ("retry after: ", "等待退避重试："),
                            ("health check failed: ", "健康检查失败：")] {
        if reason.hasPrefix(prefix) { return label + reason.dropFirst(prefix.count) }
    }
    return reason
}

func authorizationLabel(_ raw: String) -> String {
    ["enabled": "已获授权", "requiresApproval": "需要系统设置允许", "notRegistered": "尚未注册",
     "notFound": "系统未找到该项目", "unknown": "未知"][raw] ?? raw
}

func cmdDistribution() -> Int32 {
    emitJSON(["bundleID": Distribution.bundleID, "replayLabel": Distribution.replayLabel,
              "legacyReplayLabel": Distribution.legacyReplayLabel,
              "bundled": runningFromAppBundle(), "version": NIBBLE_VERSION])
    return 0
}
