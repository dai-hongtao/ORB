# Windows System Services

## 1. System Metrics Service

目标输出：

```text
SystemMetricsSnapshot
  SampledAt
  TotalCPUUsagePercent
  CPUCoreLoads[]
  MemoryUsedBytes
  MemoryTotalBytes
  NetworkReceiveBytesPerSecond
  NetworkSendBytesPerSecond
  DiskReadBytesPerSecond
  DiskWriteBytesPerSecond
  GPUUsagePercent?
```

所有采样失败都应该降级为 `0` 或 `null`，并记录 warn，不应导致输出 loop 崩溃。

### 1.1 CPU total

首选：

- Win32 `GetSystemTimes`。
- 记录 idle/kernel/user ticks。
- delta 公式：

```text
busy = (kernelDelta + userDelta) - idleDelta
total = kernelDelta + userDelta
usage = busy / total * 100
```

注意：

- `kernel` 包含 idle，所以要减去 idle。
- 第一次采样返回 `0`，等待下一次 delta。

### 1.2 CPU per core

需要 M0 spike 决定最终实现。推荐优先级：

1. PDH English counters：`\\Processor Information(*)\\% Processor Utility` 或 `\\Processor Information(*)\\% Processor Time`。
2. 如果 PDH instance 排序和 core ID 映射不稳定，再评估 native processor performance information。
3. 如果 per-core 失败，返回空数组，UI fallback 到总 CPU。

要求：

- core index 稳定从 `0` 开始。
- 不把 `_Total` 作为一个 core。
- 多 processor group 机器要排序稳定，例如按 group, number。
- 采样周期小于 PDH 可靠周期时，可缓存上一笔 per-core 数据。

### 1.3 CPU topology

首选：

- `GetSystemCpuSetInformation`。
- 使用 `EfficiencyClass` 区分：
  - 低 efficiency class：performance。
  - 高 efficiency class：efficiency。

由于厂商和 Windows 版本差异，分类规则必须能降级：

- 如果所有 core `EfficiencyClass` 相同，全部标为 `unknown` 或全部 performance。
- 如果 API 失败，按逻辑核心数生成 `unknown`。

UI token：

- 如果存在 performance core，显示“大核平均”。
- 如果存在 efficiency core，显示“小核平均”。
- 如果都 unknown，只显示每个 CPU 核心和内存。

### 1.4 Memory

Win32 API：

- `GlobalMemoryStatusEx`

字段：

```text
MemoryTotalBytes = ullTotalPhys
MemoryUsedBytes = ullTotalPhys - ullAvailPhys
MemoryUsagePercent = MemoryUsedBytes / MemoryTotalBytes * 100
```

### 1.5 Network

Win32 API：

- `GetIfTable2`

字段：

- `MIB_IF_ROW2.InOctets`
- `MIB_IF_ROW2.OutOctets`

过滤建议：

- `OperStatus == IfOperStatusUp`
- 排除 loopback。
- 排除 tunnel。
- 优先保留 hardware interface。
- 虚拟网卡第一版可以计入总量；如用户反馈偏高，再加“忽略虚拟网卡”设置。

delta：

```text
receiveBps = max(current.InOctets - previous.InOctets, 0) / elapsedSeconds
sendBps = max(current.OutOctets - previous.OutOctets, 0) / elapsedSeconds
```

接口变化：

- 按 interface LUID 或 index 聚合。
- 如果接口集合变化，仍对总量做 delta；若 current < previous，返回 0 并重置 previous。

### 1.6 Disk

第一版建议：

- PDH English counters。

Counters：

```text
\\PhysicalDisk(_Total)\\Disk Read Bytes/sec
\\PhysicalDisk(_Total)\\Disk Write Bytes/sec
```

原因：

- 与 Mac IOKit 总磁盘吞吐心智一致。
- 可直接获得 bytes/sec，不需要自己处理每块磁盘累计计数。

注意：

- 使用 `PdhAddEnglishCounterW`，不要用本地化 counter name。
- 初始化 PDH query 后第一次采样可能为 0，下一次才可信。
- 如果 PDH 不可用，返回 0 并记录 warn。

### 1.7 GPU

第一版：

- 保留字段 `GPUUsagePercent = null`。
- 不在 UI 中暴露 GPU token。

后续候选：

- PDH GPU Engine counters。
- DXGI。
- 厂商 SDK。

## 2. Device Discovery Service

### 2.1 首选：Win32 DNS-SD

API：

- `DnsServiceBrowse`
- `DnsServiceResolve`

浏览目标：

```text
_orb._tcp.local.
```

输出：

```text
DiscoveredService
  Name
  HostName
  Port
  Txt
```

实现要求：

- Browse callback 不直接改 UI state，先进入 service 内部集合，再向 ViewModel 发布 snapshot。
- Resolve 可按需触发，也可发现后自动 resolve。
- 服务消失时移除缓存 endpoint。
- 解析失败不清空其他服务。

### 2.2 Fallback

必须存在：

1. UDP heartbeat direct connect：只要收到心跳就能连接。
2. Manual IP：开发者设置中输入 IP/port。
3. 嵌入式 mDNS fallback：M0 spike 后决定是否实现。

Manual IP 规则：

- 默认 port `80`。
- 输入后先 `GET /api/v1/ping`，成功再加载 state。
- 成功连接后可把 endpoint 记入本次运行内存，不必持久化到本地状态。

## 3. UDP Heartbeat Listener

绑定策略：

1. 尝试 `0.0.0.0:43981`。
2. 设置端口复用，避免重启时短时间占用问题。
3. 如果失败，绑定 `0.0.0.0:0`，由系统分配动态端口。
4. 向 UI 发布：
   - `PreferredUdp`
   - `DynamicUdp`
   - `Unavailable`

状态字段：

```text
HeartbeatListenerStatus
  Mode
  LocalPort
  Message
```

收到数据：

- UTF-8 decode。
- JSON decode 为 `OrbHeartbeat`。
- 设置 `ReceivedAt = DateTimeOffset.Now`。
- 发布到 `ConnectionCoordinator`。

异常：

- JSON decode 失败：记录 warn，继续监听。
- socket receive 失败：记录 warn，重启 listener 或转 unavailable。
- 防火墙导致无数据：通常没有异常，只能通过长时间收不到心跳 + HTTP probe 成功推断。

## 4. Heartbeat Routing

当 `HeartbeatListenerStatus.IsAvailable` 且 `DeviceState` 表明固件支持 heartbeat routing：

```text
if DeviceState.HeartbeatTargetPort != LocalPort || DeviceState.HeartbeatConfiguredPort != true:
  POST /api/v1/heartbeat/config udp_port=LocalPort
```

失败时：

- 不影响 HTTP 控制。
- UI 展示非阻塞问题：`UDP 心跳端口同步失败...`
- Watchdog 继续用 HTTP probe。

## 5. Windows Defender Firewall UX

可能触发时机：

- UDP listener 开始监听入站。
- DNS-SD/mDNS multicast。

UI 文案建议：

```text
Windows 可能正在拦截 ORB 的局域网心跳。请在 Windows 安全中心或防火墙弹窗中允许 ORB 访问“专用网络”。如果你暂时不允许，ORB 仍会尝试通过 HTTP 保持连接，但状态刷新可能变慢。
```

不要引导用户允许公共网络，默认建议专用网络。

## 6. Tray Service

WinUI 3 没有内建通知区图标，封装 Win32：

- `Shell_NotifyIcon`
- hidden window message callback
- context menu

菜单：

```text
连接状态：已连接/未连接/离线
打开主窗口
开发者设置
退出
```

行为：

- 左键单击：显示主窗口。
- 右键：context menu。
- 双击：同左键。
- 退出：取消所有 background loops，然后关闭 app。

## 7. File Dialog Service

需要三类选择：

- OTA `.bin`。
- Gauge JSON。
- Gauge SVG。

建议：

- 用 Windows App SDK / Win32 file picker，并封装为 `IFileDialogService`。
- 返回 path，不在 ViewModel 里直接 new dialog。
- 读取 SVG 后保存 markup 到 `MetricBinding.DialSVGMarkup`。
- JSON/SVG 导入失败要区分：
  - 文件不可读。
  - JSON 格式不合法。
  - JSON 无有效 tick。
  - SVG 找不到或不可读。

Gauge JSON 解析：

```text
state.majorTicks[]
  valueText
  unitText
  percent
```

单位换算：

```text
B/byte/bytes -> value
K/KB -> value * 1024
M/MB -> value * 1024^2
G/GB -> value * 1024^3
```

SVG 自动查找顺序：

1. 和 JSON 同名 `.svg`。
2. 当前 metric 对应文件：
   - `网速上行.svg`
   - `网速下行.svg`
   - `硬盘读取.svg`
   - `硬盘写入.svg`
3. 同目录唯一 `.svg`。
4. 弹文件选择。

## 8. App Data Paths

Roaming state：

```text
%APPDATA%\ORB\app_state.json
```

Local logs/cache：

```text
%LOCALAPPDATA%\ORB\logs\
%LOCALAPPDATA%\ORB\cache\
```

不要把用户选择的固件文件复制到 app data。

## 9. Native API Spike Checklist

M0 需要实际验证：

- DNS-SD 能否发现 ESP32 的 `_orb._tcp.local.`。
- 默认 UDP 43981 被占用时，动态端口 + `/heartbeat/config` 是否稳定。
- Windows Defender Firewall 首次弹窗文案和触发点。
- PDH per-core counter 的 instance 排序。
- PDH disk counter 在中文 Windows 上是否能通过 English counter 打开。
- `GetIfTable2` 是否把虚拟网卡导致的吞吐计入过高。
- `GetSystemCpuSetInformation` 在 Intel/AMD/ARM 混合架构上的分类表现。
