# Implementation Backlog

每个条目都应该可以拆成 issue。优先级按开发顺序排列。

## M0：工程基线和技术 Spike

### W0.1 创建 WinUI 3 工程

交付：

- `ORB.Windows.sln`
- `src/ORB.Windows`
- `tests/ORB.Windows.Tests`
- 空 MainWindow。
- 能加载 ORB icon。

验收：

- Debug 可启动。
- Release 可构建。
- 无硬件时打开空舞台不崩。

### W0.2 复制和加载产品图资源

交付：

- `origin.png`
- `radiance.png`
- `balance.png`
- `orb_icon_set/*`

验收：

- MainWindow 能显示三张图。
- 资源以 app package content 方式加载。

### W0.3 DNS-SD spike

交付：

- 最小 console/service 代码浏览 `_orb._tcp.local.`。
- Resolve host、port、TXT。
- 记录 Windows 11 实测结果。

验收：

- 接入真实 ESP32 时能发现，或明确失败原因。
- 输出是否需要 embedded mDNS fallback 的结论。

### W0.4 UDP heartbeat spike

交付：

- 默认端口 `43981` listener。
- 动态端口 fallback。
- JSON decode heartbeat。

验收：

- 能收到真实 ESP32 心跳。
- 默认端口被占用时动态端口可工作。
- 记录防火墙弹窗表现。

### W0.5 System metrics spike

交付：

- CPU total。
- Memory。
- Network total bps。
- Disk read/write bps。
- Per-core CPU 可行性结论。
- CPU P/E topology 可行性结论。

验收：

- 采样值每秒更新。
- 网络/磁盘有实际 IO 时数值变化。

## M1：模型、协议、存储

### W1.1 迁移 domain models

交付：

- `Models/` 下所有 domain model。
- enum raw values 和 Mac/固件一致。

验收：

- 模块类型、指标类型、连接状态可序列化。

### W1.2 DTO 和 JSON 映射

交付：

- `OrbDeviceStateDto`
- `OrbHeartbeatDto`
- `OrbPingResponseDto`
- `OrbPreviewActivationResponseDto`
- `OrbHeartbeatConfigResponseDto`
- `OrbFirmwareUploadResponseDto`

验收：

- 能 decode `PROTOCOL.md` 示例 JSON。

### W1.3 HTTP client

交付：

- `OrbHttpClient` 实现所有 API。
- Form encode。
- Multipart OTA。
- Timeout。
- HTTP error body logging。

验收：

- Mock server 验证每个 endpoint 的 method/path/body。

### W1.4 LUT mapper

交付：

- 默认 LUT。
- 插值 map。
- clamp。

验收：

- 单元测试覆盖端点补齐、乱序 points、超出范围。

### W1.5 AppStateStore

交付：

- `%APPDATA%\ORB\app_state.json`。
- async save。
- legacy migration。

验收：

- 缺文件返回默认状态。
- 坏 JSON 不崩并回默认。
- 保存再读取一致。

## M2：连接层

### W2.1 DeviceDiscoveryService

交付：

- DNS-SD browse/resolve。
- ServicesChanged snapshot。
- Stop cleanup。

验收：

- 服务新增/移除反映到 UI/debug log。

### W2.2 HeartbeatListenerService

交付：

- preferred/dynamic/unavailable status。
- HeartbeatReceived event。
- JSON decode error 不中断。

验收：

- 默认端口和动态端口两个场景通过。

### W2.3 ConnectionCoordinator

交付：

- 自动连接第一个服务。
- 心跳直连。
- reconnect 优先级。
- HTTP probe watchdog。
- heartbeat routing sync。

验收：

- 开机自动 online。
- 设备断电后 offline。
- 设备重启后自动恢复。

### W2.4 Manual IP

交付：

- 开发者设置中输入 IP/port。
- ping 成功后加载 state。

验收：

- DNS-SD 关闭时仍可连接。

## M3：指标和实时输出

### W3.1 WindowsSystemMetricsService

交付：

- CPU total。
- Memory。
- Network bps。
- Disk bps。
- Per-core best effort。
- Topology best effort。

验收：

- 空闲/负载状态变化合理。
- 首次采样 delta 项为 0，第二次开始有值。

### W3.2 Metric normalizer

交付：

- CPU/memory/rate normalization。
- fallback ranges。
- custom scale points。

验收：

- 单元测试覆盖网络/磁盘 piecewise。

### W3.3 OutputFrameScheduler

交付：

- metrics loop。
- ready gate。
- frame id。
- HTTP frame send。
- send failure logging。

验收：

- mock state + metrics 生成正确 frame。
- unknown/calibration/locate 时暂停。

## M4：首屏舞台

### W4.1 Stage layout

交付：

- Source + modules 横向排列。
- Mac 坐标常量迁移。
- 窗口 resize 重新布局。

验收：

- 760x520 和 1100x640 都不重叠。

### W4.2 Hotspots

交付：

- Source hotspot。
- Radiance tube hotspots。
- Balance gauge hotspots。
- Hover/active border。

验收：

- 点击目标区域准确。

### W4.3 Connection badge

交付：

- 状态圆点。
- 文案。
- 手动重连。
- tooltip。

验收：

- online/offline/not found 都显示正确。

### W4.4 Metric candidate panels

交付：

- Radiance tokens。
- Balance tokens。
- 点击绑定。
- 拖拽绑定。
- 已绑定 chip/label。
- 右键/拖回移除。

验收：

- CPU 多选和内存独占行为正确。
- Balance token 全局唯一。

### W4.5 Real-time simulation

交付：

- Radiance glow bars。
- Balance needle。
- Imported SVG display。
- Smoothing animation。

验收：

- 软件显示随 metrics 变化。

### W4.6 Module reorder

交付：

- 拖拽改变顺序。
- drop 后持久化。

验收：

- 重启后顺序保持。

## M5：注册和详情

### W5.1 Unknown device overlay

交付：

- 发现卡片。
- 注册面板。
- reset 面板。
- busy/notice/issue。

验收：

- `0x60` 新设备可注册。
- 旧地址设备可 reset 后继续注册。

### W5.2 Source detail

交付：

- 连接信息。
- 心跳摘要。
- 采样频率。
- metrics summary。
- 运动参数入口。

验收：

- 修改刷新周期生效并持久化。

### W5.3 Radiance detail

交付：

- 绑定摘要。
- 状态/地址。
- CPU core editor。
- debug panel。
- 寻找/校准/delete。

验收：

- 详情操作和舞台操作保持同步。

### W5.4 Balance detail

交付：

- metric picker。
- debug panel。
- 表盘 JSON/SVG 导入。
- 寻找/校准/delete。

验收：

- 导入后 scale points 和 SVG markup 持久化。

## M6：校准和运动参数

### W6.1 Calibration dialog

交付：

- Radiance target preview。
- Balance target preview。
- slider。
- 上一步/下一步/保存/取消。

验收：

- 通道预览 ACK 正确校验。
- 取消恢复实时输出。

### W6.2 Calibration save

交付：

- 保存 LUT 到固件。
- upsert 本地 LUT。
- apply state。

验收：

- 保存后 debug panel 显示 LUT 后 code。

### W6.3 Motion settings apply

交付：

- Draft editing。
- Radiance/Balance apply。
- ACK tolerance 校验。
- 成功提示。

验收：

- 固件返回参数和 UI 期望一致。

## M7：维护、托盘、OTA、本地化

### W7.1 Maintenance overlay

交付：

- 服务列表。
- 注册表快照。
- 运动参数。
- I2C debug。
- OTA。
- Manual IP。

验收：

- overlay 打开/关闭不影响输出 loop。

### W7.2 I2C debug

交付：

- 扫描。
- 当前地址 picker。
- 新地址 picker。
- 写入。

验收：

- mock 和硬件均可验证。

### W7.3 OTA

交付：

- 选择 BIN。
- 上传 progress。
- 成功后重连。

验收：

- 真实硬件 OTA 成功。

### W7.4 Tray

交付：

- 通知区图标。
- 左键打开。
- 右键菜单。
- 退出。

验收：

- 关闭主窗口后可从托盘恢复。

### W7.5 Localization

交付：

- zh-Hans/en/system。
- 主窗口和托盘菜单刷新。
- Windows 特有文案。

验收：

- 切语言不需要重启。

## M8：发布候选

### W8.1 Diagnostics

交付：

- 日志文件。
- 简单导出诊断信息。

验收：

- 用户可提供日志定位 discovery/metrics/OTA 问题。

### W8.2 Packaging

交付：

- Release build。
- 安装/卸载方案。
- README Windows 章节。

验收：

- 干净 Windows 11 机器可运行。

### W8.3 Full hardware regression

交付：

- 测试记录。
- 已知问题列表。

验收：

- `TEST_PLAN.md` 发布回归全部通过或有明确 waivers。
