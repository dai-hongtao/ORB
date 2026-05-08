# Test Plan

## 1. 测试层级

```text
Unit tests
  Pure models, mapping, normalization, LUT, encoding

Integration tests
  Mock HTTP server, mock UDP heartbeat, fake metrics source

Manual hardware tests
  Real ESP32 + real modules + Windows 11 machines

Release regression
  Fresh install, upgrade, firewall, OTA, packaging
```

## 2. Unit Tests

### 2.1 Address mapping

Cases：

- `AddressForModuleId(1) == 0x61`
- `AddressForModuleId(7) == 0x67`
- `AddressForModuleId(8) == 0x60`
- `SlotLabel(8) == "0"`
- invalid ID returns null/throws typed validation error。

### 2.2 JSON decode

Fixtures：

- `state_full.json`
- `state_missing_optional_fields.json`
- `heartbeat_full.json`
- `heartbeat_legacy_no_route.json`

Assert：

- snake_case fields map correctly。
- missing `unknown_candidate_present` is derived from unknown addresses。
- missing smoothing uses defaults。
- missing calibration LUTs does not clear local state unexpectedly。

### 2.3 Form encode

Cases：

- `/frame` channels format。
- `/preview` fields。
- `/calibration/save` points format with 4 decimals。
- percent encoding of special characters。

### 2.4 LUT mapper

Cases：

- no LUT：`0 -> 0`，`1 -> 4095`，`0.5 -> 2048`。
- unordered points sorted before interpolation。
- missing endpoint inserts `(0,0)` and `(1,1)`。
- output clamped to `0...4095`。
- duplicate input points do not divide by zero。

### 2.5 Metric normalization

Cases：

- total CPU clamp。
- core average with selected cores。
- core selection empty returns not-send。
- memory `used/total`。
- network fallback ranges。
- disk fallback ranges。
- custom scale points。
- custom scale points beyond max clamp to last percent。

### 2.6 Ready gate

Cases：

- no endpoint -> no frame。
- offline -> no frame。
- active calibration -> no frame。
- locating -> no frame。
- unknown devices -> no frame。
- metric none -> no channel。
- CPU metric with empty core list -> no channel。

### 2.7 Persistence

Cases：

- no file -> defaults。
- bad JSON -> defaults + log。
- legacy `binding` -> two channelBindings。
- legacy shared LUT -> channel 0 and 1。
- save/read roundtrip。

## 3. Integration Tests

### 3.1 Mock HTTP server

模拟 endpoints：

- `/api/v1/ping`
- `/api/v1/state`
- `/api/v1/heartbeat/config`
- `/api/v1/frame`
- `/api/v1/preview`
- `/api/v1/modules/register`
- `/api/v1/modules/delete`
- `/api/v1/modules/reset`
- `/api/v1/i2c/write_address`
- `/api/v1/calibration/save`
- `/api/v1/firmware/upload`

Assert：

- method/path/content-type 正确。
- form body 正确。
- timeout 和 cancellation 正确。
- 4xx/5xx 映射到 typed exception。

### 3.2 UDP heartbeat broadcaster

Cases：

- preferred port receives heartbeat。
- dynamic port receives heartbeat after preferred occupied。
- invalid JSON ignored。
- heartbeat state revision change triggers delayed state refresh。

### 3.3 Connection coordinator

使用 fake discovery + fake heartbeat + mock HTTP：

- discovery first connect。
- heartbeat first connect。
- reconnect prefers current service name。
- HTTP probe recovers online status。
- HTTP probe failure leaves offline/not found correctly。

### 3.4 Output loop

使用 fake metrics：

- 每 tick 生成 frame。
- refresh interval changed restarts loop。
- frame send success notes device contact。
- frame send failure only logs。

### 3.5 Calibration workflow

Mock preview endpoint：

- ACK exact match opens dialog。
- ACK mismatched mode/module/channel/target fails。
- retry on transient timeout。
- save LUT calls calibration endpoint and upserts local LUT。

### 3.6 OTA workflow

Mock upload：

- multipart contains firmware field。
- progress advances。
- success clears file and schedules reconnect。
- failure preserves selected file and shows issue。

## 4. Manual Hardware Tests

### 4.1 Test matrix

至少覆盖：

- Windows 11 x64 desktop/laptop。
- Windows 11 arm64，如果可获得设备。
- 中文系统。
- 英文系统。
- 普通家用路由器。
- 至少一个存在虚拟网卡的环境。

### 4.2 Discovery and connection

Steps：

1. ORB 已接入 Wi-Fi。
2. 打开 Windows 客户端。
3. 等待自动发现。

Expected：

- 设备进入 online。
- 服务列表显示 `ORB-XXXX`。
- 心跳摘要更新。
- IP/MAC/固件版本正确。

### 4.3 Firewall scenarios

Scenario A：允许专用网络。

- 收到 UDP 心跳。
- 不依赖频繁 HTTP probe。

Scenario B：拒绝或阻断 UDP。

- HTTP probe 仍可保持基本在线。
- UI 有可理解提示。
- 操作不崩。

### 4.4 Metrics output

Steps：

- 绑定曜通道到 CPU core average。
- 运行 CPU load。
- 绑定曜通道到 memory。
- 增加内存压力。
- 绑定衡通道到 network up/down。
- 下载/上传文件。
- 绑定衡通道到 disk read/write。
- 拷贝大文件。

Expected：

- 硬件显示和软件模拟都随指标变化。
- debug panel 值合理。

### 4.5 Module registration

Steps：

1. 只接一个新模块，地址 `0x60`。
2. 选择曜，注册到 ID 1。
3. 断电换另一个新模块。
4. 选择衡，注册到 ID 2。

Expected：

- 注册成功后模块显示在线。
- I2C 地址符合规则。
- 本地 binding 默认值正确。

### 4.6 Reset old unknown device

Steps：

1. 制造一个不在注册表但地址为 `0x61...0x67` 的模块。
2. 客户端显示 reset 流程。
3. reset。
4. 继续注册。

Expected：

- reset 后看到 `0x60`。
- 可注册。

### 4.7 Locate

Steps：

- 对每个通道点击寻找。

Expected：

- 只有目标通道亮/动。
- 3 秒后恢复实时输出。

### 4.8 Calibration

Radiance：

- 按 `0%, 50%, 25%, 100%, 75%` 完成。
- 保存 LUT。
- 重启客户端。

Expected：

- LUT 状态保留。
- 输出使用 LUT 后 code。

Balance：

- 导入 gauge JSON/SVG。
- 按导入刻度校准。
- 保存 LUT。

Expected：

- 校准目标显示导入 SVG。
- 指针位置和表盘刻度一致。

### 4.9 Motion settings

Steps：

- 修改到位时间。
- 修改曜/衡响应力度、最大速度、抖动参数。
- 应用。

Expected：

- 固件返回参数一致。
- 舞台模拟和硬件运动变化明显。
- 重启客户端后参数从设备同步。

### 4.10 I2C debug

Steps：

- 扫描现有 I2C。
- 选择地址。
- 改写到空闲地址。

Expected：

- 扫描显示正确地址。
- 改址成功后新地址出现。
- 注册表不被自动修改。

### 4.11 OTA

Steps：

- 选择 `.bin`。
- 上传。
- 等设备重启。

Expected：

- 上传成功提示。
- 设备重启期间 offline。
- 之后自动 reconnect。

## 5. Release Regression

必须通过：

- 干净 Windows 11 安装后首次启动。
- 无硬件启动。
- 有硬件自动连接。
- 托盘打开/关闭/退出。
- 中英文切换。
- app_state 写入和重启恢复。
- 日志文件生成。
- 卸载后不影响用户自己保存的固件文件。

## 6. Test Artifacts

建议新增：

```text
tests/ORB.Windows.Tests/Fixtures/
  state_full.json
  state_missing_optional_fields.json
  heartbeat_full.json
  heartbeat_legacy_no_route.json
  gauge_export.json
  gauge.svg
```

硬件回归记录：

```text
client/windows/docs/test-runs/YYYY-MM-DD-rcN.md
```

记录内容：

- Windows 版本。
- 机器架构。
- 网络环境。
- ORB 固件版本。
- 模块数量和类型。
- 通过/失败项。
- 日志片段。
