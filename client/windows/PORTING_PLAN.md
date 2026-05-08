# ORB Windows 11 Client Porting Plan

日期：2026-05-08  
范围：将现有 macOS 客户端能力迁移到 Windows 11 客户端；ESP32 固件和硬件协议保持不变。  
当前状态：`client/windows` 为空目录，本文件作为 Windows 端的开发规格和拆工基线。

## 0. 详细开发文档

本计划文档只保留方向和里程碑。具体实现以 `docs/` 下的开发文档为准：

- [docs/README.md](docs/README.md)：文档索引和阅读顺序
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)：Windows 工程架构、模块边界、线程模型
- [docs/PROTOCOL.md](docs/PROTOCOL.md)：ESP32 发现、心跳、HTTP API、DTO 和错误处理
- [docs/STATE_AND_WORKFLOWS.md](docs/STATE_AND_WORKFLOWS.md)：应用状态、持久化结构、核心业务流程
- [docs/WINDOWS_SYSTEM_SERVICES.md](docs/WINDOWS_SYSTEM_SERVICES.md)：Windows 系统指标、mDNS、UDP、托盘和文件系统接口
- [docs/UI_SPEC.md](docs/UI_SPEC.md)：WinUI 首屏舞台、浮层、详情页、校准和维护 UI 规格
- [docs/BACKLOG.md](docs/BACKLOG.md)：可拆 issue 的实施任务和验收标准
- [docs/TEST_PLAN.md](docs/TEST_PLAN.md)：单元、集成、硬件和发布回归测试

## 1. 目标和非目标

### 1.1 目标

- 在 Windows 11 上提供和 Mac 客户端尽量一致的功能、信息架构、视觉层级和交互流程。
- 复用 ESP32 现有 HTTP API、UDP 心跳、mDNS/DNS-SD 服务，不要求固件改动。
- Windows 客户端独立采集本机 CPU、内存、网络、磁盘等指标，并按 Mac 端同一套归一化、LUT、输出帧逻辑下发给 ESP32。
- 支持模块发现、自动连接、注册、删除、寻找、校准、运动参数、I2C 维护、OTA 固件上传。
- 保留本地状态持久化：模块排序、通道绑定、采样周期、运动参数草稿、LUT、本地语言。
- 保留中英文 UI 基础，后续让 Mac/Windows 使用同一份 `locales` 作为源。

### 1.2 非目标

- 不重写 ESP32 固件协议。
- 不改变硬件注册地址规则。
- 不在第一版引入账号、云同步、远程访问或鉴权。
- 不把 Wi-Fi 配网页面迁进客户端第一版；当前固件已有 AP captive portal，Windows 版可先和 Mac 一样假设设备已入网。
- 不强求逐像素复刻 SwiftUI；重点是功能和用户心智一致，Windows 端使用原生 Fluent/WinUI 表达。

## 2. 已读源码地图

### 2.1 Mac 客户端

- 入口和窗口：`client/macos/ORB/ORB/ORBApp.swift`、`ContentView.swift`
- 状态机：`ViewModels/AppModel.swift`
- 协议访问：`Services/ORBSession.swift`
- 发现：`Services/DeviceDiscoveryService.swift`
- UDP 心跳：`Services/HeartbeatListenerService.swift`
- 系统指标采样：`Services/SystemMetricsService.swift`
- 本地存储：`Persistence/AppStore.swift`
- 数据模型：`Models/*.swift`
- LUT：`Calibration/LUTMapper.swift`
- 菜单栏：`AppKitBridge/StatusItemController.swift`
- UI 详情页：`Views/DetailViews.swift`
- 产品图资源：`resources/origin.png`、`radiance.png`、`balance.png`、`resources/orb_icon_set/*`

### 2.2 ESP32 固件

- HTTP API：`firmware/ORB_ESP32C3/src/ApiServer.cpp`
- mDNS 广播：`BonjourService.cpp`
- UDP 心跳：`HeartbeatService.cpp`
- Wi-Fi 配网：`WiFiProvisioning.cpp`
- I2C 模块扫描：`ModuleBus.cpp`
- 地址和模型规则：`Models.h`、`Config.h`
- 平滑和抖动：`SmoothingEngine.*`
- LUT 持久化：`CalibrationStore.*`

### 2.3 Windows 目录

- `client/windows` 当前为空；建议从新工程开始，但把本文件作为第一份架构文档提交。

## 3. Mac 客户端功能清单

### 3.1 连接和在线状态

Mac 当前流程：

1. 首次打开先展示本地网络授权引导。
2. 启动系统指标采样。
3. 启动 UDP 心跳监听，优先绑定 `43981`，失败则使用动态端口。
4. 启动 Bonjour 浏览 `_orb._tcp.local.`。
5. 发现服务后自动解析并 `GET /api/v1/state`。
6. 如果收到 UDP 心跳，按 `device_name` 或 `mac` 关联当前设备。
7. 如果动态 UDP 端口被使用，通过 `POST /api/v1/heartbeat/config` 告诉 ESP32 后续投递端口。
8. 心跳不新鲜时，回退 HTTP `GET /api/v1/ping` / `state` 探活。

Windows 需要保持同一套在线判断：

- `online`：最近一次心跳或 HTTP 通信仍在 grace window 内。
- `offline`：已知设备存在，但超过 grace window。
- `not_found`：未发现任何设备。

### 3.2 系统指标采样

Mac 采样字段：

- 总 CPU 使用率。
- 每个逻辑核心使用率。
- CPU 核心拓扑：性能核心 / 能效核心 / 未分类。
- 内存已用和总量。
- 网络下载 / 上传字节每秒。
- 磁盘读取 / 写入字节每秒。
- GPU 使用率，目前只是模型字段，主 UI 还没有作为稳定绑定入口。

默认采样/下发周期为 `0.5s`，允许 `0.25s ... 5.0s`。

### 3.3 指标到输出帧

Mac 端输出链路：

1. 采样得到 `SystemMetricsSnapshot`。
2. 按每个模块的 `ChannelBinding` 选择指标。
3. 指标归一化到 `0...1`。
4. 应用通道 LUT 映射为 `0...4095` DAC code。
5. 聚合为 `OutputFrame(frameID, channels)`。
6. `POST /api/v1/frame`，表单字段：
   - `frame_id`
   - `channels`，格式 `moduleId,channelIndex,targetCode;...`

输出暂停条件：

- 主控离线。
- 正在校准。
- 正在寻找通道。
- 正在启动校准。
- 存在未知 I2C 设备待处理。

### 3.4 模块和指标绑定

模块类型：

- `unknown = 0`
- `radiance = 1`：曜，双通道 6E2，主要绑定 CPU 核心组平均 / 内存占用。
- `balance = 2`：衡，双通道指针表，主要绑定网络上传、网络下载、磁盘读取、磁盘写入。

本地模块设置：

- `ModuleSetting(moduleID, moduleType, channelBindings)`
- 每个通道一个 `ChannelBinding(channelIndex, MetricBinding)`
- `MetricBinding` 包含指标类型、CPU 核心列表、是否用户指定、非线性刻度点、表盘 SVG 路径/内容。

### 3.5 UI 结构

Mac 首屏是一个产品图舞台：

- 中间展示源模块和已注册的曜/衡模块实物图。
- 顶右角是连接状态胶囊和手动重连按钮。
- 点击源模块显示源设置浮层。
- 点击曜/衡模块的通道区域显示指标候选面板和寻找/校准按钮。
- 拖拽模块可改变顺序并持久化。
- 发现未知设备时右上浮层提示注册。
- 开发者设置覆盖层包括服务列表、注册表快照、运动参数、I2C 调试、OTA。
- 校准使用模态 sheet。

Windows UI 应复刻这些用户心智：

- 仍以产品图舞台作为第一屏，而不是设置列表或向导。
- 操作入口尽量保持“点设备/点通道”的直接性。
- Windows 可使用 Fluent 材质、CommandBar、TeachingTip/Dialog，但信息结构不要改。

### 3.6 注册和维护

地址规则：

- 模块 ID `1...7` 对应 I2C `0x61...0x67`。
- 模块 ID `8` 在 UI 中显示为 ID `0`，对应保留地址 `0x60`。
- 新模块默认地址 `0x60`。
- 前 7 个槽位未满时，不允许直接占用 ID 8。
- 前 7 个槽位已满后，第 8 个模块保留 `0x60`。
- 发现已经改过地址但不属于当前注册表的模块时，需要先 reset 回 `0x60` 再注册。

维护能力：

- 刷新状态作为 I2C 扫描。
- 手动写 MCP4728 I2C 地址。
- 删除模块时清本地绑定/LUT，并调用固件删除。
- OTA 上传 `.bin`。

## 4. ESP32 协议规格

### 4.1 发现和心跳

mDNS/DNS-SD：

- 服务类型：`_orb._tcp.local.`
- 实例名：`ORB-xxxx`
- 端口：`80`
- TXT：
  - `device`
  - `fw`

UDP 心跳：

- 默认端口：`43981`
- 周期：`1500ms`
- 投递方式：局域网广播。
- 客户端如果无法监听默认端口，可监听动态端口，并通过 `/api/v1/heartbeat/config` 配置 ESP32。

心跳 JSON 字段：

- `type = "heartbeat"`
- `protocol_version = 1`
- `device_name`
- `firmware_version`
- `ip`
- `mac`
- `port`
- `sequence`
- `state_revision`
- `heartbeat_interval_ms`
- `default_port`
- `target_port`
- `configured_port`
- `delivery`
- `uptime_ms`
- `registered_count`
- `present_count`

### 4.2 HTTP API

所有 mutating API 当前都是 `application/x-www-form-urlencoded`，OTA 是 `multipart/form-data`。

| 方法 | 路径 | 用途 | 请求字段 | 成功响应 |
| --- | --- | --- | --- | --- |
| GET | `/api/v1/ping` | 探活和轻量状态 | 无 | 设备名、IP、MAC、心跳配置、`state_revision` |
| POST | `/api/v1/heartbeat/config` | 配置 UDP 心跳目标端口 | `udp_port` | 心跳配置 ACK |
| GET | `/api/v1/state` | 完整状态 | 无 | `ORBDeviceState` |
| POST | `/api/v1/smoothing` | 下发运动参数 | `module_type`, `settle_time_ms`, `a_max`, `v_max`, `jitter_frequency_hz`, `jitter_amplitude`, `jitter_dispersion` | 完整状态 |
| POST | `/api/v1/frame` | 批量输出帧 | `frame_id`, `channels` | `ok`, `frame_id`, `applied` |
| POST | `/api/v1/outputs` | 单通道输出，兼容/调试用 | `module_id`, `channel_index`, `target_code` | `ok` |
| POST | `/api/v1/preview` | 寻找/校准预览 | `mode`, `module_id`, `channel_index`, `target_code` | 预览 ACK |
| POST | `/api/v1/modules/register` | 注册模块 | `module_type`, `id`, `address` | 完整状态 |
| POST | `/api/v1/modules/delete` | 删除模块 | `id` | 完整状态 |
| POST | `/api/v1/modules/reset` | 未知旧地址重置为 `0x60` | `address` | 完整状态 |
| POST | `/api/v1/i2c/write_address` | 手动 I2C 改址 | `old_address`, `new_address` | 完整状态 |
| POST | `/api/v1/calibration/save` | 保存 LUT | `module_id`, `channel_index`, `points`, `updated_at_epoch` | 完整状态 |
| POST | `/api/v1/firmware/upload` | OTA 上传 | multipart `firmware` | `ok`, `rebooting`, `message`, `firmware_version` |

`ORBDeviceState` 字段：

- `device_name`
- `firmware_version`
- `ip`
- `mac`
- `state_revision`
- `heartbeat_interval_ms`
- `heartbeat_default_port`
- `heartbeat_target_port`
- `heartbeat_configured_port`
- `heartbeat_delivery`
- `wifi_mode`
- `unknown_candidate_present`
- `detected_i2c_addresses`
- `unknown_i2c_addresses`
- `calibration_luts`
- `smoothing`
- `modules`

## 5. Windows 技术选型建议

### 5.1 推荐基线

- UI：WinUI 3 + Windows App SDK。
- 语言：C#。
- 运行时：.NET 10 LTS。
- Windows App SDK：使用当前稳定版 1.8.x；暂不使用 2.0 preview。
- 目标系统：Windows 11 x64 / arm64。代码不主动依赖 Windows 10，但 WinUI/Win32 API 多数可兼容 Windows 10。
- 打包：先用 unpackaged dev build；进入发布阶段再定 MSIX 或 unpackaged + installer。

选择理由：

- WinUI 3 是 Windows App SDK 中的现代桌面 UI 框架，贴近 Windows 11 原生体验。
- Windows App SDK 可用于桌面应用，并通过 NuGet 发布，不和 OS SDK 强绑定。
- .NET 10 是当前 LTS，支持期到 2028-11。

### 5.2 备选方案

- WPF：开发快、拖拽和系统托盘成熟，但视觉和 Windows 11 原生感弱。若 WinUI 的舞台/拖拽成本过高，可作为降级。
- C++/WinUI：原生 API 调用更直接，但开发效率低；本项目逻辑以状态、网络、UI 为主，C# 更合适。
- MAUI：跨平台不是目标，且 Mac 客户端已有 SwiftUI；不建议。

## 6. Windows 模块架构

建议工程结构：

```text
client/windows/
  ORB.Windows.sln
  src/
    ORB.Windows/
      App.xaml
      MainWindow.xaml
      Assets/
      Views/
      Controls/
      ViewModels/
      Services/
      Models/
      Persistence/
      Calibration/
      Native/
      Localization/
  tests/
    ORB.Windows.Tests/
```

### 6.1 Models

从 Swift 模型逐一迁移：

- `ModuleType`
- `MetricSourceKind`
- `MetricBinding`
- `MetricScalePoint`
- `ChannelBinding`
- `RegistryEntry`
- `SmoothingConfig`
- `DeviceSmoothingProfiles`
- `ORBDeviceState`
- `ORBHeartbeat`
- `LayoutSlot`
- `ModuleSetting`
- `LUTPoint`
- `CalibrationLUT`
- `CalibrationDraft`
- `OutputPreviewMode`
- `OutputChannelPayload`
- `OutputFrame`
- `DiscoveredService`
- `ORBEndpoint`
- `CPUCoreKind`
- `CPUCoreDescriptor`
- `CPUCoreLoad`
- `SystemMetricsSnapshot`
- `ConnectionStatus`
- `AppLanguage`

JSON 策略：

- 使用 `System.Text.Json`。
- API DTO 使用 snake_case 属性映射，避免因 C# 命名和固件字段不一致出错。
- 本地存储可继续使用 camelCase 或跟 Mac 一致；为未来跨平台迁移，建议使用和 Mac `StoredAppState` 兼容的字段名。

### 6.2 Services

| 服务 | Windows 职责 | Mac 对照 |
| --- | --- | --- |
| `OrbHttpClient` | HTTP API、表单编码、OTA multipart、错误映射 | `ORBSession` |
| `DeviceDiscoveryService` | DNS-SD/mDNS 浏览 `_orb._tcp.local.`、解析 host/port、维护发现列表 | `DeviceDiscoveryService` |
| `HeartbeatListenerService` | UDP 43981 监听、动态端口回退、解析心跳 JSON | `HeartbeatListenerService` |
| `SystemMetricsService` | Windows 本机指标采样 | `SystemMetricsService` |
| `AppStateStore` | `%AppData%/ORB/app_state.json` 读写 | `AppStore` |
| `TrayService` | 通知区图标、打开主窗、开发者设置、退出 | `StatusItemController` |
| `FileDialogService` | 选择 BIN/JSON/SVG | `NSOpenPanel` / SwiftUI fileImporter |
| `LocalizationService` | zh-Hans/en/system 语言切换 | `AppLanguage` + `Localizable.strings` |

### 6.3 ViewModels

建议不要把 Mac 的 `AppModel` 原样搬成一个巨型类。可以保留一个根 `AppViewModel`，但拆出内聚子状态：

- `ConnectionCoordinator`
- `MetricsLoop`
- `OutputFrameScheduler`
- `ModuleRegistryWorkflow`
- `CalibrationWorkflow`
- `MotionSettingsWorkflow`
- `MaintenanceWorkflow`

根 ViewModel 汇总可绑定状态，避免 UI 到处直接调用服务。

## 7. Windows 差异点和实现方案

### 7.1 系统指标采样

目标输出必须和 Mac `SystemMetricsSnapshot` 对齐。

| 指标 | Mac 来源 | Windows 建议 | 风险 |
| --- | --- | --- | --- |
| 总 CPU | Mach `host_processor_info` delta | `GetSystemTimes` delta | 只能总量，不能分核心 |
| 每核心 CPU | Mach per-core ticks | 优先技术 spike：`NtQuerySystemInformation(SystemProcessorPerformanceInformation)` 或 PDH per core；总 CPU fallback 用 `GetSystemTimes` | per-core API 需要验证精度、权限、采样频率 |
| P/E 核心分类 | `sysctl hw.perflevel*` | `GetSystemCpuSetInformation` + `EfficiencyClass` | 非混合架构可能全 unknown |
| 内存 | `host_statistics64` + physicalMemory | `GlobalMemoryStatusEx` | 简单稳定 |
| 网络吞吐 | `getifaddrs` 的 `ifi_ibytes/obytes` delta | `GetIfTable2` 的接口累计字节 delta，排除 loopback/down/tunnel | 多网卡/虚拟网卡过滤要调 |
| 磁盘吞吐 | IOKit `IOBlockStorageDriver` 统计 delta | 首版用 PDH English counters：`PhysicalDisk(_Total)\Disk Read Bytes/sec` / `Disk Write Bytes/sec`；并做 direct IOCTL spike | PDH 高频和本地化需要注意 |
| GPU | IOKit IOAccelerator | 首版隐藏或保留 placeholder；后续用 PDH GPU Engine/DXGI/NVML spike | 供应商差异大 |

采样策略：

- UI 仍允许 `0.25s ... 5s`。
- 如果某项 Windows API 不适合高频，服务内部可用独立节流，上一笔数据复用到更高频输出帧。
- 网络和磁盘用累计计数时要处理计数回绕、接口变化、睡眠恢复。
- CPU core descriptors 需要稳定排序，避免每次启动核心 token 顺序变化。

### 7.2 mDNS / DNS-SD

用户直觉是“Windows 没有原生 Bonjour，需要嵌入 mDNS”。需要稍微校正：

- Windows 10+ 桌面应用有 Win32 DNS-SD API：`DnsServiceBrowse`、`DnsServiceResolve`。
- WinRT `DnssdServiceWatcher` 文档标注不推荐继续依赖，且建议使用其他枚举方式。
- 因此建议第一阶段先做 Win32 DNS-SD spike；如果在 Windows 11 + 常见路由器 + 防火墙环境下发现不稳定，再嵌入 mDNS 客户端库作为 fallback。

建议实现：

1. 用 Win32 `DnsServiceBrowse` 浏览 `_orb._tcp.local.`。
2. 用 `DnsServiceResolve` 获取 host、port、TXT、IP。
3. 发现列表按实例名去重。
4. 如果 3 秒内 DNS-SD 无结果，但收到 UDP 心跳，直接通过心跳 IP 连接。
5. 提供“手动输入 IP”隐藏入口或开发者入口，作为现场救援方案。

防火墙注意：

- UDP 心跳监听可能触发 Windows Defender Firewall 入站提示。
- 第一版应准备明确的 UI 文案：需要允许专用网络上的 UDP 入站，HTTP 主动请求通常不需要入站授权。
- 如果默认端口 43981 不可用，仍要绑定动态端口并调用 `/api/v1/heartbeat/config`。

### 7.3 UI 重构

WinUI 版 UI 建议分三层：

1. **舞台层**：模块产品图、热点区域、拖拽排序、实时模拟输出。
2. **浮层层**：连接徽章、未知设备注册、指标候选面板、通道动作条。
3. **详情/维护层**：源设置、模块详情、开发者设置、校准 Dialog。

重点复刻：

- 产品图资源沿用 Mac `resources/*.png`。
- 源模块和扩展模块横向排列。
- 曜模块两个 tube 通道有可点击/可 drop 的热点。
- 衡模块两个 gauge 通道有可点击/可 drop 的热点。
- 拖拽模块改变横向顺序。
- 通道绑定后，舞台上有实时视觉反馈。
- 校准时其他输出暂停，只有当前通道响应滑块。

Windows 具体控件建议：

- `MainWindow`：根容器。
- `Canvas`：舞台绝对定位和热点。
- `Image`：产品图。
- `Popup` / `TeachingTip` / 自定义 overlay：候选面板和注册面板。
- `ContentDialog`：校准流程、重要确认。
- `CommandBar` 或轻量按钮条：通道动作。
- `NavigationView` 不作为主入口，避免变成传统设置型应用。

### 7.4 系统托盘

Mac 有菜单栏状态图标。Windows 对应通知区图标：

- 左键：显示主窗口。
- 右键菜单：
  - 连接状态
  - 打开主窗口
  - 开发者设置
  - 退出
- 图标状态可暂不动态换图，第一版用 ORB icon + tooltip 文字。

WinUI 没有完整托盘抽象，建议用 Win32 `Shell_NotifyIcon` 封装。

### 7.5 文件导入

需要支持：

- OTA `.bin`。
- 衡模块仪表盘 JSON。
- 同名/同目录 SVG 表盘。

Windows 差异：

- 无 security-scoped resource。
- 需要把导入的 SVG 内容读入本地状态，避免路径移动后丢失。
- Calibration preview 中显示 SVG 可用 WebView2 或 SVG 渲染库；首版推荐 WebView2，和 Mac 的 `WKWebView` 角色一致。

### 7.6 本地存储

Mac 路径：Application Support/ORB/app_state.json。  
Windows 建议路径：

- `%APPDATA%\ORB\app_state.json`

字段保持：

- `layout`
- `moduleSettings`
- `refreshInterval`
- `motionDurationFactor`
- `calibrationLUTs`
- `appLanguage`

需要做迁移：

- 兼容早期 legacy `binding` 单绑定字段。
- 兼容 legacy shared LUT。
- Windows 版第一次运行不应覆盖 Mac 状态，两个平台本地独立。

### 7.7 本地化

当前 Mac 有 `en.lproj/Localizable.strings`、`zh-Hans.lproj/Localizable.strings`，仓库根还有 `locales/en.json`、`locales/zh-Hans.json`。

建议：

- 第一版 Windows 直接用 JSON resource 或 `.resw`。
- 后续把根 `locales/*.json` 定为唯一源，再生成 Mac `.strings` 和 Windows `.resw`。
- UI 文案要先补齐 Windows 特有内容：防火墙、专用网络、通知区、手动 IP。

## 8. 开发里程碑

### M0：技术 spike 和工程基线

交付：

- WinUI 3 空工程。
- 能打开主窗口、加载 ORB icon 和三张产品图。
- 验证 .NET 10 + Windows App SDK 1.8 开发环境。
- DNS-SD spike：确认 `DnsServiceBrowse/Resolve` 能否发现 ESP32 `_orb._tcp.local.`。
- UDP spike：默认 43981 监听、动态端口 fallback、防火墙表现记录。
- Metrics spike：CPU/memory/network/disk 四项在 Windows 11 上可取值。

验收：

- 不接硬件也能打开 UI。
- 接硬件时至少能通过 DNS-SD 或 UDP 心跳拿到设备 IP。
- 输出一份 spike 结论：DNS-SD 是否需要嵌入 fallback。

### M1：协议和模型层

交付：

- C# 数据模型。
- `OrbHttpClient`。
- `LUTMapper`。
- `AppStateStore`。
- 单元测试覆盖：
  - module ID/address 映射。
  - snake_case JSON decode。
  - LUT 插值。
  - rate normalization。
  - frame channels 格式。

验收：

- 可用 mock HTTP server 完整 decode `/state`。
- 可发送 `/frame` 并验证 form body。

### M2：连接协调层

交付：

- `DeviceDiscoveryService`。
- `HeartbeatListenerService`。
- `ConnectionCoordinator`。
- 心跳端口同步 `/heartbeat/config`。
- HTTP ping/state fallback。
- 手动重连。

验收：

- 设备开机后自动连接。
- 拔掉/关掉设备后状态变为 offline。
- 设备重新上线后恢复 online。
- 默认 UDP 端口被占用时，动态端口能收到后续心跳。

### M3：系统指标和实时下发

交付：

- `SystemMetricsService`。
- `OutputFrameScheduler`。
- `SystemMetricsSnapshot` UI debug display。
- 采样周期设置和持久化。
- 绑定 CPU/内存/网络/磁盘并下发。

验收：

- CPU/内存驱动曜模块变化。
- 网络/磁盘驱动衡模块变化。
- 校准/寻找/未知设备状态下输出暂停。
- 采样周期改变后实时生效。

### M4：首屏舞台 UI

交付：

- 源/曜/衡产品图舞台。
- 模块横向布局。
- 在线/离线 dimmed 状态。
- 顶右连接 badge。
- 点击源模块打开源设置。
- 点击通道打开候选指标面板。
- 拖拽模块排序。

验收：

- 不打开详情页即可完成常用绑定。
- 模块排序重启后保持。
- 舞台实时模拟输出和硬件输出大体一致。

### M5：模块详情和注册流程

交付：

- 未知设备 overlay。
- 注册曜/衡模块。
- reset 旧地址设备。
- 删除设备。
- Radiance 详情：CPU 核心选择、内存绑定、debug panel、寻找、校准入口。
- Balance 详情：网络/磁盘绑定、debug panel、寻找、校准入口、表盘导入。

验收：

- 新模块从 `0x60` 注册到目标 ID。
- 旧地址未知模块可 reset 后注册。
- 删除模块后本地绑定和 LUT 清理。
- 表盘 JSON + SVG 导入后参与非线性映射。

### M6：校准和运动参数

交付：

- 校准 Dialog。
- Radiance 校准顺序：`0%, 50%, 25%, 100%, 75%`。
- Balance 校准顺序：导入刻度 percent；无刻度时 `0...100%` 每 10%。
- 预览请求 ACK 校验和重试。
- 保存 LUT 到固件和本地。
- 源设置/开发者设置中的运动参数：到位时间、响应力度、最大速度、抖动频率、抖动幅度、抖动随机度。

验收：

- 校准滑块只影响当前通道。
- 取消校准后恢复实时输出。
- 保存后重新进入显示自定义 LUT。
- 运动参数应用后固件返回值和期望值一致。

### M7：维护、托盘、OTA、本地化

交付：

- 开发者设置 overlay。
- 已发现服务列表。
- 注册表快照。
- I2C 扫描和手动改址。
- OTA `.bin` 上传。
- Windows 通知区图标和菜单。
- 中英文切换。
- Windows 防火墙/网络访问错误文案。

验收：

- OTA 成功后设备重启，客户端自动重连。
- 右键托盘菜单可打开开发者设置和退出。
- 切换语言后主窗口和托盘菜单刷新。

### M8：打包、测试和发布候选

交付：

- Release build。
- x64 和 arm64 测试。
- 崩溃日志/诊断日志。
- README Windows 安装和防火墙说明。
- 发布包。

验收：

- 干净 Windows 11 机器可安装/运行。
- 无 Visual Studio 环境也能运行。
- 完整硬件回归通过。

## 9. 测试计划

### 9.1 单元测试

- `LUTMapper.map`：默认映射、插值、端点补齐、clamp。
- `MetricNormalizer`：CPU、内存、network fallback ranges、disk fallback ranges、自定义 scale points。
- `AddressMapper`：ID 1...8 和 I2C 地址互转。
- `FrameEncoder`：channels 格式、空帧不发送。
- `StateStore`：默认值、legacy migration、date/epoch decode。
- `HeartbeatParser`：snake_case 字段、旧固件缺字段 fallback。

### 9.2 集成测试

- Mock ESP32 HTTP server。
- Mock UDP heartbeat broadcaster。
- DNS-SD 可用时做本地服务模拟；不可用则把 DNS-SD 放到手工硬件测试。
- OTA multipart body 验证。
- 心跳动态端口配置验证。

### 9.3 硬件回归

每个 RC 至少跑：

1. 首次发现和自动连接。
2. 手动重连。
3. 注册一个曜。
4. 注册一个衡。
5. CPU/内存/网络/磁盘绑定和实时输出。
6. 曜通道寻找和校准。
7. 衡表盘导入和校准。
8. 删除模块。
9. I2C 扫描。
10. OTA 上传并重连。
11. 默认 UDP 端口冲突场景。
12. Windows Defender Firewall 专用网络允许/拒绝场景。

## 10. 风险和对策

| 风险 | 影响 | 对策 |
| --- | --- | --- |
| Windows DNS-SD 在目标环境不稳定 | 设备发现失败 | M0 spike；实现 UDP 心跳直连；保留手动 IP；必要时嵌入 mDNS fallback |
| Windows 防火墙拦截 UDP 心跳 | 在线状态延迟或无法自动刷新 | HTTP ping/state fallback；清晰文案；动态端口同步 |
| per-core CPU 采样不稳定 | 曜模块 CPU 核心绑定体验差 | 先保总 CPU/核心组 fallback；M0 验证 per-core API |
| PDH 磁盘计数本地化/频率问题 | 衡磁盘读写不准 | 使用 `PdhAddEnglishCounterW`；必要时改 direct IOCTL 或降低内部采样频率 |
| WinUI 舞台拖拽和 overlay 复杂 | UI 开发周期拉长 | 先做功能可用舞台，再逐步精修动画和材质 |
| SVG 表盘渲染差异 | 衡校准预览不一致 | 首版 WebView2；后续考虑 SVG rasterization cache |
| OTA 过程中断 | 设备需重新刷写 | 上传前强提示；超时 180s；失败明确提示不要断电 |

## 11. 待确认问题

1. Windows 版第一版是否只支持 Windows 11，还是也声明 Windows 10 可运行？
2. 是否接受 WinUI 3 + .NET 10 LTS 作为正式技术栈？
3. 是否允许把 `client/macos/ORB/ORB/resources` 里的 PNG 和 icon 复制到 Windows 工程？
4. DNS-SD 如果 Win32 API 可用，是否仍强制嵌入第三方 mDNS？建议先 spike 再决定。
5. Windows 第一版是否需要“手动输入 IP”入口？建议开发者设置中加入。
6. GPU 指标是否进入 Windows v1？建议先不进入可选 token。
7. Windows 发布形式偏好：MSIX、传统 installer，还是 zip portable？

## 12. Definition of Done

Windows v1 完成标准：

- 连接发现、心跳、HTTP fallback、状态同步完整。
- CPU、内存、网络、磁盘四类指标可驱动硬件。
- 曜/衡双通道绑定、寻找、校准、LUT 保存完整。
- 新设备注册、旧地址 reset、删除设备完整。
- 运动参数、I2C 调试、OTA 完整。
- 本地状态持久化和中英文切换可用。
- 托盘菜单可用。
- Windows 11 x64 硬件回归通过。
- 不需要 ESP32 固件改动。

## 13. 官方资料

- WinUI 3：<https://learn.microsoft.com/en-us/windows/apps/winui/>
- Windows App SDK：<https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/>
- Windows App SDK downloads：<https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads>
- .NET support policy：<https://dotnet.microsoft.com/en-us/platform/support/policy>
- Windows SDK：<https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/>
- Win32 DNS-SD `DnsServiceBrowse`：<https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse>
- Win32 DNS-SD `DnsServiceResolve`：<https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceresolve>
- WinRT DNS-SD namespace：<https://learn.microsoft.com/en-us/uwp/api/windows.networking.servicediscovery.dnssd>
- `GetSystemTimes`：<https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemtimes>
- `GetSystemCpuSetInformation`：<https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-getsystemcpusetinformation>
- `GlobalMemoryStatusEx`：<https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/nf-sysinfoapi-globalmemorystatusex>
- `GetIfTable2`：<https://learn.microsoft.com/en-us/windows/win32/api/netioapi/nf-netioapi-getiftable2>
- PDH `PdhAddEnglishCounterW`：<https://learn.microsoft.com/en-us/windows/win32/api/pdh/nf-pdh-pdhaddenglishcounterw>
- Windows Performance Counters：<https://learn.microsoft.com/en-us/windows/win32/perfctrs/performance-counters-portal>
