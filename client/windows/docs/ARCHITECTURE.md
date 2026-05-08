# Architecture

## 1. 技术基线

- UI：WinUI 3。
- Runtime：.NET 10 LTS。
- Platform：Windows 11 desktop。
- Packaging：开发期先 unpackaged；发布期再决定 MSIX 或传统 installer。
- JSON：`System.Text.Json`。
- HTTP：`HttpClient`。
- UDP：`.NET Socket/UdpClient`，必要时下沉到 raw `Socket` 以设置端口复用。
- Native APIs：集中在 `Native/`，不要散落在 ViewModel。

## 2. 推荐目录

```text
client/windows/
  ORB.Windows.sln
  src/
    ORB.Windows/
      App.xaml
      MainWindow.xaml
      Assets/
        origin.png
        radiance.png
        balance.png
        orb_icon_set/
      Models/
      Services/
      ViewModels/
      Views/
      Controls/
      Calibration/
      Persistence/
      Native/
      Localization/
      Diagnostics/
  tests/
    ORB.Windows.Tests/
```

## 3. 层级边界

### 3.1 Views / Controls

职责：

- 只渲染状态和发出用户意图。
- 不直接调用 HTTP、UDP、Win32 API。
- 不直接读写文件。
- 可包含少量纯 UI 几何计算，例如舞台坐标、热点 rect、动画状态。

典型对象：

- `MainWindow`
- `ModuleStageView`
- `ConnectionBadge`
- `MetricCandidatePanel`
- `UnknownDeviceOverlay`
- `MaintenanceOverlay`
- `CalibrationDialog`
- `GaugeSvgView`

### 3.2 ViewModels

职责：

- 暴露 UI 可绑定状态。
- 调度 workflow。
- 统一处理 loading、notice、issue 文案。
- 持有 cancellation token / background loop lifecycle。

建议拆分：

- `AppViewModel`：根状态和 UI 导航。
- `ConnectionViewModel`：发现、心跳、连接状态。
- `ModuleStageViewModel`：舞台排序、热点选择、指标 token。
- `MaintenanceViewModel`：开发者设置、I2C、OTA。
- `CalibrationViewModel`：校准 dialog 状态。

### 3.3 Services

职责：

- 可 mock。
- 不依赖 WinUI 控件。
- 通过事件、channel 或 observable stream 汇报状态。
- 只返回 domain model 或 typed result。

核心服务：

```csharp
public interface IOrbHttpClient
{
    Task<OrbDeviceState> FetchStateAsync(OrbEndpoint endpoint, CancellationToken ct);
    Task<OrbPingResponse> PingAsync(OrbEndpoint endpoint, CancellationToken ct);
    Task<OrbHeartbeatConfigResponse> ConfigureHeartbeatAsync(OrbEndpoint endpoint, int listenerPort, CancellationToken ct);
    Task SendOutputsAsync(OrbEndpoint endpoint, OutputFrame frame, CancellationToken ct);
    Task<OrbPreviewActivationResponse> ActivatePreviewAsync(OrbEndpoint endpoint, OutputPreviewMode mode, int moduleId, int channelIndex, int targetCode, TimeSpan timeout, CancellationToken ct);
    Task<OrbDeviceState> RegisterModuleAsync(OrbEndpoint endpoint, ModuleType type, int id, int address, CancellationToken ct);
    Task<OrbDeviceState> DeleteModuleAsync(OrbEndpoint endpoint, int id, CancellationToken ct);
    Task<OrbDeviceState> ResetUnknownDeviceAsync(OrbEndpoint endpoint, int address, CancellationToken ct);
    Task<OrbDeviceState> WriteI2CAddressAsync(OrbEndpoint endpoint, int oldAddress, int newAddress, CancellationToken ct);
    Task<OrbDeviceState> SaveCalibrationLutAsync(OrbEndpoint endpoint, int moduleId, int channelIndex, IReadOnlyList<LutPoint> points, CancellationToken ct);
    Task<OrbFirmwareUploadResponse> UploadFirmwareAsync(OrbEndpoint endpoint, string filePath, IProgress<double>? progress, CancellationToken ct);
}
```

```csharp
public interface IDeviceDiscoveryService
{
    event EventHandler<IReadOnlyList<DiscoveredService>>? ServicesChanged;
    Task StartAsync(CancellationToken ct);
    Task StopAsync();
    Task<OrbEndpoint> ResolveAsync(string serviceName, CancellationToken ct);
}
```

```csharp
public interface IHeartbeatListenerService
{
    event EventHandler<OrbHeartbeat>? HeartbeatReceived;
    event EventHandler<HeartbeatListenerStatus>? StatusChanged;
    Task StartAsync(CancellationToken ct);
    Task StopAsync();
}
```

```csharp
public interface ISystemMetricsService
{
    Task<SystemMetricsSnapshot> SampleAsync(CancellationToken ct);
}
```

### 3.4 Native

职责：

- P/Invoke declarations。
- Win32 handle lifetime。
- Native error code 转 typed exception。
- API-specific DTO 不上浮到 ViewModel。

目录建议：

```text
Native/
  Win32DnsSd.cs
  Win32IpHelper.cs
  Win32Memory.cs
  Win32Processor.cs
  Win32Pdh.cs
  Win32ShellNotifyIcon.cs
```

## 4. Runtime 线程模型

### 4.1 UI thread

只做：

- 更新 observable properties。
- 响应用户操作。
- 创建/关闭 WinUI dialog。

禁止：

- 同步等待 HTTP/UDP。
- 高速指标采样。
- 文件上传读大文件。

### 4.2 Background loops

Loop 列表：

- Metrics/output loop：默认 `0.5s`，最小 `0.25s`。
- Heartbeat watchdog：`0.5s` 检查一次是否需要 HTTP probe。
- Discovery listener：由 DNS-SD callback 驱动。
- UDP listener：阻塞接收，收到后 marshal 到 UI dispatcher。

每个 loop 必须由 owner 持有 `CancellationTokenSource`：

- `AppViewModel` 负责 app lifetime。
- `ConnectionCoordinator` 负责 discovery/heartbeat/watchdog。
- `OutputFrameScheduler` 负责 metrics/output。
- `CalibrationWorkflow` 负责 preview debounce。

### 4.3 Dispatcher 规则

- Service callback 进入 ViewModel 前使用 `DispatcherQueue.TryEnqueue`。
- ViewModel 内状态变更必须在 UI thread。
- Service 内部不依赖 `DispatcherQueue`。

## 5. Dependency Injection

建议使用轻量 DI 容器：

- `IOrbHttpClient -> OrbHttpClient`
- `IDeviceDiscoveryService -> Win32DnsSdDiscoveryService`
- `IHeartbeatListenerService -> UdpHeartbeatListenerService`
- `ISystemMetricsService -> WindowsSystemMetricsService`
- `IAppStateStore -> AppStateStore`
- `IFileDialogService -> FileDialogService`
- `ITrayService -> ShellTrayService`
- `ILogger<T>` 或项目内 `IDiagnosticsLogger`

开发期可先手写 service locator，但接口边界要先定住，方便测试。

## 6. 错误模型

统一 domain exception：

- `OrbHttpException(statusCode, endpoint, body)`
- `OrbProtocolException(message, body)`
- `OrbDiscoveryException(kind, message)`
- `OrbHeartbeatException(kind, message)`
- `OrbSystemMetricsException(metric, message)`
- `OrbFileException(path, message)`

UI 文案不直接展示 raw exception：

- HTTP 4xx/5xx 映射成“设备拒绝请求 / 当前模块离线 / 地址冲突”等。
- 网络失败映射成“无法连接主控，请确认 Windows 与 ORB 在同一局域网”。
- UDP 被防火墙拦截时提示允许专用网络入站。

## 7. 日志和诊断

第一版至少记录到：

- Debug output。
- `%LOCALAPPDATA%\ORB\logs\orb-windows.log`，按大小滚动。

日志等级：

- `Info`：启动、发现设备、连接、状态刷新、输出帧每 10 帧摘要。
- `Warn`：心跳丢失、HTTP probe 失败、指标采样 fallback。
- `Error`：HTTP API 错误、OTA 失败、native API 初始化失败。

不要记录：

- Wi-Fi 密码。
- 用户文件完整内容。
- 大量每帧 channels 明细。

## 8. 资源策略

直接复用 Mac 资源：

- `origin.png`
- `radiance.png`
- `balance.png`
- `orb_icon_set/*`

复制到 Windows app `Assets/` 后通过 project file 打包。

后续可把产品图提升到 `assets/client/` 公共目录，但第一版不要因为资源重组阻塞工程。
