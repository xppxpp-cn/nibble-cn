# 本轮离线验证报告（2026-11-07）

## 工作区与安全边界

- 源目录 `~/Developer/DisplayDial-cn/.tmp-nibble-cn`：完整、干净的 Git 仓库，基线为 `8d7b1dc`，origin 为中文 Fork；本轮未在其中编辑或构建。
- 独立目录 `~/Developer/nibble-cn`：原来只有 `.fidelity-test`、`.gate-test`、`.probe-write-test` 三个文件。它们保持原样且未纳入 Git。已复制完整仓库，在 `fix/nibble-idle-recovery-and-lifecycle` 开发。
- 已 fetch，远端 main 仍为基线。未覆盖安装 app、未删除用户配置、未修改真实 launchd/BTM/TCC、未执行驱动安装或 sfltool resetbtm。
- Swift 默认缓存路径受沙箱限制，改用项目内 `work/module-cache` 后构建成功。一次中间通用构建因源码同时变化而中止，已废弃，之后固定源码重新验证。

## 验证结果

| 检查 | 结果 | 范围与限制 |
|---|---|---|
| `make test` | 421 checks 通过 | 原有协议/配置向量，加恢复状态机和 Replay Fake；不是 421 个独立硬件场景 |
| G/MX 状态丢失与无 0x41 恢复 | 通过 | StatefulMouse，未向真实设备发包 |
| 重连新会话、旧回调、功能索引变化 | 通过 | Fake；验证不恢复旧表、重新查询功能索引 |
| 失败重试与 4/8 秒退避 | 通过 | 虚拟 scheduler；三次失败请求新 Transport |
| 去重、睡眠取消、部分启动回滚 | 通过 | 不申请系统权限、不合成真实按键 |
| Replay 写入/bootout/bootstrap 失败回退 | 通过 | 临时目录与 Fake launchctl，无真实服务变更 |
| 旧版归属不明、原版共存、可验证迁移 | 通过 | 身份判断注入 Fake；真实签名验证代码完成编译，真实历史代理未迁移 |
| 同路径 ZIP 更新、并发注册锁 | 通过 | 文件指纹与 Fake；不能证明真实 BTM 允许执行 |
| arm64 + x86_64 universal 编译 | 通过 | 本机 CLT 对 x86_64 compatibility pack 有警告，最终链接成功 |
| app 签名、发行身份、版本、CLI/app 无设备入口 | 通过 | `scripts/verify-release.sh`，没有运行菜单栏 |
| 当前 USB 设备枚举 | 未取得 | 只读 ioreg 在本沙箱被拒绝，不能确认接收器 PID/实际 Transport |
| 5/15/30 分钟闲置、系统睡眠、拔插、多轮循环 | 未测试 | 需用户批准并配合实际鼠标操作 |
| DPI/报告率、配置切换、Deskflow 实际共存 | 未测试 | 配置与协议离线回归通过，不能代替设备验收 |
| 更新后的 TCC/BTM 连续性与 SMAppService 注销 | 未测试 | 未替换正式安装或注册/注销真实服务 |
| 常驻 CPU、电量与恢复耗时 | 未测量 | 只提供源码层面的请求频率分析，不虚报实测值 |

## 根因结论的证据等级

已经确认原实现存在“active 持续成功，但设备状态无法证明健康”的缺陷，以及 reapply 失败被吞掉、缺少无 0x41 恢复、旧 feature cache 跨会话继续使用等问题。保存配置会经文件监视器重建引擎、Transport 与订阅，这一因果链是源码事实。

**尚未证实当前用户故障究竟是设备 remap/spy 复位、输入通道失效、host 模式变化、权限或 Deskflow 动作执行层问题。** 修复覆盖这些故障边界中的可检测状态与通信恢复；不能将离线成功描述为实际根因已定位或设备验收通过。

## 性能与行为限制

新增恢复机制没有常驻健康 timer；输入活动中每分钟最多一次检查，G 为功能索引查询+表回读，MX 为功能索引查询+各映射 reporting flags 回读。闲置 >=60 秒后首次输入额外重订阅一次，用于覆盖表仍在但 spy 订阅丢失的不可回读情况。失败先 4/8 秒退避，必要时宿主重新发现，长期失败上限 120 秒。

既有每 300 秒菜单/电量刷新保留。NSEvent 输入监视有事件处理开销；未实测 CPU 与电量，不宣称开销为零。Deskflow 合成输入也可能触发一次限频检查。首次唤醒按键若早于恢复完成，可能不执行，不补发以避免重复动作。

ad-hoc designated requirement 实测含 cdhash、无 TeamIdentifier。代码变化可以改变签名身份约束；无法据此证明每次更新必然阻止 Replay。新版仅对自己的同路径、已安装新代理做指纹更新检查，不能绕过用户授权或替代 Developer ID 与公证。

## 交付与后续验收

运行时与生命周期方案分别见 [runtime-reliability.md](runtime-reliability.md)、[replay-lifecycle.md](replay-lifecycle.md)。安全安装、ZIP 更新、回退与卸载命令见 [README.zh-CN.md](../README.zh-CN.md)。本轮没有打发行 tag、没有合并 main。

下一步需经用户确认：备份现有 app/配置，退出当前引擎，运行验收版，按上述硬件表记录首次输入至恢复的耗时、CPU 与异常；失败时退出验收版并恢复旧 app，保持配置和权限数据库不动。无需自动重装或重置系统服务。
