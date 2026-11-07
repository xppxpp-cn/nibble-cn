# Nibble 简体中文版

基于 [ben0128/nibble](https://github.com/ben0128/nibble) 的个人使用简体中文版本。保留原项目的鼠标 HID++ 协议、按键映射逻辑与配置格式，采用**独立应用 Bundle ID `com.xppxpp.nibblecn`** 与显示名称「Nibble 中文版」，避免与英文版 `com.ben0128.nibble` 的 macOS 辅助功能权限混淆。

## 下载和安装

1. 打开本仓库的 **Actions**，选择「构建 Nibble 中文版」。
2. 打开最近一次**成功**的运行，在页面底部 **Artifacts** 下载 `Nibble-zh-CN-macOS-universal`。
3. 解压下载包（可能需要连续解压两层 ZIP），得到 `Nibble.app`。
4. **先退出原版 Nibble**，再备份原版 `/Applications/Nibble.app`，最后把中文版放入 `/Applications`。
5. 打开中文版，并在 **系统设置 → 隐私与安全性** 中核实 **输入监控**、**允许辅助应用程序控制电脑**授权（macOS 27 的名称）。中文版应作为「Nibble 中文版」独立出现，不应被认作「Nibble-en」。

> GitHub Actions 产物是 ad-hoc 签名、未经过 Apple 公证的个人构建版。如果 macOS 因隔离标记拦截你信任的本仓库构建，请确认来源后在终端执行：
>
> ```bash
> xattr -dr com.apple.quarantine /Applications/Nibble.app
> ```
>
> 代码签名变化后，macOS 可能要求重新开启或重新添加上述两项权限。不要在原版仍运行时直接覆盖。

## 打包方式

- **日常构建**：每次向 `main` 推送、PR 更新或手动运行 `build-zh-cn.yml`，都会执行 `make test`、`make universal`、`make app`，上传同时包含 `arm64` 和 `x86_64` 的 ZIP。
- **正式归档**：推送形如 `cn-v1.8.1-1` 的 tag 时，`release.yml` 会在**本 fork** 创建 GitHub Release，不会修改原作者的 Homebrew 仓库。
- 不需要在 Windows 上安装 Swift 编译环境，也不需要 Apple 开发者账号。

## 与原版兼容

- **英文版与中文版的 macOS 权限身份相互独立**，但按键配置文件仍然共用同一路径。不要让两个版本同时运行。
- 按键配置文件仍使用 `~/.config/nibble.json`，**不会因为界面变中文而更改配置键名**。
- 例如 `mission-control`、`play-pause` 等内部动作 ID 仍保持英文，只将界面选项显示为中文。
- 汉化不负责改变 Deskflow 或 G502 的板载映射行为；Mac 上已验证的快捷键与权限设置应保持原样。
- 按键功能仍需运行 Nibble 菜单栏进程，退出应用后将由鼠标原有配置接管。

上游项目遵循 MIT 许可，版权与原始实现归原作者所有。此 fork 未经上游官方认证。

## 旧中文版授权异常的处理

2026-11-06 之前的首版汉化构建沿用了原版 `com.ben0128.nibble`，在某些 macOS 27 环境中，手动选择中文版授予「允许辅助应用程序控制电脑」权限时，系统却重新列出已改名的英文版 `Nibble-en`。这属于两个应用共用身份引发的授权冲突。

应退出旧中文版并用本次独立 Bundle ID 构建的 `Nibble.app` 替换它，再重新添加新版权限项。无需删除英文版备份，也不必调整原有键盘修饰键或 Deskflow 配置。每次重新编译仍可能因 ad-hoc 签名变化要求重新授权。

## 闲置后的自动恢复

菜单栏现在区分最近一次应用成功、设备端映射回读和真实按键事件。无线重连会重新发现设备；系统唤醒与闲置后的输入会触发有界恢复；恢复失败会退避并在必要时重建 Transport。正常活动时健康检查最多每分钟一次，闲置时不新增 HID 检查 timer，不会自动保存配置，不写 Flash。

`engine.json` 的 active 不是端到端验证，不能保证目标应用或 Deskflow 接收了合成快捷键。完整调查、已确认事实和待验证项见 [运行时可靠性报告](docs/runtime-reliability.md)。当前修复尚未完成 G502 LIGHTSPEED 的 5/15/30 分钟实机验收。

## 两种登录功能

- **登录时启动 Nibble**：`SMAppService.mainApp` 启动菜单栏，负责常驻按键映射。
- **登录时恢复我的设置**：一次性 Replay Agent 恢复 DPI、报告率和灯光，执行完退出。

两者可以独立启用。下面的命令均需用户在安装后主动执行；仓库测试不会注册真实服务。

```bash
/Applications/Nibble.app/Contents/MacOS/nibble startup on
/Applications/Nibble.app/Contents/MacOS/nibble replay install
/Applications/Nibble.app/Contents/MacOS/nibble replay status --json
```

Replay 使用独立的 `com.xppxpp.nibblecn.replay`。旧 `com.ben0128.nibble.replay` 只有执行目标和签名身份可以确认为中文版时才迁移；英文版、历史裸 CLI 或路径已失效的代理会保留并提示。不要仅凭旧 label 手动删除它。详见 [Replay 生命周期说明](docs/replay-lifecycle.md)。

## 从 Actions ZIP 安全更新与回退

1. 下载成功构建的 ZIP，先把旧 app 复制到安全的备份目录，并备份 `~/.config/nibble.json`。不要删除英文版备份或授权记录。
2. 退出当前菜单栏及设置窗口，确认进程已经结束，再将解压出的整个 `Nibble.app` 替换到相同的 `/Applications/Nibble.app` 路径。不要单独覆盖 bundle 内的可执行文件。
3. 打开新 app，检查系统设置中的输入监控与辅助功能。ad-hoc 更新可能需要重新授权，不能保证历史授权保持有效；本仓库没有 Developer ID 签名和公证。
4. 已安装的**新版中文版 Replay** 会在 app 启动时检查同路径可执行文件的变化并更新自己的注册；不需要 `make install-app`。旧共享 label 的首次迁移请显式运行上面的 `replay install`。这不会绕过系统禁止的后台授权。
5. 运行 `doctor --json` 和 `replay status --json`，分别检查 plist、后台授权、job 加载、最近执行结果及引擎状态。job 加载不等于正在运行，也不等于 apply 成功。
6. 若升级失败，退出新版，将备份的旧 app 整体恢复到原路径，打开并重新检查权限。新版已注册的 Replay 若调用旧版不认识的 `replay run`，请在回退前用新版 `replay uninstall` 解除，回退后按旧版本支持的方式重新安装其 Replay。用户配置格式未变，不必清空 JSON。

日志位于 `~/Library/Logs/NibbleCN/`；`last-replay.json` 标注其对应版本和执行时间。旧记录只证明历史一次执行结果。

## 安全卸载

先退出菜单栏和设置窗口，从待卸载的**中文版 app** 执行：

```bash
/Applications/Nibble.app/Contents/MacOS/nibble uninstall-services
```

确认命令成功后再将该 app 移到废纸篓；若有手动创建的 CLI 链接，确认指向本中文版后再移除。该命令解除自己的 Replay 和 `SMAppService.mainApp`，失败返回非零，不删除用户 JSON、备份、原版 app、归属不明的旧代理或系统授权记录。不需要 `sfltool resetbtm`。

源码用户的 `make uninstall` 也先调用安装 app 的服务解除命令，失败会停止，避免直接删除仍有注册的程序。若此前已移走 app，先恢复它到原路径以正确注销，不要靠删除 plist 猜测系统已清理完成。

## 本地验证与发行检查

```bash
make test
make universal
make app
scripts/verify-release.sh
```

测试使用 Fake Transport 和 Fake launchd；编译缓存在项目 `work/module-cache`，不会向其他项目写构建文件。发行检查验证 arm64/x86_64、bundle 身份、签名、版本一致性及 CLI/app 的固定 Replay 身份。它不访问鼠标、不申请权限、不注册服务。CI 的通过结果不能代替真实设备验收。

本轮保留现有菜单栏图标，不引入新的 AI 图标或无关 UI 重构。专属 app 图标可作为后续视觉改进；它不影响发行身份或权限可靠性。MIT 许可和上游署名继续保留。
