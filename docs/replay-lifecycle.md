# 中文版 Replay 生命周期

## 身份与共存

固定发行 ID 为 `com.xppxpp.nibblecn`，Replay label/plist 为 `com.xppxpp.nibblecn.replay`。CLI 不依赖 Bundle.main 是否有 ID。内部 DispatchQueue label、配置路径、MIT 与上游署名保留。

`SMAppService.mainApp` 负责菜单栏登录启动；Replay 是登录时执行一次配置恢复，两者继续独立。Replay 执行 `replay run`，调用原有 apply 后原子记录开始/结束时间、版本、执行路径与退出码到 `~/Library/Logs/NibbleCN/last-replay.json`。日志也放在该目录，避免共享 /tmp 路径。

旧 label `com.ben0128.nibble.replay` 只在显式 replay install 完成新版注册后检查。仅在 plist label/参数结构符合旧版、目标实际位于中文版 bundle、Info.plist 与可验证签名身份均为中文版且执行文件确为该 bundle 主程序时才迁移。历史裸 CLI、失效路径、英文版或无法验证的程序都保留并提示。此判断验证的是当前执行目标，无法重建一个后来被替换的历史文件的来源；不能把文件名或 label 当作历史版本证据。

## 安装事务

1. 获取中文版专用非阻塞 flock，防止多个 CLI/设置窗口并发更改。
2. 验证目标路径并用 PropertyListSerialization 生成 plist，路径中的 XML 字符得到转义。
3. 保存旧文件/加载状态；归属不明或缺少可回滚文件则拒绝接管。
4. **先原子写入成功**，之后才 bootout 旧 job。写入失败不触碰服务。
5. bootstrap 失败返回非零并保留 stderr，恢复原文件；旧 job 原来已加载时尝试重新 bootstrap。回退自身失败也明确报告。
6. 新 job 成功注册后才迁移可确认的旧中文版代理。旧代理停止失败时保留文件并报错，不能谎报完全迁移成功。

这不是跨 launchd/磁盘的原子事务：在进程被强制终止或断电时仍存在注册窗口；下次启动可自检，必要时显式 replay install。离线测试覆盖可控写入和注册错误，不声称覆盖系统崩溃。

## ZIP 替换与签名

菜单栏启动时只对具有本发行 marker、且 ProgramArguments 的路径与自身完全一致的已安装新 Replay 做检查。二进制 SHA256 改变时更新注册；没有已安装新 Replay 不会擅自开启功能，也不会接管其他路径。无需运行 make install-app。失败记录到 engine.json 的 replayUpdateError 和 stderr，doctor 显示该错误。权限被系统禁止时仍需用户在系统设置允许。

本地验证：ad-hoc bundle 的签名 Identifier 正确为 `com.xppxpp.nibblecn`，TeamIdentifier 为空，designated requirement 包含 cdhash。代码或签名输入变化可以改变 cdhash。**不能由此推导每次更新必然造成 launchd 拒绝。** 原 plist 没有显式 SpawnConstraint；历史 BTM 状态/系统生成约束与授权必须在真实系统上观察。重注册只能处理应用自己的 job，不能绕过 TCC/BTM，也不保证修复被用户禁止的后台项目。

Apple 的 AssociatedBundleIdentifiers 用于关联后台项目与 app，并要求目标与 app 的 TeamIdentifier 匹配。ad-hoc/CLI 未具备 Developer ID 的稳定身份，显示名称和授权连续性不能保证。稳定发布的长期方案仍是 Developer ID 签名与公证；本次不伪造证书、不放宽安全约束。

- [Apple：更新旧版 helper](https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos)
- [Apple：启动约束与 cdhash](https://developer.apple.com/documentation/security/defining-launch-environment-and-library-constraints)

## 诊断与卸载

`replay status --json` 分别返回 plistExists、authorization、loaded、launchctl、lastRun。`doctor` 分开展示这些证据。一次性 job loaded 不表示进程正在执行，statusForLegacyPlist 不代表运行状态。lastRun 只证明所标注时间/版本的一次执行，不证明当前 DPI、权限或引擎正常。

先退出菜单栏，再使用已安装中文 app 的 `uninstall-services`，它先解除自己的 Replay，再解除本 bundle 的 SMAppService。失败返回非零，make uninstall 因此停止，避免删除仍有注册的程序。不会猜测或删除旧英文代理，不清理权限数据库，不删除用户配置与备份。

## 尚未进行

没有修改用户 launchd/BTM、没有安装替换 /Applications/Nibble.app、没有执行真实 replay install/uninstall。ZIP 原路径更新后的 BTM/TCC 行为、SMAppService 注销效果及 G502 登录恢复需要用户批准后验收。
