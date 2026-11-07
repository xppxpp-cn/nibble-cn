// SettingsWindow.swift — ② 原生設定面板（`nibble ui`）
// 設定器哲學：開 → 調 → 關窗即退出程序，零常駐。純 AppKit 手寫佈局，無 SwiftUI runtime。
import AppKit

/// 說明全靠 hover 才看得到，那 hover 就不該等——AppKit 預設要 1.5 秒以上，
/// 對「移過去看一眼」的用法太久。註冊在 registration domain：只影響這個程序，
/// 不會像 `defaults write -g` 那樣改掉使用者整台機器的行為，也不寫進偏好檔。
/// 單位是毫秒。200 而不是 0：夠快到感覺是「馬上」，又留一點餘裕讓游標
/// 掠過一排控制項時不會沿途閃出一串提示。
func nibbleFastTooltips() {
    UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 200])
}

/// 說明性文字改成 hover 才顯示的「?」——常駐灰字會把視窗塞滿但多數時候沒人在讀
func nibbleHelpBadge(_ text: String) -> NSImageView {
    let view = NSImageView()
    view.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: text)
    view.contentTintColor = .tertiaryLabelColor
    view.toolTip = text
    view.setContentHuggingPriority(.required, for: .horizontal)
    view.setContentCompressionResistancePriority(.required, for: .horizontal)
    return view
}

/// 區段標題後面掛一個說明圖示
func nibbleSectionRow(_ label: NSView, help: String) -> NSStackView {
    let row = NSStackView(views: [label, nibbleHelpBadge(help)])
    row.spacing = 5
    row.alignment = .centerY
    return row
}

func runSettingsUI(initialTab: String? = nil) -> Int32 {
    nibbleFastTooltips()
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = SettingsDelegate()
    delegate.initialTab = initialTab
    app.delegate = delegate
    app.run()
    return 0
}

final class SettingsDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTabViewDelegate {
    private var window: NSWindow!
    private let deviceLabel = NSTextField(labelWithString: "正在检测…")
    private let batteryLabel = NSTextField(labelWithString: "")
    // DPI 用與選單列相同的級距——先前滑桿 100–6400、選單 400–3200、CLI 50–25600 三套並存
    private let dpiControl = NSSegmentedControl(labels: MenuBarDelegate.dpiPresets.map(String.init),
                                                trackingMode: .selectOne, target: nil, action: nil)
    private let dpiCustom = NSTextField(string: "")
    private let rateControl = NSSegmentedControl(labels: ["125", "250", "500", "1000"], trackingMode: .selectOne, target: nil, action: nil)
    private let rgbControl = NSSegmentedControl(labels: ["关闭", "循环", "呼吸"], trackingMode: .selectOne, target: nil, action: nil)
    private let replayCheck = NSButton(checkboxWithTitle: "登录时恢复我的设置", target: nil, action: nil)
    private let startupCheck = NSButton(checkboxWithTitle: "登录时启动 Nibble", target: nil, action: nil)
    private let startupNote = NSTextField(labelWithString: "")
    private let notifyCheck = NSButton(checkboxWithTitle: "低于此电量时提醒", target: nil, action: nil)
    private let notifyField = NSTextField(string: "")
    // 健康狀態列：改鍵沒反應時的答案幾乎都在這三行裡（先前只有 CLI 的 `nibble doctor` 看得到）
    private let imValue = NSTextField(labelWithString: "正在检查…")
    private let axValue = NSTextField(labelWithString: "正在检查…")
    private let engineValue = NSTextField(labelWithString: "正在检查…")
    private let imFix = NSButton(title: "打开系统设置…", target: nil, action: nil)
    private let axFix = NSButton(title: "打开系统设置…", target: nil, action: nil)
    private let engineFix = NSButton(title: "启动 Nibble", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: " ")
    private let aboutButton = NSButton(title: "GitHub", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let closeButton = NSButton(title: "关闭", target: nil, action: nil)
    /// Save 只屬於 Buttons 分頁；General 是即時寫入的，那裡不該擺一顆永遠灰著的按鈕
    private var onButtonsTab = false
    private var lastIndex: UInt8 = 1
    private var lastRGB: String? = lastKnownRGB()
    private let buttonsPane = ButtonsPane()
    private var headerTimer: Timer?
    private var statusClear: DispatchWorkItem?
    private var rememberWork: DispatchWorkItem?
    var initialTab: String?
    private static let rateValues = [125, 250, 500, 1000]
    private static let rgbKinds = ["off", "cycle", "breathing"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        deviceLabel.font = .boldSystemFont(ofSize: 14)
        batteryLabel.textColor = .secondaryLabelColor
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        rgbControl.toolTip = "灯光设置将立即写入设备。鼠标不会返回当前灯效，因此显示的是 Nibble 上次设置的效果。"
        rateControl.toolTip = "报告率越高，追踪越流畅，但耗电略高。设置时需要主机模式，Nibble 会自动切换。"
        replayCheck.toolTip = "安装一次性登录任务，登录时执行 `nibble apply` 后立即退出，不会常驻。"

        dpiControl.target = self
        dpiControl.action = #selector(dpiPresetChanged)
        dpiControl.segmentDistribution = .fillEqually
        // 欄位只需容納 5 位數；全寬的輸入框會讓人以為要填長字串
        dpiCustom.placeholderString = "50–25600"
        dpiCustom.toolTip = "可输入传感器支持的 DPI。若鼠标按键设定的 DPI 不在预设值中，会在此显示。"
        dpiCustom.target = self
        dpiCustom.action = #selector(dpiCustomCommitted)
        dpiCustom.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        dpiCustom.alignment = .right
        dpiCustom.translatesAutoresizingMaskIntoConstraints = false
        dpiCustom.widthAnchor.constraint(equalToConstant: 74).isActive = true
        replayCheck.target = self
        replayCheck.action = #selector(replayToggled)
        startupCheck.target = self
        startupCheck.action = #selector(startupToggled)
        startupCheck.toolTip = "保持菜单栏程序运行，由它执行按键映射。"
                             + "如果不启用，重启后按键映射不会运行；下方的登录时恢复设置仅负责 DPI、报告率和灯光。"
        startupNote.font = .systemFont(ofSize: 11)
        startupNote.textColor = .systemOrange
        startupNote.isHidden = true
        notifyCheck.target = self
        notifyCheck.action = #selector(notifyToggled)
        notifyField.target = self
        notifyField.action = #selector(notifyFieldCommitted)
        notifyField.alignment = .right
        notifyField.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        notifyField.placeholderString = "\(defaultLowBatteryPercent)"
        notifyField.translatesAutoresizingMaskIntoConstraints = false
        notifyField.widthAnchor.constraint(equalToConstant: 46).isActive = true
        for b in [imFix, axFix, engineFix] {
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 11)
            b.target = self
        }
        imFix.action = #selector(openInputMonitoringAction)
        axFix.action = #selector(openAccessibilityAction)
        engineFix.action = #selector(startMenuBarAction)
        engineFix.toolTip = "启动 /Applications/Nibble.app，菜单栏程序负责运行按键映射引擎。"
        rateControl.target = self
        rateControl.action = #selector(rateChanged(_:))
        rgbControl.target = self
        rgbControl.action = #selector(rgbChanged(_:))

        let customCaption = NSTextField(labelWithString: "自定义")
        customCaption.font = .systemFont(ofSize: 11)
        customCaption.textColor = .secondaryLabelColor
        let dpiCustomRow = NSStackView(views: [customCaption, dpiCustom])
        dpiCustomRow.spacing = 6
        dpiCustomRow.alignment = .centerY

        // 兩個「登入時」的勾選框刻意相鄰又分工明確：一個讓程式活著（改鍵才有宿主），
        // 一個把裝置設定寫回去。先前只有後者，重開機後按鍵全死卻沒人說得出為什麼。
        let launchRow = NSStackView(views: [
            startupCheck,
            nibbleHelpBadge("只有 Nibble 菜单栏程序运行时，按键映射才能生效。"
                          + "启用后会注册登录启动项，重启后自动运行。"),
            startupNote,
        ])
        launchRow.spacing = 8
        launchRow.alignment = .centerY

        // 勾選框就是「保留我的設定」的唯一開關：勾了之後每次改動自動記錄，
        // 不再需要一顆語意跟右下角 Save 撞車的按鈕
        let startupRow = NSStackView(views: [
            replayCheck,
            nibbleHelpBadge("本页面的设置会立即写入鼠标，但鼠标断电后会丢失，"
                          + "并恢复板载配置。勾选此项后，程序会记录当前设置，"
                          + "登录时自动重新应用，无需手动保存。"),
        ])
        startupRow.spacing = 8
        startupRow.alignment = .centerY

        let percentLabel = NSTextField(labelWithString: "%")
        percentLabel.textColor = .secondaryLabelColor
        let notifyRow = NSStackView(views: [
            notifyCheck, notifyField, percentLabel,
            nibbleHelpBadge("低电量通知由菜单栏程序发送，因此需要保持菜单栏运行。"
                          + "每次放电周期只提醒一次，充电后重置提醒状态。"
                          + "达到相同电量阈值时，菜单栏图标会变红。"),
        ])
        notifyRow.spacing = 6
        notifyRow.alignment = .centerY

        let statusHeader = nibbleSectionRow(sectionLabel("运行状态"),
            help: "按键映射依赖三项状态：输入监控允许 Nibble 读取鼠标，"
                + "辅助功能允许模拟按键，映射引擎运行在菜单栏程序中。"
                + "权限状态取自实际运行引擎的进程；也可以运行 `nibble doctor` 检查。")

        let generalStack = NSStackView(views: [
            sectionLabel("DPI"), dpiControl, dpiCustomRow,
            sectionLabel("报告率（Hz）"), rateControl,
            nibbleSectionRow(sectionLabel("灯光效果"),
                             help: "无法从鼠标读取灯光状态，Nibble 显示上次应用的效果。"
                                 + "鼠标断电后会恢复板载配置。"),
            rgbControl,
            NSBox(), launchRow, startupRow, notifyRow,
            NSBox(), statusHeader,
            healthRow("输入监控", imValue, imFix),
            healthRow("辅助功能", axValue, axFix),
            healthRow("按键映射引擎", engineValue, engineFix),
        ])
        generalStack.orientation = .vertical
        generalStack.alignment = .leading
        generalStack.spacing = 8
        for case let box as NSBox in generalStack.views { box.boxType = .separator }

        let tabs = NSTabView()
        tabs.delegate = self
        tabs.translatesAutoresizingMaskIntoConstraints = false
        let general = NSTabViewItem(identifier: "general")
        general.label = "常规"
        general.view = Self.pane(generalStack, pinBottom: false)
        tabs.addTabViewItem(general)

        let buttons = NSTabViewItem(identifier: "buttons")
        buttons.label = "按键"
        buttons.view = buttonsPane.makeView()
        tabs.addTabViewItem(buttons)
        buttonsPane.onStatus = { [weak self] msg in self?.setStatus(msg) }
        buttonsPane.onPendingChange = { [weak self] count in
            self?.saveButton.isEnabled = count > 0
            self?.saveButton.title = count > 0 ? "保存（\(count)）" : "保存"
            self?.syncSaveButton()
        }

        // Save/Close：改鍵不再邊改邊寫檔，改動先暫存，按 Save 才落地
        saveButton.target = self
        saveButton.action = #selector(saveButtonsAction)
        // Enter 直接儲存——但只在 Buttons 分頁（見 syncSaveButton）。預設按鈕會在
        // 第一響應者之前吃掉 Return，在 General 打 DPI 按 Enter 就會變成「送出改鍵」。
        saveButton.isEnabled = false
        saveButton.toolTip = "将暂存的按键修改写入配置文件，随后菜单栏重新加载映射引擎。"
        closeButton.target = self
        closeButton.action = #selector(closeAction)
        closeButton.keyEquivalent = "\u{1b}"     // Esc 關窗
        // 放進 NSStackView：藏起 Save 時堆疊會自動收合它的位置，Close 就補上右下角，
        // 不會留一塊「本來有東西」的空白。單獨下約束做不到這件事。
        let buttonBar = NSStackView(views: [closeButton, saveButton])
        buttonBar.spacing = 10
        buttonBar.alignment = .centerY

        // 版本資訊移到右上角：右下角留給 Save/Close
        aboutButton.bezelStyle = .inline
        aboutButton.isBordered = false
        aboutButton.target = self
        aboutButton.action = #selector(openRepo)
        // 「GitHub」用強調色標示可點，版本號用次要色——一眼分得出哪部分是連結
        let footer = NSMutableAttributedString(string: "GitHub", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.controlAccentColor,
        ])
        footer.append(NSAttributedString(string: "  ·  v\(NIBBLE_VERSION)", attributes: [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        aboutButton.attributedTitle = footer
        aboutButton.toolTip = "github.com/ben0128/nibble — MIT"
        aboutButton.setContentHuggingPriority(.required, for: .horizontal)
        aboutButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        // 全程 Auto Layout：NSTabView 用 frame 幫分頁排版，內容一旦帶固定約束就會打架、溢出邊界
        let root = NSView()
        for v in [deviceLabel, batteryLabel, tabs, statusLabel, aboutButton, buttonBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.usesSingleLineMode = true
        statusLabel.cell?.truncatesLastVisibleLine = true
        // 關鍵：不讓長字串把視窗頂寬——標籤讓步，超長就截斷
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        deviceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        deviceLabel.lineBreakMode = .byTruncatingTail
        batteryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            deviceLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            deviceLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            deviceLabel.trailingAnchor.constraint(lessThanOrEqualTo: aboutButton.leadingAnchor, constant: -12),

            batteryLabel.topAnchor.constraint(equalTo: deviceLabel.bottomAnchor, constant: 2),
            batteryLabel.leadingAnchor.constraint(equalTo: deviceLabel.leadingAnchor),
            batteryLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -18),

            tabs.topAnchor.constraint(equalTo: batteryLabel.bottomAnchor, constant: 10),
            tabs.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            tabs.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),

            tabs.bottomAnchor.constraint(equalTo: buttonBar.topAnchor, constant: -10),
            statusLabel.topAnchor.constraint(greaterThanOrEqualTo: tabs.bottomAnchor, constant: 6),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: buttonBar.leadingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: buttonBar.centerYAnchor),

            buttonBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            buttonBar.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),

            aboutButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            aboutButton.centerYAnchor.constraint(equalTo: deviceLabel.centerYAnchor),
        ])

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 600),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = "Nibble"
        window.contentView = root
        window.contentMinSize = NSSize(width: 680, height: 580)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)

        if initialTab == "buttons" { tabs.selectTabViewItem(withIdentifier: "buttons") }
        onButtonsTab = (tabs.selectedTabViewItem?.identifier as? String) == "buttons"
        syncSaveButton()
        loadPreferences()
        refreshHealth()
        loadState()
        buttonsPane.reload()
        headerTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: true) { [weak self] _ in
            self?.refreshHeader()
            self?.refreshHealth()
        }
    }

    /// 勾了「登入重新套用」就代表使用者要保留現況——之後每次改動都自動記錄。
    /// 延遲 1.5 秒合併寫入：連續拖 DPI 不該變成一連串寫檔＋引擎重載。
    private func rememberIfEnabled() {
        guard replayCheck.state == .on else { return }
        rememberWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let dev = try? self.openDevice() else { return }
            try? uiSaveConfig(dev, rgb: self.lastRGB)
        }
        rememberWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    /// 狀態列是兩個分頁共用的，訊息卻是當下情境的——不清掉的話，
    /// 在 General 觸發的警告會跟著你飄到 Buttons 分頁，看起來像在講別的事。
    private func setStatus(_ text: String, sticky: Bool = false) {
        statusClear?.cancel()
        statusLabel.stringValue = text
        guard !sticky, !text.isEmpty else { return }
        let work = DispatchWorkItem { [weak self] in self?.statusLabel.stringValue = "" }
        statusClear = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        setStatus("")
        onButtonsTab = (tabViewItem?.identifier as? String) == "buttons"
        syncSaveButton()
    }

    /// General 是即時寫入的，沒有東西可以 Save——那裡就不擺這顆按鈕。
    /// 唯一例外：Buttons 有暫存改動時仍然留著，否則切個分頁就找不到儲存的地方了。
    private func syncSaveButton() {
        saveButton.isHidden = !onButtonsTab && buttonsPane.pendingCount == 0
        // Return 只在 Buttons 分頁代表「儲存」；在 General 它該留給輸入框
        saveButton.keyEquivalent = onButtonsTab ? "\r" : ""
    }

    // 設定器哲學：關窗即退出
    func windowWillClose(_ notification: Notification) {
        headerTimer?.invalidate()
        buttonsPane.teardown()
        NSApp.terminate(nil)
    }

    /// 分頁內容統一包一層容器，四邊用約束釘住——這樣分頁縮放時內容跟著走，不會溢出
    static func pane(_ content: NSView, pinBottom: Bool) -> NSView {
        let container = NSView()
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        var cs = [
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ]
        cs.append(pinBottom
            ? content.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12)
            : content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -12))
        NSLayoutConstraint.activate(cs)
        return container
    }

    @objc private func saveButtonsAction() {
        buttonsPane.commitPending()
    }

    @objc private func closeAction() {
        window.performClose(nil)
    }

    /// 有未儲存的改動就先問——直接關掉等於默默丟棄使用者剛做的事
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard buttonsPane.pendingCount > 0 else { return true }
        let alert = NSAlert()
        alert.messageText = "保存 \(buttonsPane.pendingCount) 项按键修改？"
        alert.informativeText = "这些修改尚未写入配置文件。"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "放弃修改")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn: buttonsPane.commitPending(); return true
        case .alertSecondButtonReturn: buttonsPane.discardPending(); return true
        default: return false
        }
    }

    @objc private func openRepo() {
        NSWorkspace.shared.open(URL(string: "https://github.com/ben0128/nibble")!)
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        return l
    }

    private func openDevice() throws -> HIDPPDevice {
        let (dev, idx) = try uiOpenDevice(preferred: lastIndex)
        lastIndex = idx
        return dev
    }

    private func loadState() {
        do {
            let dev = try openDevice()
            deviceLabel.stringValue = (try? dev.name()) ?? "Logitech #\(lastIndex)"
            updateBattery(dev)
            do {
                let tr = dev.transport
                // 連線細節屬於除錯資訊，放 hover；表頭留給名字和電量
                deviceLabel.toolTip = String(format: "%@ 046D:%04X · device index %d · HID++",
                                             tr.isDirect ? "bluetooth-direct" : "receiver",
                                             tr.productID, Int(lastIndex))
            }
            if let dpi = try? dev.currentDPI() { showDPI(dpi) }
            if let hz = try? dev.reportRateHz(), let i = Self.rateValues.firstIndex(of: hz) {
                rateControl.selectedSegment = i
            }
            let supported = (try? dev.supportedReportRatesHz()) ?? []
            // 支援清單放 tooltip：它和上面那排按鈕通常一模一樣，常駐顯示只是重複
            if !supported.isEmpty {
                rateControl.toolTip = "此设备支持 "
                    + supported.sorted().map(String.init).joined(separator: " / ") + " Hz. "
                    + "设置报告率需要主机模式，Nibble 会自动切换。"
            }
            showLighting()
            setStatus("就绪")
        } catch {
            deviceLabel.stringValue = "鼠标离线或处于休眠状态"
            batteryLabel.stringValue = "移动鼠标唤醒，然后重新打开此页面"
            setStatus("❌ \(error)", sticky: true)
        }
    }

    /// 只更新表頭；失敗就沿用上次的值，不要把畫面清空或跳錯誤
    /// （選單列的引擎同時握著裝置，偶爾搶不到很正常）
    private func refreshHeader() {
        guard let dev = try? openDevice() else { return }
        updateBattery(dev)
    }

    private func updateBattery(_ dev: HIDPPDevice) {
        guard let b = try? dev.battery() else { return }
        let volt = b.millivolts.map { String(format: " · %.2fV", Double($0) / 1000) } ?? ""
        batteryLabel.stringValue = "🔋 \(b.percent)%\(volt) · \(b.charging ? "正在充电" : "放电中")"
    }

    /// 現值若不在級距上（例如滑鼠上的 DPI 鍵調出來的），就顯示在 Custom 欄位而不是假裝選中某一格
    private func showDPI(_ dpi: Int) {
        if let i = MenuBarDelegate.dpiPresets.firstIndex(of: dpi) {
            dpiControl.selectedSegment = i
            dpiCustom.stringValue = ""
        } else {
            dpiControl.selectedSegment = -1
            dpiCustom.stringValue = "\(dpi)"
        }
    }

    private func showLighting() {
        if let kind = lastRGB, let i = Self.rgbKinds.firstIndex(of: kind) {
            rgbControl.selectedSegment = i
        } else {
            rgbControl.selectedSegment = -1
        }
    }

    private func applyDPI(_ target: Int) {
        do {
            let dev = try openDevice()
            var got = 0
            try uiHostFallback(dev) { got = try dev.setDPI(target) }
            showDPI(got)
            statusLabel.stringValue = got == target ? "DPI → \(got) ✓" : "⚠️ 期望值 \(target), 设备报告 \(got)"
        } catch { setStatus("❌ \(error)") }
    }

    @objc private func dpiPresetChanged() {
        guard dpiControl.selectedSegment >= 0 else { return }
        applyDPI(MenuBarDelegate.dpiPresets[dpiControl.selectedSegment])
    }

    @objc private func dpiCustomCommitted() {
        let text = dpiCustom.stringValue.trimmingCharacters(in: .whitespaces)
        guard let v = Int(text), (50...25600).contains(v) else {
            setStatus("⚠️ DPI 必须介于 50 到 25600 之间")
            return
        }
        applyDPI(v)
    }

    @objc private func replayToggled() {
        let on = replayCheck.state == .on
        let result = cmdReplay([on ? "install" : "uninstall"])
        replayCheck.state = FileManager.default.fileExists(atPath: replayPlistURL.path) ? .on : .off
        if result != 0 { setStatus("❌ Replay 操作失败，请运行 nibble replay status --json 查看状态", sticky: true) }
        else { setStatus(on ? "已注册登录恢复；可在系统登录项中检查授权" : "已关闭登录时恢复设置") }
    }

    @objc private func rateChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0 else { return }
        let hz = Self.rateValues[sender.selectedSegment]
        do {
            let dev = try openDevice()
            var got = 0
            try uiHostFallback(dev) { got = try dev.setReportRateHz(hz) }
            statusLabel.stringValue = got == hz ? "报告率 → \(got) Hz ✓" : "⚠️ 期望值 \(hz), 设备报告 \(got)"
        } catch { setStatus("❌ \(error)") }
    }


    /// 授權完回到這個視窗的那一刻就要看到新狀態——不然使用者會以為授權沒生效
    func applicationDidBecomeActive(_ notification: Notification) {
        refreshHealth()
    }

    /// 裝置無關的偏好設定。刻意不放在 loadState 裡：那邊開不到滑鼠就整段跳掉，
    /// 於是滑鼠睡著時這些勾選框會顯示成「沒開」——明明是開著的。
    private func loadPreferences() {
        replayCheck.state = FileManager.default.fileExists(atPath: replayPlistURL.path) ? .on : .off
        let cfg = loadConfig()
        let limit = lowBatteryThreshold(cfg)
        notifyCheck.state = limit == nil ? .off : .on
        // 關閉狀態下也顯示夾過的值：手改成 99 卻顯示 99，會讓人以為那是生效中的門檻
        let shown = limit ?? cfg?.lowBatteryPercent.map { min(max($0, lowBatteryRange.lowerBound), lowBatteryRange.upperBound) }
                          ?? defaultLowBatteryPercent
        notifyField.stringValue = "\(shown)"
        notifyField.isEnabled = limit != nil
    }

    private func healthRow(_ title: String, _ value: NSTextField, _ fix: NSButton) -> NSStackView {
        let name = NSTextField(labelWithString: title)
        name.font = .systemFont(ofSize: 11, weight: .medium)
        name.textColor = .secondaryLabelColor
        name.translatesAutoresizingMaskIntoConstraints = false
        name.widthAnchor.constraint(equalToConstant: 116).isActive = true   // 固定欄寬讓三行的值對齊
        value.font = .systemFont(ofSize: 11)
        value.lineBreakMode = .byTruncatingTail
        value.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [name, value, fix])
        row.spacing = 8
        row.alignment = .centerY
        return row
    }

    /// ok = nil 代表「不是問題，只是還沒設定」——用灰點而不是紅叉，免得看起來像壞了
    private func setHealth(_ field: NSTextField, ok: Bool?, _ text: String) {
        switch ok {
        case true:  field.stringValue = "✓  " + text; field.textColor = .secondaryLabelColor
        case false: field.stringValue = "✗  " + text; field.textColor = .systemRed
        case nil:   field.stringValue = "–  " + text; field.textColor = .tertiaryLabelColor
        }
    }

    private func refreshHealth() {
        let im = inputMonitoringGranted()
        setHealth(imValue, ok: im, im ? "已授权" : "未授权，Nibble 无法读取鼠标")
        imFix.isHidden = im

        let st = EngineState.read()
        let running = menuBarRunning()
        // 引擎跑在選單列那個程序裡，所以要看它回報的授權狀態，不是這個視窗自己的
        //（從終端機跑 `nibble ui` 時，這個程序的授權是終端機的，跟 Nibble.app 無關）。
        // 但那份狀態是「上次回報」——選單列關掉後就不再更新，而重建 bundle 會讓
        // 綁在 cdhash 上的授權失效。所以沒在跑的時候只能說不知道，不能照著舊值說 ✓。
        if running, let ax = st["axTrusted"] as? Bool {
            setHealth(axValue, ok: ax, ax ? "已授权" : "未授权，按键映射无法执行")
            axFix.isHidden = ax
        } else if running {
            setHealth(axValue, ok: nil, "等待菜单栏上报状态")
            axFix.isHidden = false
        } else {
            setHealth(axValue, ok: nil, "未知，菜单栏未运行")
            axFix.isHidden = false
        }

        let mapped = activeButtonMaps(loadConfig()).values.reduce(0) { $0 + $1.count }
        if !running {
            setHealth(engineValue, ok: mapped > 0 ? false : nil,
                      mapped > 0 ? "菜单栏未运行，\(mapped) 项按键映射未生效"
                                 : "菜单栏未运行")
            engineFix.isHidden = false
        } else if st["active"] as? Bool == true {
            let n = st["mappings"] as? Int ?? 0
            setHealth(engineValue, ok: true, "运行中 · \(n) 项按键映射")
            engineFix.isHidden = true
        } else {
            let reason = st["reason"] as? String ?? "菜单栏尚未上报状态"
            // Keep machine-readable engine reasons in English; translate only the UI.
            let readableReason: String
            switch reason {
            case "no mappings configured": readableReason = "尚未配置按键映射"
            case "Accessibility permission not granted": readableReason = "未授权辅助功能权限"
            case "device exposes neither 0x8110 nor 0x1b04": readableReason = "设备不支持按键映射"
            case "device disconnected — waiting for reconnect": readableReason = "设备已断开，等待重新连接"
            case "paused by user": readableReason = "用户已暂停映射"
            default:
                readableReason = reason.hasPrefix("no mappings for ")
                    ? "当前设备没有配置按键映射"
                    : reason
            }
            // 尚未配置按键不是故障，不显示红色错误状态。
            setHealth(engineValue, ok: reason.contains("no mappings") ? nil : false, readableReason)
            engineFix.isHidden = true
        }

        let login = LoginItem.snapshot
        startupCheck.isEnabled = login.supported
        startupCheck.state = login.enabled ? .on : .off
        startupNote.isHidden = (login.note == "on" || login.note == "off")
        startupNote.stringValue = startupNote.isHidden ? "" : login.note
    }

    @objc private func openInputMonitoringAction() { openInputMonitoringSettings() }

    @objc private func openAccessibilityAction() { openAccessibilitySettings() }

    @objc private func startMenuBarAction() {
        let url = URL(fileURLWithPath: "/Applications/Nibble.app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            setStatus("⚠️ 未找到 /Applications/Nibble.app，请先运行 `make install-app`", sticky: true)
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, err in
            DispatchQueue.main.async {
                guard let self else { return }
                if let err {
                    self.setStatus("❌ \(err.localizedDescription)", sticky: true)
                } else {
                    self.setStatus("正在启动菜单栏…")
                    self.scheduleHealthRecheck()
                }
            }
        }
    }

    /// 選單列剛啟動時還沒寫過狀態檔，立刻重讀會看到舊值
    private func scheduleHealthRecheck() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.refreshHealth() }
    }

    @objc private func startupToggled() {
        let on = startupCheck.state == .on
        var failure: String?
        do { try LoginItem.set(on) } catch { failure = "\(error)" }
        refreshHealth()   // 系統可能拒絕或需要核可，勾選框要反映真實狀態而不是使用者的點擊
        // 訊息要在 refreshHealth 之後、依照真正生效的狀態決定——
        // 先前會出現「will start at login ✓」旁邊那個勾選框自己彈回去的矛盾畫面
        if let failure {
            setStatus("❌ \(failure)", sticky: true)
        } else if LoginItem.needsApproval {
            setStatus("已注册，但被 macOS 阻止；请在“系统设置 › 通用 › 登录项”中启用 Nibble", sticky: true)
        } else {
            setStatus(LoginItem.enabled ? "Nibble 将在登录时启动 ✓" : "已关闭登录启动")
        }
    }

    @objc private func notifyToggled() {
        applyNotifySettings()
    }

    @objc private func notifyFieldCommitted() {
        applyNotifySettings()
    }

    private func applyNotifySettings() {
        let on = notifyCheck.state == .on
        let typed = Int(notifyField.stringValue.trimmingCharacters(in: .whitespaces))
        let clamped = on && typed != nil && !lowBatteryRange.contains(typed!)
        do {
            try updateLowBatteryNotify(enabled: on, percent: typed ?? defaultLowBatteryPercent)
            loadPreferences()   // 夾過範圍後把真正生效的值寫回欄位
            // 一次只講一句話：先前警告訊息會被下面那句成功訊息立刻蓋掉，
            // 於是輸入 99 只看得到「已設定 50%」，沒人知道自己打的值被改了
            guard on else { setStatus("已关闭低电量提醒"); return }
            setStatus(clamped
                ? "⚠️ \(lowBatteryRange.lowerBound)–\(lowBatteryRange.upperBound)% only — using \(notifyField.stringValue)%"
                : "低电量提醒阈值 \(notifyField.stringValue)% ✓")
        } catch {
            setStatus("❌ \(error)", sticky: true)
        }
    }

    @objc private func rgbChanged(_ sender: NSSegmentedControl) {
        guard sender.selectedSegment >= 0 else { return }
        let kind = Self.rgbKinds[sender.selectedSegment]
        do {
            let dev = try openDevice()
            let applied = try uiSetRGB(dev, kind: kind)
            lastRGB = kind
            showLighting()
            statusLabel.stringValue = applied > 0 ? "灯光效果 → \(kind) ✓" : "⚠️ 此设备不支持该灯光效果"
        } catch { setStatus("❌ \(error)") }
    }

}
