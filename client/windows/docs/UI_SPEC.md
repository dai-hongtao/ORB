# UI Specification

## 1. 总体原则

- 第一屏就是可操作的 ORB 舞台，不做 landing page。
- Windows 版用 Fluent 视觉，但信息结构和 Mac 一致。
- 常用操作在舞台上完成：连接状态、源设置、通道绑定、寻找、校准、注册新设备。
- 开发者设置是覆盖层，不打断主舞台心智。
- 所有硬件相关危险操作必须有明确状态反馈。

## 2. Window

初始尺寸：

```text
1100 x 640
```

最小尺寸：

```text
760 x 520
```

背景：

- 使用 Windows app background。
- 舞台区域保留足够空白，不使用复杂装饰背景。

## 3. Main Stage

### 3.1 Product assets

```text
origin.png   1000 x 1000
radiance.png 1000 x 1000
balance.png  1000 x 1200
```

### 3.2 Layout constants

从 Mac 迁移：

```text
sourceVisibleWidth = 880
moduleVisibleWidth = 664
sourcePixelSize = 1000 x 1000
sourceHotspot = x 60, y 634, w 882, h 328
radiance channel 0 rect = x 586, y 177, w 199, h 578
radiance channel 1 rect = x 250, y 180, w 200, h 576
balance channel 1 rect = x 216, y 70,  w 569, h 217
balance channel 0 rect = x 216, y 578, w 569, h 218
balance needle channel 1 center = 502,443 length 333
balance needle channel 0 center = 502,951 length 333
```

Radiance glow bars：

```text
channel 0 down: x 656, y 285
channel 0 up:   x 656, y 666
channel 1 down: x 320, y 285
channel 1 up:   x 320, y 666
bar width = 58
max height = 190
```

Stage scaling：

```text
visiblePixels = sourceVisibleWidth + moduleCount * moduleVisibleWidth
availableWidth = windowWidth - 48
widthFit = availableWidth / (visiblePixels / 1000)
verticalReserve = 190
bottomPadding = 42
heightFit = (windowHeight - verticalReserve - bottomPadding) / maxImagePixelHeightRatio
imageSide = min(420, max(120, min(widthFit, heightFit)))
```

### 3.3 Module order

- Source 永远在最左。
- 注册模块按本地 layout position 排序。
- 新出现的模块追加到末尾。
- 删除模块移除对应 slot。
- 拖拽模块水平排序，drop 后持久化。

### 3.4 Empty state

如果没有 `DeviceState` 且 source 不在线：

```text
请将「源」模块连接至 Wi-Fi。
```

Windows 可以额外在次级文案提示：

```text
如果已经完成配网，请确认电脑和 ORB 在同一局域网。
```

## 4. Connection Badge

位置：

- 右上角，距 top/right 约 `22px`。

内容：

- 状态圆点。
- 文案：
  - `已连接`
  - `未连接`
  - `本地网络被禁止` 仅 Mac 使用；Windows 用防火墙/网络访问文案。
- 刷新按钮。

行为：

- 点击刷新按钮调用 `ReconnectFromStatusBadge()`。
- Tooltip 展示连接帮助：
  - online：已连接。
  - offline：上次看到设备，但当前心跳不新鲜。
  - not found：尚未发现 ORB 设备。
  - firewall suspected：提示允许专用网络。

## 5. Source Inline Settings

触发：

- 点击源模块热点。

内容：

- IP 地址。
- 采样频率 slider。

Mac 舞台 slider 是 `0...2s step 0.1`，详情页是 `0.25...5s step 0.25`。Windows 建议统一：

- 舞台 inline：`0.25...2.0s step 0.25`
- 源详情/维护：`0.25...5.0s step 0.25`

修改后：

- 持久化。
- 重启 metrics/output loop。
- 标记 motion draft changed。

## 6. Radiance Channel Interaction

### 6.1 Hotspot

- 每个曜模块有两个 tube hotspot。
- Hover/active 时显示发光边框。
- 点击通道后显示：
  - action bar：寻找、校准。
  - metric candidate panel。

### 6.2 Candidate tokens

候选：

- 大核平均，如果存在 performance cores。
- 小核平均，如果存在 efficiency cores。
- CPU0...CPUN。
- 内存占用。

Token 规则：

- 点击 token：绑定到当前 active channel。
- Shift 多选：多个 CPU token 组成平均。
- 拖拽 token 到任一 tube hotspot：绑定到目标 channel。
- 内存 token 独占，绑定后清空选中。

已绑定 chip：

- 显示在 tube 上方。
- 右键移除。
- 拖回 candidate panel 移除。

### 6.3 Binding behavior

- 绑定 CPU 时使用 `MetricSourceKind.CpuCoreAverage`。
- 如果当前已是 CPU 绑定，新选择的 core 与现有 core 合并。
- 绑定内存时使用 `MetricSourceKind.MemoryUsage`，清 core list。

## 7. Balance Channel Interaction

### 7.1 Hotspot

- 每个衡模块两个 gauge hotspot。
- 点击 gauge 后显示：
  - action bar：寻找、校准、导入设置。
  - balance candidate panel。

### 7.2 Candidate tokens

候选：

- 网速上行。
- 网速下行。
- 硬盘读取。
- 硬盘写入。

规则：

- 每个 token 全局只显示一次，已经绑定的 token 从候选中隐藏。
- 点击 token：绑定到当前 gauge。
- 拖拽 token 到任一 gauge hotspot：绑定到目标 channel。
- 已绑定 label 可右键移除或拖回 candidate panel 移除。

### 7.3 Gauge SVG

导入设置：

- 选择 gauge designer 导出的 JSON。
- 自动寻找 SVG。
- 成功后：
  - `MetricBinding.ScalePoints = parsed ticks`
  - `MetricBinding.DialSvgPath = path`
  - `MetricBinding.DialSvgMarkup = svg text`

舞台上：

- 如果绑定有 SVG markup，在 gauge rect 中渲染 SVG。
- SVG 黑白化规则和 Mac 一致：强制 stroke/fill 为黑色，透明背景。

## 8. Real-time Simulation

舞台要显示软件模拟输出：

- Radiance：绿色 bar 按当前 percent 动。
- Balance：红色指针按当前 percent 转动。

动画模型与 Mac 保持大体一致：

```text
settleSeconds = max(config.settleTimeMs / 1000, 0.12)
maxVelocity = max(config.vMax / 5.0, 0.18)
maxAcceleration = max(config.aMax / 7.5, 0.22)
desiredVelocity = clamp((target - current) / settleSeconds, -maxVelocity, maxVelocity)
velocity = velocity + clamp(desiredVelocity - velocity, -maxAcceleration * dt, maxAcceleration * dt)
percent = clamp(current + velocity * dt, 0, 1)
```

条件：

- 模块离线或校准高亮时 immediate jump。
- 在线但无有效 binding 时 percent 为 `0`。

## 9. Unknown Device Overlay

触发：

- `DeviceState.UnknownI2CAddresses` 非空。

未展开：

- 右上显示“发现新设备”卡片。

注册面板：

- 标题：你连接了什么模块？
- 类型选择：曜 / 衡。
- 槽位选择：有效 ID 列表。
- 按钮：确认 / 取消。

Reset 面板：

- 当未知地址不是 `0x60` 且无可用槽位，需要 reset。
- 文案说明会写回 `0x60`。
- 按钮：确认 reset / 取消。

忙碌状态：

- 按钮 disabled。
- 显示 hourglass 或 progress ring。

## 10. Maintenance Overlay

触发：

- 托盘菜单“开发者设置”。
- 主 UI 后续可加快捷入口。

形态：

- 右侧宽 `760px` overlay。
- 背景 dim。
- 点击外部或 x 关闭，回到 source selection。

内容：

1. 已发现 ORB 服务。
2. 注册表快照。
3. 运动参数。
4. I2C 调试。
5. OTA 升级固件。
6. 手动 IP 连接，Windows 增加。

## 11. Source Detail

内容：

- 连接状态。
- IP。
- MAC。
- 固件版本。
- 主控心跳摘要。
- 采集/下发频率。
- CPU 总负载。
- 内存占用。
- 最近采样。
- 到位时间。
- 曜运动参数。
- 衡运动参数。
- 确认参数按钮。

## 12. Radiance Detail

内容：

- 模块说明。
- 绑定摘要。
- 状态。
- 地址。
- 通道 2、通道 1 的设置，保持 Mac 当前顺序。
- CPU core selection editor。
- Metric debug panel。
- LUT 状态。
- 寻找通道。
- 校准通道。
- 删除设备。

CPU editor：

- Picker：CPU 核心组平均 / 内存占用。
- 全选 / 全不选。
- 核心 chip，颜色按 P/E/unknown。

## 13. Balance Detail

内容：

- 模块说明。
- 绑定摘要。
- 状态。
- 地址。
- 通道 1、通道 2 设置。
- Metric picker：网速上行/下行、硬盘读取/写入。
- Metric debug panel。
- LUT 状态。
- 寻找。
- 校准。
- 删除。

## 14. Calibration Dialog

形态：

- Modal dialog。
- 最小宽度约 `560px`。

内容：

- 标题：`曜 · #1 · 通道 1 校准`。
- 当前步骤说明。
- 当前步、当前输出、总步数。
- 目标示意：
  - Radiance：裁剪产品图 + 目标绿色 bar。
  - Balance：表盘 SVG + 目标红色指针。
- Slider。
- 上一步 / 下一步 / 保存 LUT / 取消。
- 错误文案。

Radiance 裁剪：

```text
channel 0: x 586, y 177, w 199, h 578
channel 1: x 250, y 180, w 200, h 576
```

Balance 裁剪：

```text
channel 0: x 216, y 578, w 569, h 218
channel 1: x 216, y 70,  w 569, h 217
```

## 15. Toast / Notice

轻量消息：

- `ModuleActionNotice`
- `ModuleActionIssue`
- `MotionApplySuccessNotice`
- `ReconnectStatusNotice`
- `UnknownDeviceNotice/Issue`
- `I2CDebugNotice/Issue`
- `FirmwareUploadNotice/Issue`

规则：

- success 用绿色。
- issue 用红色。
- 默认 3 秒自动消失，除非用户进入同一流程。
- 不遮挡连接 badge 和注册 overlay。

## 16. Accessibility

第一版要求：

- 所有 icon-only button 有 tooltip / automation name。
- Dialog 有默认按钮和取消按钮。
- 颜色状态必须配文字。
- 键盘可操作：Tab 遍历 buttons、slider、picker。
- 托盘菜单项有文本。

## 17. Windows-specific Additions

相对 Mac 增加：

- 防火墙/专用网络帮助 banner。
- 手动 IP 入口。
- 托盘图标。
- 如果 DNS-SD 不可用，开发者设置显示 discovery fallback 状态。
