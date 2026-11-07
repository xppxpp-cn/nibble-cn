# 运行时可靠性调查与离线验证

## 已确认事实与尚未确认的实际根因

原始版本 `8d7b1dc`：ReceiverTransport 被 HIDPPDevice 和 RemapEngine 持有，回调在当前线程的 default run loop 上投递。G 路径写入 0x8110 remap 表并启动 spy；MX 路径逐 CID 设置 0x1b04 divert。两条路径的 `active` 都只表示 start 曾成功，不能证明设备状态、事件通道或动作执行仍有效。

重连通知 0x41 是原实现唯一的无线会话恢复信号；断开位不会使引擎降级。延迟重挂失败被 `try?` 吞掉，没有重试或健康状态变更。没有 0x41 时，设备端状态复位无法被发现。IOHID removal 仅覆盖 collection 消失，不覆盖接收器仍在线而鼠标休眠的情况。

保存链路：MenuBar.saveAction → act/openDevice → uiSaveConfig（读 DPI/回报率，保留映射）→ saveConfig（原子替换 JSON）→ watchConfig（rename/write）→ 0.3 秒后 startEngine → stop 旧引擎并还原 → 新 Transport、新 HIDPPDevice → 写 remap/divert、启动 spy。保存本身没有切 host，也没有写鼠标 Flash。此链路同时重建多层状态，所以“保存有效”不能单独证明鼠标休眠就是根因。

**没有对当前安装执行硬件实验。** 接收器 PID、真实 Transport、是否缺失 0x41、是否存在 host 模式复位、Deskflow 影响及实际通道故障仍需测量。菜单定时刷新原本会另开 Transport，现改为复用引擎 device；这是生命周期收紧，不能宣称已实证该行为导致故障。

## 恢复机制

- 0x41 连接、系统唤醒触发单次恢复。失败标记 unhealthy，4/8 秒退避，三次失败后交由宿主重建 Transport。重建失败沿用 4 秒起、上限 120 秒退避。
- 输入事件只作为可能活动信号（包括 Deskflow 合成输入，不能证明来源）。活动中每分钟至多一次回读；无输入不新增 HID 健康查询。G 比较实际表，MX 回读 reporting flags，失配才写入。
- 闲置 >=60 秒后首次输入会额外重订阅一次，以覆盖 spy 订阅丢失但表未变的情况。已知 0x8110 接口没有订阅状态回读，此行为是有界恢复，不是持续写入或定时保存。首个唤醒按键可能在恢复完成前到达，不保证补发。
- whole-operation 串行队列防止 roundTrip 泵 run loop 时重入 start/stop/recovery。恢复使用 generation 失效旧任务；宿主回调用 engine 对象身份校验。Transport 拒绝重入，清空旧 inbox，不采信上次超时请求残留响应。
- 设备回调使用 common run loop modes，退出显式注销，保持与创建时相同 run loop。系统睡眠取消恢复；新 session 重新发现 feature index。
- G 左右键永不 patch，MX 主键排除。部分启动失败尝试恢复运行时设置；不执行 sector 写入。恢复/清理失败不可能保证设备已经回到默认状态，诊断需保留失败原因。

## 性能与验证范围

离线状态机和 StatefulMouse 不产生 HID 或 CGEvent，不调用真实 launchd。测试验证状态丢失、恢复、退避、去重、旧回调及新 session。CPU、实际 USB 请求、电量影响、恢复耗时及所有真实设备场景尚未测量，不能从 mock 测试推导。

既有每 300 秒电量/菜单刷新保留；新增输入监视没有轮询 timer，输入热路径只比较单调时间。正常活动每分钟一次 G 表读取，MX 每个映射 CID 一次读取。健康时不重启引擎。长期断开时宿主退避仍会探测设备。

参考：
- [Apple IOHIDDeviceScheduleWithRunLoop](https://developer.apple.com/documentation/iokit/1588660-iohiddeviceschedulewithrunloop)
- [OpenLogi 0x8110 接口分析](https://openlogi.org/hidpp/features/x8110-mouse-button-filter)：逆向资料，自身注明未硬件验证，不能代替 G502 实测。

## 待用户批准的硬件验收步骤

先备份安装包和 `~/.config/nibble.json`，记录当前权限与版本；退出现有进程，再运行测试版（是否替换 /Applications 需单独确认）。测试期间会暂时切换运行时按键映射，不写 Flash；退出测试版并启动旧版回退。

依次闲置 5/15/30 分钟，再测试系统睡眠、接收器拔插、切换 profile、多次循环和重启。每次记录首次输入、最后 spy 事件、健康状态变化、恢复时间以及进程 CPU。出现问题先取状态和日志，不清理授权数据库、不重装驱动、不自动保存配置作为补救。
