# ESP32 Protocol

## 1. 常量

| 名称 | 值 |
| --- | --- |
| HTTP scheme | `http` |
| HTTP port | `80` |
| DNS-SD service type | `_orb._tcp.local.` |
| UDP heartbeat default port | `43981` |
| Heartbeat interval | `1500ms` |
| Max modules | `8` |
| Channels per module | `2` |
| DAC code range | `0...4095` |
| Fresh module address | `0x60` |
| Writable module addresses | `0x60...0x67` |

## 2. Naming

ESP32 JSON 使用 snake_case。Windows domain model 使用 PascalCase，但 DTO 必须显式映射 JSON 名称。

示例：

```csharp
public sealed record OrbDeviceStateDto(
    [property: JsonPropertyName("device_name")] string DeviceName,
    [property: JsonPropertyName("firmware_version")] string FirmwareVersion,
    [property: JsonPropertyName("state_revision")] int? StateRevision);
```

不要依赖全局 naming policy 猜字段，尤其是 `I2C`、`LUT`、`MAC`、`IP` 这类缩写字段。

## 3. Discovery

### 3.1 DNS-SD

浏览：

- Type：`_orb._tcp.local.`
- Instance：通常是 `ORB-XXXX`
- Port：`80`

TXT：

- `device`
- `fw`

解析结果进入 `DiscoveredService`：

```text
name: string
hostName: string?
port: int?
txt: dictionary<string,string>
```

连接时必须重新 resolve，不能长期信任旧 IP。

### 3.2 UDP Heartbeat

监听：

1. 优先绑定 UDP `43981`。
2. 如果失败，绑定动态端口。
3. 如果动态端口可用，连接后调用 `/api/v1/heartbeat/config`。

心跳 JSON：

```json
{
  "type": "heartbeat",
  "protocol_version": 1,
  "device_name": "ORB-1234",
  "firmware_version": "0.1.0",
  "ip": "192.168.1.120",
  "mac": "AA:BB:CC:DD:EE:FF",
  "port": 80,
  "sequence": 42,
  "state_revision": 8,
  "heartbeat_interval_ms": 1500,
  "default_port": 43981,
  "target_port": 43981,
  "configured_port": false,
  "delivery": "udp_broadcast",
  "uptime_ms": 123456,
  "registered_count": 2,
  "present_count": 2
}
```

兼容规则：

- `default_port`、`target_port`、`configured_port`、`delivery` 可以缺失。
- `receivedAt` 是客户端字段，不来自 JSON。
- 心跳按 `device_name` 或 `mac` 关联当前设备。没有当前设备时，任何 ORB 心跳都可触发加载状态。

## 4. HTTP Client

### 4.1 URL

```text
http://{endpoint.host}:{endpoint.port}{path}
```

`endpoint.port` 默认来自 DNS-SD 或 heartbeat 的 `port`。如果 state 内只有 IP，端口 fallback 为 `80`。

### 4.2 Timeouts

| 操作 | Timeout |
| --- | --- |
| ping/state/smoothing/register/delete/reset/i2c/calibration | `5s` |
| preview | 单次 `0.75...0.9s`，总重试窗口 `3s` |
| frame | `5s`，但失败只记录不弹窗 |
| OTA upload | `180s` |

### 4.3 Form Encoding

Mutating API 当前都用：

```text
Content-Type: application/x-www-form-urlencoded; charset=utf-8
```

字段按 key 排序不是协议要求，但 Mac 端这么做。Windows 可保持排序，方便测试。

百分号编码 allowlist：

```text
A-Z a-z 0-9 - . _ ~
```

## 5. Endpoints

### 5.1 GET `/api/v1/ping`

用途：

- 轻量探活。
- 获取 heartbeat routing 信息。
- 判断是否需要完整 state refresh。

响应：

```json
{
  "ok": true,
  "device_name": "ORB-1234",
  "firmware_version": "0.1.0",
  "ip": "192.168.1.120",
  "mac": "AA:BB:CC:DD:EE:FF",
  "port": 80,
  "state_revision": 8,
  "heartbeat_interval_ms": 1500,
  "heartbeat_default_port": 43981,
  "heartbeat_target_port": 43981,
  "heartbeat_configured_port": false,
  "heartbeat_delivery": "udp_broadcast"
}
```

### 5.2 POST `/api/v1/heartbeat/config`

请求：

```text
udp_port=43982
```

响应：

```json
{
  "ok": true,
  "heartbeat_default_port": 43981,
  "heartbeat_target_port": 43982,
  "heartbeat_configured_port": true,
  "heartbeat_delivery": "udp_broadcast"
}
```

ACK 校验：

- `ok == true`
- `heartbeat_target_port == listenerPort`
- `heartbeat_configured_port == true`

### 5.3 GET `/api/v1/state`

响应：

```json
{
  "device_name": "ORB-1234",
  "firmware_version": "0.1.0",
  "ip": "192.168.1.120",
  "mac": "AA:BB:CC:DD:EE:FF",
  "state_revision": 8,
  "heartbeat_interval_ms": 1500,
  "heartbeat_default_port": 43981,
  "heartbeat_target_port": 43981,
  "heartbeat_configured_port": false,
  "heartbeat_delivery": "udp_broadcast",
  "wifi_mode": "sta",
  "unknown_candidate_present": false,
  "detected_i2c_addresses": [96, 97],
  "unknown_i2c_addresses": [],
  "calibration_luts": [],
  "smoothing": {
    "radiance": {
      "settle_time_ms": 250,
      "a_max": 7.100,
      "v_max": 2.600,
      "jitter_frequency_hz": 2.500,
      "jitter_amplitude": 0.800,
      "jitter_dispersion": 0.320
    },
    "balance": {
      "settle_time_ms": 250,
      "a_max": 8.000,
      "v_max": 5.800,
      "jitter_frequency_hz": 0.000,
      "jitter_amplitude": 0.000,
      "jitter_dispersion": 0.250
    }
  },
  "modules": [
    {"id": 1, "registered": true, "present": true, "module_type": 1}
  ]
}
```

兼容：

- `unknown_candidate_present` 缺失时，用 `unknown_i2c_addresses` 是否为空推导。
- `calibration_luts` 缺失时保留本地已知 LUT。
- `smoothing` 缺失时使用默认参数。

### 5.4 POST `/api/v1/smoothing`

请求：

```text
module_type=1
settle_time_ms=350
a_max=7.100
v_max=2.600
jitter_frequency_hz=2.500
jitter_amplitude=0.800
jitter_dispersion=0.320
```

调用策略：

1. 先对 Radiance 调用。
2. 再对 Balance 调用。
3. 最终 state 必须同时校验 Radiance 和 Balance。

ACK 校验 tolerance：

- `settle_time_ms` 必须完全一致。
- 浮点字段误差 `<= 0.0015`。

### 5.5 POST `/api/v1/frame`

请求：

```text
frame_id=12
channels=1,0,2048;1,1,1024;2,0,3650
```

响应：

```json
{
  "ok": true,
  "frame_id": 12,
  "applied": 3
}
```

发送规则：

- 空 channels 不发送。
- 只有 ready 条件满足才发送。
- 请求失败只记日志，不弹用户 toast。
- `frame_id` app 运行期单调递增，重启后可从 0 重新开始。

### 5.6 POST `/api/v1/preview`

请求：

```text
mode=calibration
module_id=1
channel_index=0
target_code=2048
```

响应：

```json
{
  "ok": true,
  "preview_active": true,
  "mode": "calibration",
  "module_id": 1,
  "channel_index": 0,
  "target_code": 2048
}
```

ACK 必须逐字段校验。失败可重试条件：

- HTTP `>=500`
- timeout
- connection lost
- cannot connect
- DNS lookup failed
- not connected

不可重试：

- invalid URL
- invalid response
- JSON decode failed
- HTTP 4xx
- cancellation

### 5.7 POST `/api/v1/modules/register`

请求：

```text
module_type=1
id=1
address=96
```

注意：

- `module_type`：Radiance `1`，Balance `2`。
- `id=8` 在 UI 显示为 `ID 0`，协议仍传 `8`。
- `address` 是当前检测到的 I2C 地址十进制值，`0x60` 是 `96`。

成功响应完整 state。

### 5.8 POST `/api/v1/modules/delete`

请求：

```text
id=1
```

成功后 Windows 本地也要删除：

- `ModuleSetting`。
- 对应 `CalibrationLUT`。
- 舞台 layout slot。

### 5.9 POST `/api/v1/modules/reset`

请求：

```text
address=97
```

用途：把未知旧地址模块重置回 `0x60`。

限制：

- `address` 不能是 `0x60`。
- 目标 `0x60` 必须空闲。

### 5.10 POST `/api/v1/i2c/write_address`

请求：

```text
old_address=97
new_address=96
```

用途：开发者维护，不自动修改注册表。

### 5.11 POST `/api/v1/calibration/save`

请求：

```text
module_id=1
channel_index=0
points=0.0000:0.0000;0.2500:0.3000;0.5000:0.5200;0.7500:0.7600;1.0000:1.0000
updated_at_epoch=1778256000
```

规则：

- points 最少 2 点，最多 11 点。
- input/output 都是 `0...1` 浮点。
- 保存成功响应完整 state。

### 5.12 POST `/api/v1/firmware/upload`

请求：

- `multipart/form-data`
- field：`firmware`
- filename：用户选择的 `.bin`
- content type：`application/octet-stream`

响应：

```json
{
  "ok": true,
  "rebooting": true,
  "message": "固件上传成功，ESP32 正在重启。",
  "firmware_version": "0.1.0"
}
```

客户端行为：

1. 上传中禁止重复上传。
2. 成功后清空 selected file。
3. 清空 last contact / latest heartbeat。
4. 3 秒后自动 reconnect。

## 6. Address Rules

```text
ID 1 -> 0x61
ID 2 -> 0x62
ID 3 -> 0x63
ID 4 -> 0x64
ID 5 -> 0x65
ID 6 -> 0x66
ID 7 -> 0x67
ID 8 -> 0x60, UI label "0"
```

Windows helpers：

```text
SlotLabel(8) = "0"
AddressForModuleId(1...7) = 0x60 + id
AddressForModuleId(8) = 0x60
IdForAddress(0x61...0x67) = address - 0x60
IdForAddress(0x60) = 8
```

## 7. Error Mapping

常见固件 error：

| error | UI 文案建议 |
| --- | --- |
| `missing_*` | 客户端请求参数缺失，请升级客户端或反馈日志 |
| `invalid_*` | 请求参数不合法 |
| `module_not_registered` | 这个模块还未注册 |
| `module_not_present` | 模块当前离线，请检查供电和连接 |
| `slot_occupied` | 目标槽位已被占用 |
| `source_device_not_detected` | 当前地址没有检测到模块 |
| `target_address_busy` | 目标 I2C 地址已被占用 |
| `reserved_slot_not_allowed` | 前 7 个槽位未满，不能占用保留槽位 |
| `only_reserved_slot_available` | 前 7 个槽位已满，请使用 ID 0 |
| `address_rewrite_failed` | 模块改址失败，请断电重试 |
| `invalid_calibration_points` | LUT 点数量不足或格式不合法 |
| `firmware_upload_failed` | 固件上传失败，请确认 BIN 文件和网络 |

日志中保留 raw `error` 和 HTTP status，UI 文案做友好映射。
