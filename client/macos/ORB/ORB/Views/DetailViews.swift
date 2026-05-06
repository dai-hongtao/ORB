import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct SourceDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let connectionStatus: ConnectionStatus
    let deviceState: ORBDeviceState?
    @Binding var refreshInterval: Double
    let systemMetrics: SystemMetricsSnapshot

    var body: some View {
        DetailPanel(title: "源") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    detailStat(title: "连接状态", value: appModel.localized(connectionStatus.labelKey))
                    detailStat(title: "IP", value: deviceState?.ip ?? "--")
                    detailStat(title: "MAC", value: deviceState?.mac ?? "--")
                    detailStat(title: "固件版本", value: deviceState?.firmwareVersion ?? "--")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("主控心跳")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Text(appModel.latestHeartbeatSummary)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("采集 / 下发频率")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        Spacer()
                        Text("\(refreshInterval, specifier: "%.2f") 秒 / 次")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.67, green: 0.37, blue: 0.18))
                    }

                    Slider(value: $refreshInterval, in: 0.25...5.0, step: 0.25)

                    Text("当前这项设置已经用于 Mac 端系统采样；后续真正下发到 ESP32 时也会复用同一节奏。注册表不会按这个频率自动轮询。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 16) {
                    detailStat(title: "CPU 总负载", value: percentText(systemMetrics.totalCPUUsagePercent))
                    detailStat(title: "内存占用", value: percentText(systemMetrics.memoryUsagePercent))
                    detailStat(title: "最近采样", value: timestampText(systemMetrics.sampledAt))
                }

                MotionTimingControlPanel(
                    factor: Binding(
                        get: { appModel.motionDraftDurationFactor },
                        set: { appModel.updateMotionDraftDurationFactor($0) }
                    ),
                    refreshInterval: refreshInterval,
                    movementDurationSeconds: appModel.motionDraftMovementDurationSeconds
                )

                HStack(alignment: .top, spacing: 16) {
                    MotionProfileControlPanel(
                        title: "曜运动参数",
                        tint: ModuleType.radiance.accentColor,
                        config: appModel.motionDraftConfig(for: .radiance),
                        updateAMax: { appModel.updateSmoothingAMax(for: .radiance, value: $0) },
                        updateVMax: { appModel.updateSmoothingVMax(for: .radiance, value: $0) },
                        updateJitterFrequency: { appModel.updateJitterFrequency(for: .radiance, value: $0) },
                        updateJitterAmplitude: { appModel.updateJitterAmplitude(for: .radiance, value: $0) },
                        updateJitterDispersion: { appModel.updateJitterDispersion(for: .radiance, value: $0) }
                    )
                    MotionProfileControlPanel(
                        title: "衡运动参数",
                        tint: ModuleType.balance.accentColor,
                        config: appModel.motionDraftConfig(for: .balance),
                        updateAMax: { appModel.updateSmoothingAMax(for: .balance, value: $0) },
                        updateVMax: { appModel.updateSmoothingVMax(for: .balance, value: $0) },
                        updateJitterFrequency: { appModel.updateJitterFrequency(for: .balance, value: $0) },
                        updateJitterAmplitude: { appModel.updateJitterAmplitude(for: .balance, value: $0) },
                        updateJitterDispersion: { appModel.updateJitterDispersion(for: .balance, value: $0) }
                    )
                }

                HStack(spacing: 12) {
                    Button(appModel.isApplyingMotionSettings ? "确认中..." : "确认参数") {
                        appModel.applyMotionSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appModel.isApplyingMotionSettings ? Color.gray : Color(red: 0.67, green: 0.37, blue: 0.18))
                    .disabled(!appModel.canApplyMotionSettings)

                    if appModel.hasPendingMotionChanges && !appModel.isApplyingMotionSettings {
                        Text("当前修改尚未下发")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    if let notice = appModel.motionApplySuccessNotice {
                        Label(notice, systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.green)
                    }

                    Spacer()
                }

                if let issue = appModel.smoothingActionIssue {
                    Text(issue)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }
            }
        }
    }

    private func detailStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .separatorColor).opacity(0.12))
        )
    }
}

struct RadianceDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: RegistryEntry

    var body: some View {
        DetailPanel(title: "曜 · #\(entry.displaySlotLabel)") {
            VStack(alignment: .leading, spacing: 18) {
                Text("6E2 电子眼模块，用于展示 CPU 风格的指标。")
                    .foregroundStyle(.secondary)

                detailRow(label: "绑定", value: appModel.bindingSummary(for: entry))
                detailRow(label: "状态", value: appModel.statusText(for: entry))
                detailRow(label: "地址", value: entry.addressLabel)

                ForEach([1, 0], id: \.self) { channelIndex in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            CPUCoreSelectionEditor(
                                title: "通道 \(channelIndex + 1)",
                                metricKind: Binding(
                                    get: { appModel.binding(for: entry, channelIndex: channelIndex).metric.kind },
                                    set: { appModel.updateMetricKind(for: entry, channelIndex: channelIndex, metricKind: $0) }
                                ),
                                availableCPUCoreDescriptors: appModel.availableCPUCoreDescriptors,
                                performanceCount: appModel.performanceCPUCoreCount,
                                efficiencyCount: appModel.efficiencyCPUCoreCount,
                                isSelected: { appModel.isCPUCoreSelected(for: entry, channelIndex: channelIndex, coreIndex: $0) },
                                toggleCore: { appModel.toggleCPUCoreSelection(for: entry, channelIndex: channelIndex, coreIndex: $0) },
                                selectAll: { appModel.selectAllCPUCores(for: entry, channelIndex: channelIndex) },
                                clearAll: { appModel.clearCPUCoreSelection(for: entry, channelIndex: channelIndex) }
                            )
                            MetricDebugPanel(
                                title: "调试",
                                info: appModel.debugInfo(for: entry, channelIndex: channelIndex)
                            )
                        }

                        HStack {
                            Text("通道 \(channelIndex + 1) LUT：\(appModel.calibrationStatusText(for: entry, channelIndex: channelIndex))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) ? "寻找中..." : "寻找通道 \(channelIndex + 1)") {
                                appModel.locateChannel(for: entry, channelIndex: channelIndex)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) || appModel.isStartingCalibration(for: entry, channelIndex: channelIndex))
                            Button(appModel.isStartingCalibration(for: entry, channelIndex: channelIndex) ? "准备校准中..." : "校准通道 \(channelIndex + 1)") {
                                appModel.beginCalibration(for: entry, channelIndex: channelIndex)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appModel.isStartingCalibration(for: entry, channelIndex: channelIndex) || appModel.isLocatingChannel(for: entry, channelIndex: channelIndex))
                        }
                    }
                }

                Button("删除设备") {
                    appModel.deleteSelectedModule()
                }
                .buttonStyle(.bordered)

                if let issue = appModel.moduleActionIssue {
                    Text(issue)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }
            }
        }
    }
}

struct BalanceDetailView: View {
    @EnvironmentObject private var appModel: AppModel
    let entry: RegistryEntry

    var body: some View {
        DetailPanel(title: "衡 · #\(entry.displaySlotLabel)") {
            VStack(alignment: .leading, spacing: 18) {
                Text("模拟表头模块，用于展示网络与磁盘吞吐。")
                    .foregroundStyle(.secondary)

                detailRow(label: "绑定", value: appModel.bindingSummary(for: entry))
                detailRow(label: "状态", value: appModel.statusText(for: entry))
                detailRow(label: "地址", value: entry.addressLabel)

                ForEach(0..<2, id: \.self) { channelIndex in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top, spacing: 14) {
                            BalanceMetricEditor(
                                title: "通道 \(channelIndex + 1)",
                                metricKind: Binding(
                                    get: { appModel.binding(for: entry, channelIndex: channelIndex).metric.kind },
                                    set: { appModel.updateMetricKind(for: entry, channelIndex: channelIndex, metricKind: $0) }
                                )
                            )
                            MetricDebugPanel(
                                title: "调试",
                                info: appModel.debugInfo(for: entry, channelIndex: channelIndex)
                            )
                        }

                        HStack {
                            Text("通道 \(channelIndex + 1) LUT：\(appModel.calibrationStatusText(for: entry, channelIndex: channelIndex))")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) ? "寻找中..." : "寻找通道 \(channelIndex + 1)") {
                                appModel.locateChannel(for: entry, channelIndex: channelIndex)
                            }
                            .buttonStyle(.bordered)
                            .disabled(appModel.isLocatingChannel(for: entry, channelIndex: channelIndex) || appModel.isStartingCalibration(for: entry, channelIndex: channelIndex))
                            Button(appModel.isStartingCalibration(for: entry, channelIndex: channelIndex) ? "准备校准中..." : "校准通道 \(channelIndex + 1)") {
                                appModel.beginCalibration(for: entry, channelIndex: channelIndex)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(appModel.isStartingCalibration(for: entry, channelIndex: channelIndex) || appModel.isLocatingChannel(for: entry, channelIndex: channelIndex))
                        }
                    }
                }

                Button("删除设备") {
                    appModel.deleteSelectedModule()
                }
                .buttonStyle(.bordered)

                if let issue = appModel.moduleActionIssue {
                    Text(issue)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }
            }
        }
    }
}

struct ModulePlaceholderDetailView: View {
    let title: String
    let description: String

    var body: some View {
        DetailPanel(title: title) {
            Text(description)
                .foregroundStyle(.secondary)
        }
    }
}

struct UnknownDeviceResetView: View {
    let addressLabel: String
    let issueText: String?
    let isResetting: Bool
    let cancelAction: () -> Void
    let resetAction: () -> Void

    var body: some View {
        UnknownDevicePanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("该设备已绑定其它主机，是否重置？")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text("当前检测到的地址是 \(addressLabel)。如果继续重置，ESP32 会把这个模块的地址写回 0x60，成功后你就可以重新分配类型和新的槽位地址。")
                    .foregroundStyle(.secondary)

                if let issueText {
                    Text(issueText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }

                HStack(spacing: 12) {
                    Button {
                        resetAction()
                    } label: {
                        Image(systemName: isResetting ? "hourglass" : "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isResetting)
                    .help("确认")

                    Button {
                        cancelAction()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResetting)
                    .help("取消")
                }
            }
        }
    }
}

struct UnknownDeviceRegistrationView: View {
    @Binding var moduleType: ModuleType
    @Binding var moduleID: Int?
    let validIDs: [Int]
    let noticeText: String?
    let issueText: String?
    let isRegistering: Bool
    let cancelAction: () -> Void
    let registerAction: () -> Void
    @State private var hoveredModuleType: ModuleType?

    var body: some View {
        UnknownDevicePanel {
            VStack(alignment: .leading, spacing: 18) {
                Text("你连接了什么模块？")
                    .font(.system(size: 18, weight: .bold, design: .rounded))

                HStack(spacing: 18) {
                    ForEach(ModuleType.registrationOptions, id: \.self) { option in
                        UnknownModuleTypeChoice(
                            moduleType: option,
                            isSelected: moduleType == option,
                            isHovered: hoveredModuleType == option
                        ) {
                            moduleType = option
                        }
                        .onHover { hovering in
                            hoveredModuleType = hovering ? option : nil
                        }
                    }
                }

                if validIDs.isEmpty {
                    Text("当前没有可分配的槽位。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let noticeText {
                    Text(noticeText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                if let issueText {
                    Text(issueText)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }

                HStack(spacing: 12) {
                    Button {
                        registerAction()
                    } label: {
                        Image(systemName: isRegistering ? "hourglass" : "checkmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.67, green: 0.37, blue: 0.18))
                    .disabled(isRegistering || validIDs.isEmpty)
                    .help("确认")

                    Button {
                        cancelAction()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRegistering)
                    .help("取消")
                }
            }
            .onAppear {
                moduleID = moduleID ?? validIDs.first
            }
            .onChange(of: validIDs) { _, ids in
                if let current = moduleID, ids.contains(current) {
                    return
                }
                moduleID = ids.first
            }
        }
    }
}

private struct UnknownModuleTypeChoice: View {
    let moduleType: ModuleType
    let isSelected: Bool
    let isHovered: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(isSelected || isHovered ? 0.16 : 0.04))
                        .frame(width: 118, height: 118)
                    Circle()
                        .stroke(Color.white.opacity(isSelected || isHovered ? 0.92 : 0.18), lineWidth: isSelected ? 3 : 2)
                        .frame(width: 118, height: 118)

                    if moduleType == .balance {
                        BalanceChoiceGraphic()
                            .frame(width: 94, height: 94)
                            .grayscale(isSelected ? 0 : 1)
                            .opacity(isSelected ? 1 : 0.42)
                    } else {
                        UnknownModuleTypeImage(name: imageName)
                            .frame(width: 94, height: 94)
                            .grayscale(isSelected ? 0 : 1)
                            .opacity(isSelected ? 1 : 0.42)
                    }
                }

                Text(moduleType.displayName)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(moduleType.displayName)
    }

    private var imageName: String {
        switch moduleType {
        case .radiance:
            return "radiance"
        case .balance, .unknown:
            return "balance"
        }
    }
}

private struct BalanceChoiceGraphic: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 5, y: 2)

            Circle()
                .stroke(Color.black.opacity(0.12), lineWidth: 1)

            Capsule()
                .fill(Color.red)
                .frame(width: 5, height: 45)
                .offset(y: -17)
                .rotationEffect(.degrees(34), anchor: .bottom)

            Circle()
                .fill(Color.red)
                .frame(width: 11, height: 11)
        }
        .padding(6)
    }
}

private struct UnknownModuleTypeImage: View {
    let name: String

    var body: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "questionmark")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    private var image: NSImage? {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "resources") {
            return NSImage(contentsOf: url)
        }
        return Bundle.main.image(forResource: name)
    }
}

private struct UnknownDevicePanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.14), radius: 20, y: 12)
    }
}

struct MaintenancePanelView: View {
    @EnvironmentObject private var appModel: AppModel
    let discoveredServices: [DiscoveredService]
    let deviceState: ORBDeviceState?

    var body: some View {
        DetailPanel(title: "开发者设置") {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("已发现的 ORB 服务")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    if discoveredServices.isEmpty {
                        Text("当前还没有看到 Bonjour 设备。")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(discoveredServices) { service in
                            HStack {
                                Text(service.name)
                                    .fontWeight(.semibold)
                                Spacer()
                                Text(service.endpointLabel)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("注册表快照")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                    if let modules = deviceState?.registeredModules, !modules.isEmpty {
                        ForEach(modules) { entry in
                            HStack {
                                Text("#\(entry.displaySlotLabel) · \(entry.moduleType.displayName)")
                                Spacer()
                                Text(entry.present ? "在线" : "离线")
                                    .foregroundStyle(entry.present ? Color.green : .secondary)
                            }
                            .padding(.vertical, 6)
                        }
                    } else {
                        Text("等待主控返回实时注册表。")
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("运动参数")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text("用于调整曜和衡模块的平滑算法。")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("恢复默认") {
                            appModel.resetMotionDraftToDefaults()
                        }
                        .buttonStyle(.bordered)
                        .disabled(appModel.isApplyingMotionSettings)
                    }

                    MotionTimingControlPanel(
                        factor: Binding(
                            get: { appModel.motionDraftDurationFactor },
                            set: { appModel.updateMotionDraftDurationFactor($0) }
                        ),
                        refreshInterval: appModel.refreshInterval,
                        movementDurationSeconds: appModel.motionDraftMovementDurationSeconds
                    )

                    HStack(alignment: .top, spacing: 16) {
                        MotionProfileControlPanel(
                            title: "曜运动参数",
                            tint: ModuleType.radiance.accentColor,
                            config: appModel.motionDraftConfig(for: .radiance),
                            updateAMax: { appModel.updateSmoothingAMax(for: .radiance, value: $0) },
                            updateVMax: { appModel.updateSmoothingVMax(for: .radiance, value: $0) },
                            updateJitterFrequency: { appModel.updateJitterFrequency(for: .radiance, value: $0) },
                            updateJitterAmplitude: { appModel.updateJitterAmplitude(for: .radiance, value: $0) },
                            updateJitterDispersion: { appModel.updateJitterDispersion(for: .radiance, value: $0) }
                        )
                        MotionProfileControlPanel(
                            title: "衡运动参数",
                            tint: ModuleType.balance.accentColor,
                            config: appModel.motionDraftConfig(for: .balance),
                            updateAMax: { appModel.updateSmoothingAMax(for: .balance, value: $0) },
                            updateVMax: { appModel.updateSmoothingVMax(for: .balance, value: $0) },
                            updateJitterFrequency: { appModel.updateJitterFrequency(for: .balance, value: $0) },
                            updateJitterAmplitude: { appModel.updateJitterAmplitude(for: .balance, value: $0) },
                            updateJitterDispersion: { appModel.updateJitterDispersion(for: .balance, value: $0) }
                        )
                    }

                    HStack(spacing: 12) {
                        Button(appModel.isApplyingMotionSettings ? "应用中..." : "应用参数") {
                            appModel.applyMotionSettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(appModel.isApplyingMotionSettings ? Color.gray : Color(red: 0.67, green: 0.37, blue: 0.18))
                        .disabled(!appModel.canApplyMotionSettings)

                        if appModel.hasPendingMotionChanges && !appModel.isApplyingMotionSettings {
                            Text("当前修改尚未下发")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        if let notice = appModel.motionApplySuccessNotice {
                            Label(notice, systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.green)
                        }

                        Spacer()
                    }

                    if let issue = appModel.smoothingActionIssue {
                        Text(issue)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(Color.red)
                    }
                }

                I2CDebugSection()

                FirmwareUpdateSection()
            }
        }
    }
}

private struct I2CDebugSection: View {
    @EnvironmentObject private var appModel: AppModel

    private let addressColumns = [
        GridItem(.adaptive(minimum: 110), spacing: 8)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("I2C 调试")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
                Button(appModel.isScanningI2CDevices ? "扫描中..." : "扫描现有 I2C") {
                    appModel.scanI2CDevices()
                }
                .buttonStyle(.bordered)
                .disabled(appModel.isScanningI2CDevices || appModel.isWritingI2CAddress)
            }

            if appModel.detectedI2CAddresses.isEmpty {
                Text("当前还没有扫描到 I2C 设备。")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: addressColumns, alignment: .leading, spacing: 8) {
                    ForEach(appModel.detectedI2CAddresses, id: \.self) { address in
                        Text(rawAddressLabel(address))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(nsColor: .separatorColor).opacity(0.12))
                            )
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前地址")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    if appModel.detectedI2CAddresses.isEmpty {
                        Text("等待扫描")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "当前地址",
                            selection: Binding(
                                get: { appModel.i2cDebugSourceAddress ?? appModel.detectedI2CAddresses.first ?? 0x60 },
                                set: { appModel.i2cDebugSourceAddress = $0 }
                            )
                        ) {
                            ForEach(appModel.detectedI2CAddresses, id: \.self) { address in
                                Text(rawAddressLabel(address)).tag(address)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("新地址")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                    Picker("新地址", selection: $appModel.i2cDebugTargetAddress) {
                        ForEach(appModel.writableI2CDebugAddresses, id: \.self) { address in
                            Text(rawAddressLabel(address)).tag(address)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Button(appModel.isWritingI2CAddress ? "写入中..." : "写入新地址") {
                    appModel.writeI2CAddress()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.67, green: 0.37, blue: 0.18))
                .disabled(appModel.detectedI2CAddresses.isEmpty || appModel.isWritingI2CAddress || appModel.isScanningI2CDevices)
            }

            if let notice = appModel.i2cDebugNotice {
                Text(notice)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.green)
            }

            if let issue = appModel.i2cDebugIssue {
                Text(issue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red)
            }
        }
    }
}

private struct CPUCoreSelectionEditor: View {
    let title: String
    @Binding var metricKind: MetricSourceKind
    let availableCPUCoreDescriptors: [CPUCoreDescriptor]
    let performanceCount: Int
    let efficiencyCount: Int
    let isSelected: (Int) -> Bool
    let toggleCore: (Int) -> Void
    let selectAll: () -> Void
    let clearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                Spacer()
            }

            Picker("指示内容", selection: $metricKind) {
                ForEach(MetricSourceKind.options(for: .radiance), id: \.self) { kind in
                    Text(LocalizedStringKey(kind.localizedLabelKey)).tag(kind)
                }
            }
            .pickerStyle(.menu)

            if metricKind == .memoryUsage {
                Text("内存占用会直接按系统当前内存百分比映射到电子管。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Button("全选", action: selectAll)
                        .buttonStyle(.bordered)
                    Button("全不选", action: clearAll)
                        .buttonStyle(.bordered)
                    Spacer()
                }

                Text("直接勾选想参与平均的 CPU 核心；只选一个时，就显示这个核心本身。全不选会回到默认的 CPU 0。")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                HStack(spacing: 14) {
                    CoreKindLegendChip(
                        color: efficiencyCoreColor,
                        label: "能效核心",
                        count: efficiencyCount
                    )
                    CoreKindLegendChip(
                        color: performanceCoreColor,
                        label: "性能核心",
                        count: performanceCount
                    )
                    Spacer()
                }

                ScrollView(.vertical) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                        ForEach(availableCPUCoreDescriptors) { core in
                            Button(isSelected(core.index) ? "核心 \(core.index) 已选" : "核心 \(core.index)") {
                                toggleCore(core.index)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(isSelected(core.index) ? tint(for: core.kind) : Color(nsColor: .separatorColor))
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }

    private func tint(for kind: CPUCoreKind) -> Color {
        switch kind {
        case .performance:
            return performanceCoreColor
        case .efficiency:
            return efficiencyCoreColor
        case .unknown:
            return Color(red: 0.17, green: 0.46, blue: 0.52)
        }
    }

    private var performanceCoreColor: Color {
        Color(red: 0.95, green: 0.34, blue: 0.67)
    }

    private var efficiencyCoreColor: Color {
        Color(red: 0.43, green: 0.84, blue: 0.24)
    }
}

private struct CoreKindLegendChip: View {
    let color: Color
    let label: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text("\(label) \(count) 个")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct FirmwareUpdateSection: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var isImportingFirmware = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("OTA升级固件")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            detailRow(label: "当前文件", value: appModel.selectedFirmwareUploadFilename)

            HStack(spacing: 12) {
                Button("选择 BIN 文件") {
                    isImportingFirmware = true
                }
                .buttonStyle(.bordered)

                Button(appModel.isUploadingFirmware ? "上传中..." : "上传并刷写") {
                    appModel.uploadFirmware()
                }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isUploadingFirmware || appModel.selectedFirmwareUploadURL == nil)
            }

            if let notice = appModel.firmwareUploadNotice {
                Label(notice, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.green)
            }

            if let issue = appModel.firmwareUploadIssue {
                Text(issue)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.red)
            }
        }
        .fileImporter(
            isPresented: $isImportingFirmware,
            allowedContentTypes: [.data]
        ) { result in
            switch result {
            case .success(let url):
                appModel.setFirmwareUploadURL(url)
            case .failure(let error):
                appModel.setFirmwareUploadSelectionError("选择固件失败：\(error.localizedDescription)")
            }
        }
    }
}

private struct BalanceMetricEditor: View {
    let title: String
    @Binding var metricKind: MetricSourceKind

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .bold, design: .rounded))

            Picker("指示内容", selection: $metricKind) {
                ForEach(MetricSourceKind.options(for: .balance), id: \.self) { kind in
                    Text(LocalizedStringKey(kind.localizedLabelKey)).tag(kind)
                }
            }
            .pickerStyle(.menu)

            Text("网速和硬盘速度都会先按固定业务刻度换算成百分比，再送入 LUT。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }
}

private struct MetricDebugPanel: View {
    let title: String
    let info: MetricDebugInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .bold, design: .rounded))

            MetricChip(title: "采样值", value: info.sampleText)
            MetricChip(title: "平均 / 映射后", value: percentText(info.mappedPercent))
            MetricChip(title: "LUT 前", value: "\(info.preLUTCode)")
            MetricChip(title: "LUT 后", value: "\(info.postLUTCode) · \(percentText(info.postLUTPercent))")
        }
        .frame(maxWidth: 220, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }
}

private struct MotionTimingControlPanel: View {
    @Binding var factor: Double
    let refreshInterval: Double
    let movementDurationSeconds: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("到位时间")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("预计用时")
                    Spacer()
                    Text(String(format: "%.2f 秒", movementDurationSeconds))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $factor,
                    in: 0.10...1.50,
                    step: 0.05
                )
            }

            Text("数值越小响应越快，数值越大运动越柔和。当前采样周期为 \(refreshInterval, specifier: "%.2f") 秒。")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }
}

private struct MotionProfileControlPanel: View {
    let title: String
    let tint: Color
    let config: SmoothingConfig
    let updateAMax: (Double) -> Void
    let updateVMax: (Double) -> Void
    let updateJitterFrequency: (Double) -> Void
    let updateJitterAmplitude: (Double) -> Void
    let updateJitterDispersion: (Double) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .bold, design: .rounded))

            motionSlider(
                label: "响应力度",
                value: config.aMax,
                range: 0.5...20.0,
                step: 0.1,
                action: updateAMax
            )

            motionSlider(
                label: "最大速度",
                value: config.vMax,
                range: 0.1...12.0,
                step: 0.1,
                action: updateVMax
            )

            motionSlider(
                label: "抖动频率",
                value: config.jitterFrequencyHz,
                range: 0.0...8.0,
                step: 0.1,
                suffix: "Hz",
                action: updateJitterFrequency
            )

            motionSlider(
                label: "抖动幅度",
                value: config.jitterAmplitude,
                range: 0.0...6.0,
                step: 0.1,
                suffix: "%FS",
                action: updateJitterAmplitude
            )

            motionSlider(
                label: "抖动随机度",
                value: config.jitterDispersion,
                range: 0.0...1.0,
                step: 0.02,
                action: updateJitterDispersion
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(tint.opacity(0.08))
        )
    }

    @ViewBuilder
    private func motionSlider(
        label: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String = "",
        action: @escaping (Double) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(LocalizedStringKey(label))
                Spacer()
                Text(valueText(value, suffix: suffix))
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { value },
                    set: action
                ),
                in: range,
                step: step
            )
        }
    }

    private func valueText(_ value: Double, suffix: String) -> String {
        if suffix.isEmpty {
            return String(format: "%.2f", value)
        }
        return String(format: "%.2f %@", value, suffix)
    }
}

struct CalibrationSheetView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        if let draft = appModel.activeCalibration {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(draft.moduleType.displayName) · #\(slotLabel(for: draft.moduleID)) · 通道 \(draft.channelIndex + 1) 校准")
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                Text(appModel.calibrationInstructionText(for: draft))
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    detailStatCard(title: "当前步", value: appModel.calibrationStepDisplayLabel(for: draft))
                    detailStatCard(title: "当前输出", value: percentText(draft.currentStep.output * 100))
                    detailStatCard(title: "总步数", value: "\(draft.points.count)")
                }

                HStack(alignment: .top, spacing: 20) {
                    if let metric = appModel.calibrationMetricBinding(for: draft) {
                        CalibrationTargetPreview(
                            draft: draft,
                            metric: metric,
                            label: appModel.calibrationStepDisplayLabel(for: draft)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("校准滑块")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        Slider(
                            value: Binding(
                                get: { appModel.activeCalibrationCurrentOutput },
                                set: { appModel.updateActiveCalibrationOutput($0) }
                            ),
                            in: 0...1
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let issue = appModel.moduleActionIssue {
                    Text(issue)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.red)
                }

                HStack(spacing: 12) {
                    Button("上一步") {
                        appModel.moveCalibrationStep(by: -1)
                    }
                    .buttonStyle(.bordered)
                    .disabled(draft.stepIndex == 0)

                    if draft.stepIndex < draft.points.count - 1 {
                        Button("下一步") {
                            appModel.moveCalibrationStep(by: 1)
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button("保存 LUT") {
                            appModel.saveActiveCalibration()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.67, green: 0.37, blue: 0.18))
                    }

                    Button("取消") {
                        appModel.dismissCalibration()
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(24)
            .frame(minWidth: 560)
        }
    }

    private func detailStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }
}

private struct CalibrationTargetPreview: View {
    let draft: CalibrationDraft
    let metric: MetricBinding
    let label: String

    private var cropRect: CGRect {
        switch draft.moduleType {
        case .radiance:
            return draft.channelIndex == 0
                ? CGRect(x: 586, y: 177, width: 199, height: 578)
                : CGRect(x: 250, y: 180, width: 200, height: 576)
        case .balance:
            return draft.channelIndex == 0
                ? CGRect(x: 216, y: 578, width: 569, height: 218)
                : CGRect(x: 216, y: 70, width: 569, height: 217)
        case .unknown:
            return .zero
        }
    }

    private var previewScale: CGFloat {
        let maxWidth: CGFloat = draft.moduleType == .radiance ? 180 : 320
        let maxHeight: CGFloat = 280
        return min(maxWidth / cropRect.width, maxHeight / cropRect.height)
    }

    private var previewSize: CGSize {
        CGSize(width: cropRect.width * previewScale, height: cropRect.height * previewScale)
    }

    private var imageName: String {
        switch draft.moduleType {
        case .radiance:
            return "radiance"
        case .balance, .unknown:
            return "balance"
        }
    }

    private var fullImageSize: CGSize {
        switch draft.moduleType {
        case .radiance, .unknown:
            return CGSize(width: 1000, height: 1000)
        case .balance:
            return CGSize(width: 1000, height: 1200)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("目标示意")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            ZStack(alignment: .topTrailing) {
                if draft.moduleType == .radiance {
                    CalibrationCroppedProductImage(
                        imageName: imageName,
                        fullImageSize: fullImageSize,
                        cropRect: cropRect,
                        displaySize: previewSize
                    )

                    RadianceCalibrationBarsPreview(
                        channelIndex: draft.channelIndex,
                        percent: draft.currentStep.input,
                        cropRect: cropRect,
                        scale: previewScale
                    )
                } else if draft.moduleType == .balance {
                    Rectangle()
                        .fill(Color(white: 183.0 / 255.0))
                        .frame(width: previewSize.width, height: previewSize.height)

                    if let svgMarkup = metric.dialSVGMarkup {
                        CalibrationGaugeSVG(markup: svgMarkup)
                            .frame(width: previewSize.width, height: previewSize.height)
                    }

                    GaugeCalibrationNeedleShape(
                        center: localGaugeCenter,
                        length: 333 * previewScale,
                        percent: draft.currentStep.input
                    )
                    .stroke(Color(red: 0.93, green: 0.18, blue: 0.18), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .shadow(color: Color.red.opacity(0.3), radius: 4)
                    .mask(Rectangle().frame(width: previewSize.width, height: previewSize.height))
                }

                Text(label)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
            .frame(width: previewSize.width, height: previewSize.height)
            .clipShape(Rectangle())
            .overlay(
                Rectangle()
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private var localGaugeCenter: CGPoint {
        let globalCenter = draft.channelIndex == 0 ? CGPoint(x: 502, y: 951) : CGPoint(x: 502, y: 443)
        return CGPoint(
            x: (globalCenter.x - cropRect.minX) * previewScale,
            y: (globalCenter.y - cropRect.minY) * previewScale
        )
    }
}

private struct CalibrationCroppedProductImage: View {
    let imageName: String
    let fullImageSize: CGSize
    let cropRect: CGRect
    let displaySize: CGSize

    var body: some View {
        if let image = croppedImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: displaySize.width, height: displaySize.height)
        } else {
            Rectangle()
                .fill(Color.clear)
                .frame(width: displaySize.width, height: displaySize.height)
        }
    }

    private var croppedImage: NSImage? {
        guard let image = sourceImage,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / fullImageSize.width
        let scaleY = CGFloat(cgImage.height) / fullImageSize.height
        let pixelRect = CGRect(
            x: cropRect.minX * scaleX,
            y: (fullImageSize.height - cropRect.maxY) * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral

        guard let cropped = cgImage.cropping(to: pixelRect) else {
            return nil
        }

        return NSImage(cgImage: cropped, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    private var sourceImage: NSImage? {
        if let url = Bundle.main.url(forResource: imageName, withExtension: "png", subdirectory: "resources") {
            return NSImage(contentsOf: url)
        }
        return Bundle.main.image(forResource: imageName)
    }
}

private struct GaugeCalibrationNeedleShape: Shape {
    let center: CGPoint
    let length: CGFloat
    var percent: Double

    var animatableData: Double {
        get { percent }
        set { percent = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clampedPercent = min(max(percent, 0), 1)
        let angle = Angle.degrees(135 - 90 * clampedPercent)
        let radians = angle.radians
        let endpoint = CGPoint(
            x: center.x + CGFloat(Darwin.cos(radians)) * length,
            y: center.y - CGFloat(Darwin.sin(radians)) * length
        )
        var path = Path()
        path.move(to: center)
        path.addLine(to: endpoint)
        return path
    }
}

private struct RadianceCalibrationBarsPreview: View {
    let channelIndex: Int
    let percent: Double
    let cropRect: CGRect
    let scale: CGFloat

    private var bars: [CGRect] {
        let definitions: [(Int, CGFloat, CGFloat, Bool)] = [
            (0, 656, 285, true),
            (0, 656, 666, false),
            (1, 320, 285, true),
            (1, 320, 666, false)
        ]

        return definitions.compactMap { def in
            guard def.0 == channelIndex else { return nil }
            let height = max(0, min(1, percent)) * 190
            let rect: CGRect
            if def.3 {
                rect = CGRect(x: def.1, y: def.2, width: 58, height: height)
            } else {
                rect = CGRect(x: def.1, y: def.2 - height, width: 58, height: height)
            }
            return rect.intersection(cropRect)
        }.filter { !$0.isNull && !$0.isEmpty }
    }

    var body: some View {
        ZStack {
            ForEach(Array(bars.enumerated()), id: \.offset) { _, rect in
                Rectangle()
                    .fill(Color(red: 44 / 255, green: 204 / 255, blue: 113 / 255))
                    .frame(width: rect.width * scale, height: rect.height * scale)
                    .shadow(color: Color(red: 44 / 255, green: 204 / 255, blue: 113 / 255).opacity(0.65), radius: 10)
                    .position(
                        x: (rect.midX - cropRect.minX) * scale,
                        y: (rect.midY - cropRect.minY) * scale
                    )
            }
        }
    }
}

private struct CalibrationGaugeSVG: NSViewRepresentable {
    let markup: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html(for: markup), baseURL: nil)
    }

    private func html(for svg: String) -> String {
        """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        html, body { margin: 0; padding: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
        svg { display: block; width: 100%; height: 100%; }
        svg *[stroke]:not([stroke="none"]) { stroke: #000 !important; }
        svg *[fill]:not([fill="none"]) { fill: #000 !important; }
        </style>
        </head>
        <body>\(svg)</body>
        </html>
        """
    }
}

private struct MetricChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .separatorColor).opacity(0.08))
        )
    }
}

private struct DetailPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 24, weight: .bold, design: .rounded))
            ScrollView(.vertical) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, y: 12)
    }
}

private func percentText(_ value: Double) -> String {
    String(format: "%.1f%%", value)
}

private func byteCountText(_ value: UInt64) -> String {
    byteCountFormatter.string(fromByteCount: Int64(clamping: value))
}

private func rateText(_ value: Double) -> String {
    "\(byteCountFormatter.string(fromByteCount: Int64(max(value, 0))))/s"
}

private func timestampText(_ date: Date) -> String {
    guard date > .distantPast else {
        return "--"
    }
    return timestampFormatter.string(from: date)
}

private let byteCountFormatter: ByteCountFormatter = {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.countStyle = .binary
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter
}()

private let timestampFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color(nsColor: .separatorColor).opacity(0.14))
            )
    }
}

private func detailRow(label: String, value: String) -> some View {
    HStack {
        Text(LocalizedStringKey(label))
            .fontWeight(.semibold)
        Spacer()
        Text(value)
            .foregroundStyle(.secondary)
    }
    .padding(.vertical, 10)
    .padding(.horizontal, 14)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(nsColor: .separatorColor).opacity(0.12))
    )
}
