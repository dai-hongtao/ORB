# ORB Windows Client Development Docs

日期：2026-05-08  
状态：Windows 客户端开发前规格文档。ESP32 固件保持不改。

## 阅读顺序

1. `../PORTING_PLAN.md`：迁移范围、里程碑和关键风险。
2. `ARCHITECTURE.md`：工程结构、模块边界和线程模型。
3. `PROTOCOL.md`：和 ESP32 通信的唯一协议基线。
4. `STATE_AND_WORKFLOWS.md`：连接、输出、注册、校准、OTA 等状态流。
5. `WINDOWS_SYSTEM_SERVICES.md`：Windows API、mDNS、UDP、托盘、文件系统。
6. `UI_SPEC.md`：WinUI 界面规格和 Mac 端对应关系。
7. `BACKLOG.md`：实施任务拆分。
8. `TEST_PLAN.md`：测试策略和回归清单。

## 文档原则

- Mac 客户端是行为源，ESP32 固件是协议源。
- Windows 端可以改 UI 技术实现，但不能改用户心智和硬件协议。
- 每个服务都要能被 mock，避免 UI 层直接碰 HTTP、UDP、Win32 API。
- 第一版优先完整闭环，再追求动画和细节质感。
- 所有 Windows-only 决策都要有 fallback：DNS-SD 失败有 UDP/手动 IP，UDP 失败有 HTTP ping，指标采样失败有保守默认值。

## 推荐工程命名

- Solution：`ORB.Windows.sln`
- App project：`ORB.Windows`
- Test project：`ORB.Windows.Tests`
- Default namespace：`Orb.Windows`

## 约定

- “主控”指 ESP32C3 源模块。
- “模块”指曜/衡扩展模块。
- “通道”指每个扩展模块上的两个输出通道，索引固定为 `0` 和 `1`。
- “DAC code” 指 `0...4095` 的 MCP4728 输出值。
- “state revision” 指 ESP32 心跳中的 `state_revision`，用于判断是否需要刷新完整状态。
