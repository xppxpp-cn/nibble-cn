// main.swift — 入口與 argv 解析（零依賴，手寫解析）
import Foundation


var rawArgs = Array(CommandLine.arguments.dropFirst())
if let i = rawArgs.firstIndex(of: "--json") {
    jsonMode = true
    rawArgs.remove(at: i)
}

// 從 .app bundle 雙擊啟動時沒有引數（Finder 只會塞 -psn_*，新版常常什麼都不塞）→ 直接進選單列模式。
// 這裡一定要用 runningFromAppBundle()：只看 bundleIdentifier 的話，在 repo 根目錄
// 跑 `./nibble`（無引數）會被當成雙擊，於是把常駐選單列開起來、還搶走 HID 裝置——
// 而使用者要的只是印出說明。
let fromFinder = runningFromAppBundle() && rawArgs.allSatisfy { $0.hasPrefix("-psn_") }
let command = fromFinder ? "menubar" : (rawArgs.first ?? "help")
let subArgs = fromFinder ? [] : Array(rawArgs.dropFirst())

switch command {
case "distribution": exit(cmdDistribution())
case "status":   exit(cmdStatus())
case "battery":  exit(cmdBattery())
case "dump":     exit(cmdDump())
case "doctor":   exit(cmdDoctor())
case "dpi":      exit(cmdDPI(subArgs))
case "rate":     exit(cmdRate(subArgs))
case "rgb":      exit(cmdRGB(subArgs))
case "mode":     exit(cmdMode(subArgs))
case "wheel":    exit(cmdWheel(subArgs))
case "onboard":  exit(cmdOnboard(subArgs))
case "buttons":  exit(cmdButtons())
case "spy":      exit(cmdSpy(subArgs))
case "remap":    exit(cmdRemap())
case "profile":  exit(cmdProfile(subArgs))
case "config":   exit(cmdConfig(subArgs))
case "apply":    exit(cmdApply())
case "replay":   exit(cmdReplay(subArgs))
case "uninstall-services": exit(cmdUninstallServices())
case "startup":  exit(cmdStartup(subArgs))
case "menubar":  exit(runMenuBar())
case "ui":       exit(runSettingsUI(initialTab: subArgs.first))
case "version", "--version", "-v":
    if jsonMode { emitJSON(["version": NIBBLE_VERSION]) } else { print("nibble \(NIBBLE_VERSION)") }
    exit(0)
default:
    print("""
    Nibble 中文版 v\(NIBBLE_VERSION) — 轻量 Logitech 鼠标控制工具

    查看与诊断
      nibble status [--json]        设备、DPI、报告率和电量
      nibble battery [--json]       电量
      nibble dump [--json]          HID++ 功能列表
      nibble buttons [--json]       可编程按键（G: 0x8110 / MX: 0x1b04）
      nibble doctor [--json]        权限、设备、引擎与 Replay 诊断
      nibble distribution           中文版发行标识（JSON；不访问设备）

    配置（仅运行时写入，设备断电会恢复板载状态）
      nibble dpi [50-25600]         查询或修改 DPI
      nibble rate [125|250|500|1000] 查询或修改报告率
      nibble rgb off|show           关闭灯光或查看支持的效果
      nibble mode [host|onboard]    查询或切换运行模式
      nibble wheel free|ratchet     SmartShift（MX 系）
      nibble remap                  交互设置按键动作
      nibble profile [use <name>]   管理与切换配置方案
      nibble spy [seconds]          实时按键事件诊断
      nibble config init|show       创建或查看 ~/.config/nibble.json
      nibble apply                  应用保存的设置

    启动与卸载
      nibble replay install|uninstall|status [--json]
                                    一次性登录恢复 DPI、报告率与灯光
      nibble startup [on|off]       登录启动菜单栏（需从 app bundle 执行）
      nibble uninstall-services     先退出菜单栏，再从中文 app 解除自己的后台服务

    窗口与其他
      nibble menubar               菜单栏常驻与按键映射引擎
      nibble ui [buttons]           独立设置窗口
      nibble onboard info|backup   查看或只读备份板载内存，不写 Flash
      nibble version               版本

    NIBBLE_DEBUG=1 输出 HID++ 原始报文；包含按键事件，请按需开启。
    首次运行需允许输入监控；快捷键与宏还需要辅助功能权限。
    退出码：0 成功 · 1 无设备或未应用 · 2 传输/服务错误 · 64 参数错误。
    """)
    exit(command == "help" ? 0 : 64)
}
