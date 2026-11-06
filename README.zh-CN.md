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
