# Nibble 简体中文版

基于 [ben0128/nibble](https://github.com/ben0128/nibble) 的个人使用简体中文版本。保留原项目的鼠标 HID++ 协议、按键映射逻辑、配置格式和应用 Bundle ID，仅翻译 macOS 图形界面与提示，并独立构建安装包。

## 下载和安装

1. 打开本仓库的 **Actions**，选择「构建 Nibble 中文版」。
2. 打开最近一次**成功**的运行，在页面底部 **Artifacts** 下载 `Nibble-zh-CN-macOS-universal`。
3. 解压下载包（可能需要连续解压两层 ZIP），得到 `Nibble.app`。
4. **先退出原版 Nibble**，再备份原版 `/Applications/Nibble.app`，最后把中文版放入 `/Applications`。
5. 打开中文版，并在 **系统设置 → 隐私与安全性** 中核实 **输入监控**、**辅助功能**授权。

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

- 按键配置文件仍使用 `~/.config/nibble.json`，**不会因为界面变中文而更改配置键名**。
- 例如 `mission-control`、`play-pause` 等内部动作 ID 仍保持英文，只将界面选项显示为中文。
- 汉化不负责改变 Deskflow 或 G502 的板载映射行为；Mac 上已验证的快捷键与权限设置应保持原样。
- 按键功能仍需运行 Nibble 菜单栏进程，退出应用后将由鼠标原有配置接管。

上游项目遵循 MIT 许可，版权与原始实现归原作者所有。此 fork 未经上游官方认证。
