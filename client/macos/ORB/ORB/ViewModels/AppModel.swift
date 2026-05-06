import AppKit
import Combine
import Darwin
import SwiftUI
import UniformTypeIdentifiers

private enum UnknownDeviceFlow {
    case registerToNewAddress
    case resetBeforeRegister
    case registerAsFinalSlot
}

private let localNetworkPrimerDefaultsKey = "orb.localNetworkPrimerAccepted"

struct MetricDebugInfo {
    let sampleText: String
    let mappedPercent: Double
    let preLUTCode: Int
    let postLUTCode: Int

    var postLUTPercent: Double {
        Double(postLUTCode) / 4095.0 * 100.0
    }
}

private struct PiecewiseRange {
    let lowerValue: Double
    let upperValue: Double
    let lowerPercent: Double
    let upperPercent: Double
}

private struct GaugeExport: Decodable {
    let state: GaugeExportState
}

private struct GaugeExportState: Decodable {
    let majorTicks: [GaugeExportTick]
}

private struct GaugeExportTick: Decodable {
    let valueText: String
    let unitText: String
    let percent: Double
}

private struct CPUCoreTopology {
    let performanceCount: Int
    let efficiencyCount: Int

    var totalCount: Int {
        max(performanceCount + efficiencyCount, 1)
    }

    func kind(for index: Int) -> CPUCoreKind {
        guard index >= 0 else { return .unknown }
        if performanceCount > 0 || efficiencyCount > 0 {
            if index < efficiencyCount {
                return .efficiency
            }
            if index < efficiencyCount + performanceCount {
                return .performance
            }
        }
        return .unknown
    }

    static func current() -> CPUCoreTopology {
        let performance = sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        let efficiency = sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        if performance > 0 || efficiency > 0 {
            return CPUCoreTopology(performanceCount: performance, efficiencyCount: efficiency)
        }

        let total = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        return CPUCoreTopology(performanceCount: total, efficiencyCount: 0)
    }
}

private func sysctlInt(_ key: String) -> Int? {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    let result = key.withCString { keyPointer in
        sysctlbyname(keyPointer, &value, &size, nil, 0)
    }
    guard result == 0 else {
        return nil
    }
    return Int(value)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var appLanguage: AppLanguage {
        didSet {
            persistState()
            updateMainWindowTitle()
        }
    }
    @Published var connectionStatus: ConnectionStatus = .notFound
    @Published var deviceState: ORBDeviceState?
    @Published var discoveredServices: [DiscoveredService] = []
    @Published var refreshInterval: Double
    @Published var motionDurationFactor: Double
    @Published private(set) var motionDraftDurationFactor: Double
    @Published private(set) var systemMetrics: SystemMetricsSnapshot = .empty
    @Published var selectedModuleID: Int?
    @Published var showingMaintenanceScreen = false
    @Published var selectedUnknownAddress: Int?
    @Published var activeCalibration: CalibrationDraft?
    @Published var pendingUnknownModuleType: ModuleType = .radiance
    @Published var pendingUnknownModuleID: Int?
    @Published private(set) var unknownDeviceNotice: String?
    @Published private(set) var unknownDeviceIssue: String?
    @Published private(set) var isPerformingUnknownDeviceAction = false
    @Published private(set) var moduleActionNotice: String?
    @Published private(set) var moduleActionIssue: String?
    @Published var i2cDebugSourceAddress: Int?
    @Published var i2cDebugTargetAddress: Int = 0x60
    @Published private(set) var isScanningI2CDevices = false
    @Published private(set) var isWritingI2CAddress = false
    @Published private(set) var i2cDebugNotice: String?
    @Published private(set) var i2cDebugIssue: String?
    @Published var selectedFirmwareUploadURL: URL?
    @Published private(set) var isUploadingFirmware = false
    @Published private(set) var firmwareUploadNotice: String?
    @Published private(set) var firmwareUploadIssue: String?
    @Published private(set) var shouldShowLocalNetworkPrimer: Bool
    @Published private(set) var locatingChannelKey: String?
    @Published private(set) var pendingCalibrationStartKey: String?
    @Published private(set) var latestHeartbeat: ORBHeartbeat?
    @Published private(set) var heartbeatListenerStatus: HeartbeatListenerStatus = .booting
    @Published private(set) var heartbeatRoutingIssue: String?
    @Published private(set) var localNetworkAccessIssue: String?
    @Published private(set) var smoothingActionIssue: String?
    @Published private(set) var motionDraftProfiles: DeviceSmoothingProfiles
    @Published private(set) var isApplyingMotionSettings = false
    @Published private(set) var motionApplySuccessNotice: String?
    @Published private(set) var reconnectStatusNotice: String?
    @Published var isArrangingModules = false

    private(set) var layout: [LayoutSlot]
    private(set) var moduleSettings: [ModuleSetting]
    private(set) var calibrationLUTs: [CalibrationLUT]

    private let store: AppStore
    private let discoveryService: DeviceDiscoveryService
    private let heartbeatService: HeartbeatListenerService
    private let metricsService: SystemMetricsService
    private let session: ORBSession
    private let cpuTopology: CPUCoreTopology

    private var mainWindow: NSWindow?
    private var activeEndpoint: ORBEndpoint?
    private var hasBootstrapped = false
    private var autoConnectName: String?
    private var metricsTask: Task<Void, Never>?
    private var heartbeatWatchdogTask: Task<Void, Never>?
    private var calibrationPreviewTask: Task<Void, Never>?
    private var calibrationStartTask: Task<Void, Never>?
    private var locatePreviewTask: Task<Void, Never>?
    private var motionApplySuccessTask: Task<Void, Never>?
    private var reconnectStatusNoticeTask: Task<Void, Never>?
    private var heartbeatConfigTask: Task<Void, Never>?
    private var pendingStateRefreshTask: Task<Void, Never>?
    private var firmwareUploadTask: Task<Void, Never>?
    private var moduleActionDismissTask: Task<Void, Never>?
    private var outputFrameID = 0
    private var lastDeviceContactAt: Date?
    private var lastAppliedStateRevision: Int?
    private var lastLivenessProbeAt: Date?
    private var hasLocalMotionDraftEdits = false

    init(
        store: AppStore? = nil,
        discoveryService: DeviceDiscoveryService? = nil,
        heartbeatService: HeartbeatListenerService? = nil,
        metricsService: SystemMetricsService? = nil,
        session: ORBSession? = nil
    ) {
        let resolvedStore = store ?? AppStore()
        let resolvedDiscoveryService = discoveryService ?? DeviceDiscoveryService()
        let resolvedHeartbeatService = heartbeatService ?? HeartbeatListenerService()
        let resolvedMetricsService = metricsService ?? SystemMetricsService()
        let resolvedSession = session ?? ORBSession()

        self.store = resolvedStore
        self.discoveryService = resolvedDiscoveryService
        self.heartbeatService = resolvedHeartbeatService
        self.metricsService = resolvedMetricsService
        self.session = resolvedSession
        self.cpuTopology = CPUCoreTopology.current()

        let persisted = resolvedStore.load()
        let initialSettleTimeMs = Int((persisted.refreshInterval * persisted.motionDurationFactor * 1000).rounded())
        var initialMotionProfiles = DeviceSmoothingProfiles()
        initialMotionProfiles.radiance.settleTimeMs = initialSettleTimeMs
        initialMotionProfiles.balance.settleTimeMs = initialSettleTimeMs
        self.layout = persisted.layout.isEmpty ? [LayoutSlot.source] : persisted.layout
        self.moduleSettings = Self.clearingLegacyBalanceDefaults(in: persisted.moduleSettings)
        self.refreshInterval = persisted.refreshInterval
        self.motionDurationFactor = persisted.motionDurationFactor
        self.motionDraftDurationFactor = persisted.motionDurationFactor
        self.motionDraftProfiles = initialMotionProfiles
        self.calibrationLUTs = Self.expandedCalibrationLUTs(from: persisted.calibrationLUTs)
        self.appLanguage = persisted.appLanguage
        self.shouldShowLocalNetworkPrimer = !UserDefaults.standard.bool(forKey: localNetworkPrimerDefaultsKey)

        resolvedDiscoveryService.onServicesChanged = { [weak self] services in
            guard let self else { return }
            NSLog("ORB App：收到服务列表更新，数量=%ld", services.count)
            self.discoveredServices = services

            if let currentName = self.deviceState?.deviceName ?? self.latestHeartbeat?.deviceName,
               let resolved = services.first(where: { $0.name == currentName }),
               let host = resolved.hostName,
               let port = resolved.port {
                self.activeEndpoint = ORBEndpoint(host: host, port: port)
            }

            self.updateConnectionStatus()

            guard
                self.activeEndpoint == nil,
                self.autoConnectName == nil,
                let first = services.first?.name
            else {
                return
            }

            self.connect(to: first)
        }

        resolvedHeartbeatService.onHeartbeat = { [weak self] heartbeat in
            guard let self else { return }
            self.handleHeartbeat(heartbeat)
        }
        resolvedHeartbeatService.onStatusChanged = { [weak self] status in
            guard let self else { return }
            Task { @MainActor in
                self.heartbeatListenerStatus = status
                if status.isAvailable {
                    self.heartbeatRoutingIssue = nil
                    self.requestHeartbeatRoutingSyncIfPossible()
                }
            }
        }
    }

    static let preview: AppModel = {
        let model = AppModel(
            store: AppStore(),
            discoveryService: DeviceDiscoveryService(),
            metricsService: SystemMetricsService(),
            session: ORBSession()
        )
        model.connectionStatus = .online
        model.deviceState = .preview
        model.systemMetrics = .preview
        model.lastDeviceContactAt = .now
        model.mergeLayout(with: ORBDeviceState.preview.registeredModules)
        model.ensureModuleSettings(for: ORBDeviceState.preview.registeredModules)
        return model
    }()

    var orderedModules: [RegistryEntry] {
        let modules = deviceState?.registeredModules ?? []
        let positions: [Int: Int] = Dictionary(uniqueKeysWithValues: layout.compactMap { slot -> (Int, Int)? in
            guard let moduleID = slot.moduleID else { return nil }
            return (moduleID, slot.position)
        })

        return modules.sorted { lhs, rhs in
            let leftPosition = positions[lhs.id] ?? Int.max
            let rightPosition = positions[rhs.id] ?? Int.max
            if leftPosition == rightPosition {
                return lhs.id < rhs.id
            }
            return leftPosition < rightPosition
        }
    }

    var selectedEntry: RegistryEntry? {
        guard let selectedModuleID else { return nil }
        return orderedModules.first { $0.id == selectedModuleID }
    }

    var unknownDeviceAddresses: [Int] {
        (deviceState?.unknownI2CAddresses ?? []).sorted()
    }

    var detectedI2CAddresses: [Int] {
        (deviceState?.detectedI2CAddresses ?? []).sorted()
    }

    var writableI2CDebugAddresses: [Int] {
        Array(0x60...0x67)
    }

    var selectedUnknownAddressLabel: String {
        guard let selectedUnknownAddress else {
            return "I2C --"
        }
        return rawAddressLabel(selectedUnknownAddress)
    }

    var registeredModules: [RegistryEntry] {
        deviceState?.registeredModules ?? []
    }

    var selectedModuleSetting: ModuleSetting? {
        guard let selectedModuleID else { return nil }
        return moduleSettings.first(where: { $0.moduleID == selectedModuleID })
    }

    var availableCPUCoreIndices: [Int] {
        availableCPUCoreDescriptors.map(\.index)
    }

    var availableCPUCoreDescriptors: [CPUCoreDescriptor] {
        let count = max(systemMetrics.cpuCoreLoads.count, cpuTopology.totalCount)
        return Array(0..<max(count, 1)).map { index in
            CPUCoreDescriptor(index: index, kind: cpuTopology.kind(for: index))
        }
    }

    var performanceCPUCoreCount: Int {
        availableCPUCoreDescriptors.filter { $0.kind == .performance }.count
    }

    var efficiencyCPUCoreCount: Int {
        availableCPUCoreDescriptors.filter { $0.kind == .efficiency }.count
    }

    var selectedFirmwareUploadFilename: String {
        selectedFirmwareUploadURL?.lastPathComponent ?? "未选择 BIN 文件"
    }

    var sourceIsOnline: Bool {
        guard let lastDeviceContactAt else { return false }
        return Date().timeIntervalSince(lastDeviceContactAt) <= heartbeatGraceWindow
    }

    var isHeartbeatFresh: Bool {
        guard heartbeatListenerStatus.isAvailable, let latestHeartbeat else { return false }
        return Date().timeIntervalSince(latestHeartbeat.receivedAt) <= heartbeatGraceWindow
    }

    var latestHeartbeatSummary: String {
        guard let latestHeartbeat else {
            if let message = heartbeatListenerStatus.message {
                return "还没有收到主控心跳。\(message)"
            }
            return "还没有收到主控心跳。"
        }

        var summary = "序号 \(latestHeartbeat.sequence) · 修订 \(latestHeartbeat.stateRevision) · 最近一次 \(timestampLabel(latestHeartbeat.receivedAt))"
        if let message = heartbeatListenerStatus.message {
            summary += " · \(message)"
        }
        return summary
    }

    var connectionStatusText: String {
        localNetworkAccessIssue == nil ? (connectionStatus == .online ? "已连接" : "未连接") : "本地网络被禁止"
    }

    var connectionStatusHelpText: String {
        localNetworkAccessIssue ?? localized(connectionStatus.labelKey)
    }

    var heartbeatListenerSummary: String {
        switch heartbeatListenerStatus.mode {
        case .preferredUDP:
            if let port = heartbeatListenerStatus.localPort {
                return "已监听 UDP \(port)（默认端口）"
            }
            return "已监听默认 UDP 端口"
        case .dynamicUDP:
            if let port = heartbeatListenerStatus.localPort {
                return "已监听 UDP \(port)（动态端口）"
            }
            return "已监听动态 UDP 端口"
        case .unavailable:
            return heartbeatListenerStatus.message ?? "UDP 心跳不可用"
        }
    }

    var heartbeatRouteSummary: String {
        let targetPort = deviceState?.heartbeatTargetPort
        let defaultPort = deviceState?.heartbeatDefaultPort
        let isConfigured = deviceState?.heartbeatConfiguredPort ?? false
        let delivery = deviceState?.heartbeatDelivery ?? "udp_broadcast"

        guard let targetPort else {
            return "等待主控返回心跳投递信息"
        }

        if isConfigured {
            return "\(delivery) -> \(targetPort)（已按上位机端口投递）"
        }

        if let defaultPort {
            return "\(delivery) -> \(targetPort)（当前仍是默认端口 \(defaultPort)）"
        }

        return "\(delivery) -> \(targetPort)"
    }

    var activeReachabilitySummary: String {
        if isHeartbeatFresh {
            return "UDP 心跳"
        }
        if activeEndpoint != nil || deviceState != nil {
            return "Bonjour + HTTP ping/state"
        }
        if !discoveredServices.isEmpty {
            return "仅 Bonjour 发现"
        }
        return "尚未建立链路"
    }

    var movementDurationSeconds: Double {
        max(refreshInterval * motionDurationFactor, 0.05)
    }

    var motionDraftMovementDurationSeconds: Double {
        max(refreshInterval * motionDraftDurationFactor, 0.05)
    }

    var hasPendingMotionChanges: Bool {
        resolvedMotionDraftProfiles() != confirmedMotionProfiles()
    }

    var canApplyMotionSettings: Bool {
        hasPendingMotionChanges && sourceIsOnline && activeEndpoint != nil && !isApplyingMotionSettings
    }

    var sourceCardSubtitle: String {
        if let deviceState {
            return sourceIsOnline ? deviceState.ip : "上次地址 \(deviceState.ip)"
        }

        if let first = discoveredServices.first {
            return "已发现 \(first.name)"
        }

        return "等待 ESP32C3 上线"
    }

    var activeCalibrationCurrentOutput: Double {
        activeCalibration?.currentStep.output ?? 0
    }

    func bootstrap() {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        NSLog("ORB App：启动发现流程")
        restartMetricsSampling()
        heartbeatService.start()
        startHeartbeatWatchdog()
        discoveryService.start()
    }

    func beginLocalNetworkAccessFlow() {
        UserDefaults.standard.set(true, forKey: localNetworkPrimerDefaultsKey)
        shouldShowLocalNetworkPrimer = false
        bootstrap()
    }

    func openLocalNetworkSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.preferences.networkprivacy",
            "x-apple.systempreferences:com.apple.preference.security?PrivacyLocalNetworkService",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork",
            "x-apple.systempreferences:com.apple.preference.security?Privacy"
        ]

        for urlString in urls {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    func attachMainWindow(_ window: NSWindow?) {
        guard let window else { return }
        if mainWindow !== window {
            mainWindow = window
            updateMainWindowTitle()
            window.setContentSize(NSSize(width: 1100, height: 640))
            window.minSize = NSSize(width: 760, height: 520)
            window.isReleasedWhenClosed = false
        }
    }

    var appLocale: Locale {
        appLanguage.locale
    }

    func localized(_ key: String) -> String {
        guard
            let localeIdentifier = appLanguage.localeIdentifier,
            let path = Bundle.main.path(forResource: localeIdentifier, ofType: "lproj"),
            let bundle = Bundle(path: path)
        else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private func updateMainWindowTitle() {
        mainWindow?.title = localized("app.name")
    }

    func presentMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    func selectSource() {
        selectedModuleID = nil
        selectedUnknownAddress = nil
        showingMaintenanceScreen = false
        clearUnknownDeviceFeedback()
    }

    func selectModule(_ id: Int) {
        selectedModuleID = id
        selectedUnknownAddress = nil
        showingMaintenanceScreen = false
        clearUnknownDeviceFeedback()
    }

    func selectUnknownDevice(_ address: Int) {
        selectedUnknownAddress = address
        selectedModuleID = nil
        showingMaintenanceScreen = false
        pendingUnknownModuleType = .radiance
        pendingUnknownModuleID = suggestedRegistrationID(for: address)
        clearUnknownDeviceFeedback()
    }

    func showMaintenance() {
        selectedModuleID = nil
        selectedUnknownAddress = nil
        pendingUnknownModuleID = nil
        showingMaintenanceScreen = true
        isArrangingModules = false
        clearUnknownDeviceFeedback()
        ensureI2CDebugSelection()
    }

    func scanI2CDevices() {
        guard let endpoint = activeEndpoint, sourceIsOnline else {
            i2cDebugIssue = "当前没有可用的 ORB 连接，无法扫描 I2C。"
            return
        }

        isScanningI2CDevices = true
        i2cDebugIssue = nil
        i2cDebugNotice = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.fetchState(from: endpoint)
                await MainActor.run {
                    self.isScanningI2CDevices = false
                    self.applyLoadedState(state, preserveSelection: true)
                    self.ensureI2CDebugSelection()
                    self.i2cDebugNotice = "I2C 扫描完成，发现 \(self.detectedI2CAddresses.count) 个地址。"
                }
            } catch {
                await MainActor.run {
                    self.isScanningI2CDevices = false
                    self.i2cDebugIssue = "I2C 扫描失败：\(error.localizedDescription)"
                    NSLog("ORB App：I2C 扫描失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func writeI2CAddress() {
        guard let endpoint = activeEndpoint, sourceIsOnline else {
            i2cDebugIssue = "当前没有可用的 ORB 连接，无法写入 I2C 地址。"
            return
        }

        guard let oldAddress = i2cDebugSourceAddress else {
            i2cDebugIssue = "请先选择一个当前检测到的 I2C 地址。"
            return
        }

        let newAddress = i2cDebugTargetAddress
        guard writableI2CDebugAddresses.contains(newAddress) else {
            i2cDebugIssue = "目标地址超出当前 MCP4728 支持范围。"
            return
        }

        isWritingI2CAddress = true
        i2cDebugIssue = nil
        i2cDebugNotice = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.writeI2CAddress(
                    oldAddress: oldAddress,
                    newAddress: newAddress,
                    endpoint: endpoint
                )

                await MainActor.run {
                    self.isWritingI2CAddress = false
                    self.applyLoadedState(state, preserveSelection: true)
                    self.ensureI2CDebugSelection(preferred: self.detectedI2CAddresses.contains(newAddress) ? newAddress : nil)
                    self.i2cDebugNotice = String(format: "I2C 改址成功：0x%02X -> 0x%02X", oldAddress, newAddress)
                }
            } catch {
                await MainActor.run {
                    self.isWritingI2CAddress = false
                    self.i2cDebugIssue = "I2C 改址失败：\(error.localizedDescription)"
                    NSLog("ORB App：I2C 改址失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func dismissUnknownDeviceFlow() {
        selectSource()
    }

    func bindingSummary(for entry: RegistryEntry) -> String {
        moduleSettings.first(where: { $0.moduleID == entry.id })?.summary
            ?? ModuleSetting.default(for: entry).summary
    }

    func persistState() {
        store.save(
            StoredAppState(
                layout: layout.sorted { $0.position < $1.position },
                moduleSettings: moduleSettings.sorted { $0.moduleID < $1.moduleID },
                refreshInterval: refreshInterval,
                motionDurationFactor: motionDurationFactor,
                calibrationLUTs: persistedCalibrationLUTs(),
                appLanguage: appLanguage
            )
        )
    }

    func handleRefreshIntervalChanged() {
        persistState()
        restartMetricsSampling()
        noteMotionDraftChanged()
    }

    func connectToFirstDiscoveredDevice() {
        guard let first = discoveredServices.first else {
            updateConnectionStatus()
            return
        }

        connect(to: first.name)
    }

    func reconnect() {
        if let preferredServiceName = preferredServiceNameForReconnect() {
            connect(to: preferredServiceName)
            return
        }

        guard let endpoint = latestHeartbeat?.endpoint ?? activeEndpoint else {
            connectToFirstDiscoveredDevice()
            return
        }

        activeEndpoint = endpoint
        Task {
            await loadState(from: endpoint, preserveSelection: true)
        }
    }

    func reconnectFromStatusBadge() {
        presentReconnectStatusNotice()
        reconnect()
    }

    func toggleArrangementMode() {
        isArrangingModules.toggle()
    }

    func moveModule(_ moduleID: Int, before targetModuleID: Int) {
        guard moduleID != targetModuleID else { return }
        let moduleIDs = orderedModules.map(\.id)
        guard
            let fromIndex = moduleIDs.firstIndex(of: moduleID),
            let targetIndex = moduleIDs.firstIndex(of: targetModuleID)
        else {
            return
        }

        var reordered = moduleIDs
        let movedID = reordered.remove(at: fromIndex)
        let adjustedTargetIndex = reordered.firstIndex(of: targetModuleID) ?? max(targetIndex - (fromIndex < targetIndex ? 1 : 0), 0)
        reordered.insert(movedID, at: adjustedTargetIndex)

        for (position, moduleID) in reordered.enumerated() {
            if let index = layout.firstIndex(where: { $0.kind == .module && $0.moduleID == moduleID }) {
                layout[index].position = position + 1
            }
        }

        layout.sort { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.id < rhs.id
            }
            return lhs.position < rhs.position
        }
        persistState()
    }

    func reorderModuleIDs(_ moduleIDs: [Int]) {
        let validIDs = Set(orderedModules.map(\.id))
        let reordered = moduleIDs.filter { validIDs.contains($0) }
        guard !reordered.isEmpty else { return }

        for (position, moduleID) in reordered.enumerated() {
            if let index = layout.firstIndex(where: { $0.kind == .module && $0.moduleID == moduleID }) {
                layout[index].position = position + 1
            }
        }

        layout.sort { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.id < rhs.id
            }
            return lhs.position < rhs.position
        }
        persistState()
    }

    func cpuCoreIndices(kind: CPUCoreKind) -> [Int] {
        availableCPUCoreDescriptors
            .filter { $0.kind == kind }
            .map(\.index)
    }

    func cpuCoreKind(for index: Int) -> CPUCoreKind {
        availableCPUCoreDescriptors.first(where: { $0.index == index })?.kind ?? .unknown
    }

    func assignMemoryUsage(for entry: RegistryEntry, channelIndex: Int) {
        guard entry.moduleType == .radiance else { return }
        updateBinding(
            for: entry.id,
            binding: ChannelBinding(channelIndex: channelIndex, metric: MetricBinding(kind: .memoryUsage))
        )
    }

    func assignCPUCores(_ coreIndices: [Int], for entry: RegistryEntry, channelIndex: Int) {
        guard entry.moduleType == .radiance else { return }
        let resolved = Array(Set(coreIndices)).sorted()
        updateBinding(
            for: entry.id,
            binding: ChannelBinding(channelIndex: channelIndex, metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: resolved))
        )
    }

    func assignMetricKind(_ metricKind: MetricSourceKind, for entry: RegistryEntry, channelIndex: Int) {
        guard MetricSourceKind.options(for: entry.moduleType).contains(metricKind) else { return }
        let current = binding(for: entry, channelIndex: channelIndex).metric
        updateBinding(
            for: entry.id,
            binding: ChannelBinding(
                channelIndex: channelIndex,
                metric: MetricBinding(
                    kind: metricKind,
                    userAssigned: true,
                    scalePoints: current.scalePoints,
                    dialSVGPath: current.dialSVGPath,
                    dialSVGMarkup: current.dialSVGMarkup
                )
            )
        )
    }

    func removeAssignedBalanceMetricToken(_ tokenID: String, for entry: RegistryEntry, channelIndex: Int) {
        guard
            entry.moduleType == .balance,
            let kind = balanceMetricKind(for: tokenID),
            binding(for: entry, channelIndex: channelIndex).metric.kind == kind
        else {
            return
        }

        updateBinding(
            for: entry.id,
            binding: ChannelBinding(
                channelIndex: channelIndex,
                metric: MetricBinding(
                    kind: .none,
                    scalePoints: binding(for: entry, channelIndex: channelIndex).metric.scalePoints,
                    dialSVGPath: binding(for: entry, channelIndex: channelIndex).metric.dialSVGPath,
                    dialSVGMarkup: binding(for: entry, channelIndex: channelIndex).metric.dialSVGMarkup
                )
            )
        )
    }

    private func balanceMetricKind(for tokenID: String) -> MetricSourceKind? {
        switch tokenID {
        case "network-up":
            return .networkUp
        case "network-down":
            return .networkDown
        case "disk-read":
            return .diskRead
        case "disk-write":
            return .diskWrite
        default:
            return nil
        }
    }

    func scheduleModuleActionMessageDismiss(for message: String?, after delay: Duration = .seconds(3)) {
        moduleActionDismissTask?.cancel()
        guard let message else { return }

        moduleActionDismissTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }

            await MainActor.run {
                guard let self else { return }
                if self.moduleActionNotice == message || self.moduleActionIssue == message {
                    self.moduleActionNotice = nil
                    self.moduleActionIssue = nil
                }
            }
        }
    }

    func importBalanceGaugeSettings(for entry: RegistryEntry, channelIndex: Int) {
        guard entry.moduleType == .balance else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.message = "选择仪表盘 JSON 设置"

        guard panel.runModal() == .OK, let jsonURL = panel.url else {
            return
        }

        moduleActionNotice = nil
        moduleActionIssue = nil
        let export: GaugeExport
        do {
            export = try Self.withSecurityScopedAccess(to: jsonURL) {
                let data = try Data(contentsOf: jsonURL)
                return try JSONDecoder().decode(GaugeExport.self, from: data)
            }
        } catch {
            moduleActionIssue = "导入失败：JSON 不合法或没有读取权限。\(error.localizedDescription)"
            return
        }

        let scalePoints = export.state.majorTicks
            .compactMap { tick -> MetricScalePoint? in
                guard let value = Self.rateValue(from: tick.valueText, unitText: tick.unitText) else {
                    return nil
                }
                return MetricScalePoint(
                    value: value,
                    percent: tick.percent / 100.0,
                    label: "\(tick.valueText)\(tick.unitText)"
                )
            }
            .sorted { $0.value < $1.value }

        guard !scalePoints.isEmpty else {
            moduleActionIssue = "导入失败：JSON 中没有可用的刻度映射。"
            return
        }

        var metric = binding(for: entry, channelIndex: channelIndex).metric
        var svgURL: URL?
        var svgMarkup: String?
        var svgReadError: Error?
        for candidateURL in Self.candidateDialSVGURLs(for: metric.kind, nextTo: jsonURL) {
            do {
                svgMarkup = try Self.readSecurityScopedText(from: candidateURL)
                svgURL = candidateURL
                break
            } catch {
                svgReadError = error
            }
        }

        if svgMarkup == nil {
            guard let selectedSVGURL = Self.promptForGaugeSVG(nextTo: jsonURL, metricKind: metric.kind) else {
                if let svgReadError {
                    moduleActionIssue = "导入失败：SVG 图片没有读取权限。\(svgReadError.localizedDescription)"
                } else {
                    moduleActionIssue = "导入失败：没有找到同名 SVG，或当前指标对应的 SVG。"
                }
                return
            }

            do {
                svgMarkup = try Self.readSecurityScopedText(from: selectedSVGURL)
                svgURL = selectedSVGURL
            } catch {
                moduleActionIssue = "导入失败：SVG 图片无法读取。\(error.localizedDescription)"
                return
            }
        }

        metric.scalePoints = scalePoints
        metric.dialSVGPath = svgURL?.path
        metric.dialSVGMarkup = svgMarkup
        updateBinding(for: entry.id, binding: ChannelBinding(channelIndex: channelIndex, metric: metric))
        moduleActionNotice = "仪表设置导入成功"
    }

    func removeAssignedMetricToken(_ tokenID: String, for entry: RegistryEntry, channelIndex: Int) {
        guard entry.moduleType == .radiance else { return }
        let current = binding(for: entry, channelIndex: channelIndex).metric

        if tokenID == "memory", current.kind == .memoryUsage {
            assignCPUCores([], for: entry, channelIndex: channelIndex)
            return
        }

        if tokenID == "all-efficiency" {
            let remaining = Set(current.coreIndices).subtracting(cpuCoreIndices(kind: .efficiency))
            assignCPUCores(Array(remaining).sorted(), for: entry, channelIndex: channelIndex)
            return
        }

        if tokenID == "all-performance" {
            let remaining = Set(current.coreIndices).subtracting(cpuCoreIndices(kind: .performance))
            assignCPUCores(Array(remaining).sorted(), for: entry, channelIndex: channelIndex)
            return
        }

        guard tokenID.hasPrefix("cpu-"),
              let coreIndex = Int(tokenID.replacingOccurrences(of: "cpu-", with: ""))
        else {
            return
        }

        let remaining = current.coreIndices.filter { $0 != coreIndex }
        assignCPUCores(remaining, for: entry, channelIndex: channelIndex)
    }

    func isLocatingChannel(for entry: RegistryEntry, channelIndex: Int) -> Bool {
        locatingChannelKey == channelActionKey(moduleID: entry.id, channelIndex: channelIndex)
    }

    func isStartingCalibration(for entry: RegistryEntry, channelIndex: Int) -> Bool {
        pendingCalibrationStartKey == channelActionKey(moduleID: entry.id, channelIndex: channelIndex)
    }

    func locateChannel(for entry: RegistryEntry, channelIndex: Int) {
        locatePreviewTask?.cancel()
        calibrationStartTask?.cancel()

        guard let endpoint = activeEndpoint, sourceIsOnline else {
            moduleActionIssue = "当前没有可用的 ORB 连接，无法寻找这个通道。"
            return
        }

        let actionKey = channelActionKey(moduleID: entry.id, channelIndex: channelIndex)
        locatingChannelKey = actionKey
        moduleActionIssue = nil

        let targetCode = Int((0.5 * 4095.0).rounded())
        locatePreviewTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.requestPreviewActivation(
                    mode: .locate,
                    moduleID: entry.id,
                    channelIndex: channelIndex,
                    targetCode: targetCode,
                    endpoint: endpoint
                )
                try? await Task.sleep(nanoseconds: 120_000_000)
                _ = try? await self.session.activatePreview(
                    mode: .locate,
                    moduleID: entry.id,
                    channelIndex: channelIndex,
                    targetCode: targetCode,
                    endpoint: endpoint
                )
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        return
                    }
                    self.moduleActionIssue = "寻找通道失败：\(error.localizedDescription)"
                }
            }

            await MainActor.run {
                if self.locatingChannelKey == actionKey {
                    self.locatingChannelKey = nil
                }
                self.sendCurrentOutputsIfPossible()
            }
        }
    }

    func unknownDeviceCaption(for address: Int) -> String {
        switch flowForUnknownDevice(address) {
        case .registerToNewAddress:
            return "点击分配类型、ID 和新地址"
        case .resetBeforeRegister:
            return "该设备已绑定其它主机，点击先重置"
        case .registerAsFinalSlot:
            return "点击分配最后一个槽位（ID 0）"
        }
    }

    func binding(for entry: RegistryEntry, channelIndex: Int) -> ChannelBinding {
        selectedModuleSetting(for: entry)?.binding(for: channelIndex)
            ?? ModuleSetting.default(for: entry).binding(for: channelIndex)
            ?? ChannelBinding(channelIndex: channelIndex, metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: [0]))
    }

    func updateMetricKind(
        for entry: RegistryEntry,
        channelIndex: Int,
        metricKind: MetricSourceKind
    ) {
        guard MetricSourceKind.options(for: entry.moduleType).contains(metricKind) else {
            return
        }

        let coreIndices: [Int]
        switch metricKind {
        case .cpuCore, .cpuCoreAverage:
            let current = binding(for: entry, channelIndex: channelIndex).metric.coreIndices
            coreIndices = current.isEmpty ? [0] : current
        default:
            coreIndices = []
        }

        updateBinding(
            for: entry.id,
            binding: ChannelBinding(channelIndex: channelIndex, metric: MetricBinding(kind: metricKind, coreIndices: coreIndices))
        )
    }

    func toggleCPUCoreSelection(
        for entry: RegistryEntry,
        channelIndex: Int,
        coreIndex: Int
    ) {
        var binding = binding(for: entry, channelIndex: channelIndex)
        var indices = Set(resolvedCPUCoreSelection(for: binding.metric))

        if indices.contains(coreIndex) {
            if indices.count > 1 {
                indices.remove(coreIndex)
            }
        } else {
            indices.insert(coreIndex)
        }

        binding.metric = MetricBinding(kind: .cpuCoreAverage, coreIndices: Array(indices).sorted())
        updateBinding(for: entry.id, binding: binding)
    }

    func selectAllCPUCores(
        for entry: RegistryEntry,
        channelIndex: Int
    ) {
        let binding = ChannelBinding(
            channelIndex: channelIndex,
            metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: availableCPUCoreIndices)
        )
        updateBinding(for: entry.id, binding: binding)
    }

    func clearCPUCoreSelection(
        for entry: RegistryEntry,
        channelIndex: Int
    ) {
        let binding = ChannelBinding(
            channelIndex: channelIndex,
            metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: [])
        )
        updateBinding(for: entry.id, binding: binding)
    }

    func isCPUCoreSelected(
        for entry: RegistryEntry,
        channelIndex: Int,
        coreIndex: Int
    ) -> Bool {
        resolvedCPUCoreSelection(for: binding(for: entry, channelIndex: channelIndex).metric).contains(coreIndex)
    }

    func debugInfo(for entry: RegistryEntry, channelIndex: Int) -> MetricDebugInfo {
        let binding = binding(for: entry, channelIndex: channelIndex)
        let lut = calibrationLUT(for: entry, channelIndex: channelIndex)
        let normalized = normalizedValue(for: binding.metric, snapshot: systemMetrics)
        let preLUTCode = Int((normalized * 4095).rounded())
        let postLUTCode = LUTMapper.map(normalizedValue: normalized, with: lut)

        switch binding.metric.kind {
        case .none:
            return MetricDebugInfo(
                sampleText: "未分配",
                mappedPercent: 0,
                preLUTCode: 0,
                postLUTCode: 0
            )
        case .networkUp:
            return MetricDebugInfo(
                sampleText: debugRateText(systemMetrics.networkSendBytesPerSecond),
                mappedPercent: normalized * 100.0,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        case .networkDown:
            return MetricDebugInfo(
                sampleText: debugRateText(systemMetrics.networkReceiveBytesPerSecond),
                mappedPercent: normalized * 100.0,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        case .diskRead:
            return MetricDebugInfo(
                sampleText: debugRateText(systemMetrics.diskReadBytesPerSecond),
                mappedPercent: normalized * 100.0,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        case .diskWrite:
            return MetricDebugInfo(
                sampleText: debugRateText(systemMetrics.diskWriteBytesPerSecond),
                mappedPercent: normalized * 100.0,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        case .memoryUsage:
            return MetricDebugInfo(
                sampleText: "\(debugPercentText(systemMetrics.memoryUsagePercent)) · \(debugMemoryText())",
                mappedPercent: normalized * 100.0,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        default:
            let percent = normalized * 100.0
            return MetricDebugInfo(
                sampleText: debugPercentText(percent),
                mappedPercent: percent,
                preLUTCode: preLUTCode,
                postLUTCode: postLUTCode
            )
        }
    }

    func simulatedOutputPercent(for entry: RegistryEntry, channelIndex: Int) -> Double {
        guard isEntryOnline(entry) else { return 0 }
        if let draft = activeCalibration,
           draft.moduleID == entry.id,
           draft.channelIndex == channelIndex {
            return min(max(draft.currentStep.input, 0), 1)
        }
        let binding = binding(for: entry, channelIndex: channelIndex)
        guard shouldSendOutput(for: binding.metric) else { return 0 }
        return min(max(normalizedValue(for: binding.metric, snapshot: systemMetrics), 0), 1)
    }

    func isCalibratingChannel(for entry: RegistryEntry, channelIndex: Int) -> Bool {
        guard let draft = activeCalibration else { return false }
        return draft.moduleID == entry.id && draft.channelIndex == channelIndex
    }

    func setFirmwareUploadURL(_ url: URL) {
        selectedFirmwareUploadURL = url
        firmwareUploadIssue = nil
        firmwareUploadNotice = nil
    }

    func setFirmwareUploadSelectionError(_ message: String) {
        firmwareUploadIssue = message
    }

    func uploadFirmware() {
        firmwareUploadTask?.cancel()

        guard let endpoint = activeEndpoint, sourceIsOnline else {
            firmwareUploadIssue = "当前没有可用的 ORB 连接，无法通过 Wi‑Fi 刷固件。"
            return
        }

        guard let fileURL = selectedFirmwareUploadURL else {
            firmwareUploadIssue = "请先选择一个 .bin 固件文件。"
            return
        }

        isUploadingFirmware = true
        firmwareUploadIssue = nil
        firmwareUploadNotice = nil

        firmwareUploadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.session.uploadFirmware(fileURL: fileURL, endpoint: endpoint)
                await MainActor.run {
                    self.isUploadingFirmware = false
                    self.selectedFirmwareUploadURL = nil
                    self.firmwareUploadNotice = response.message ?? "固件上传成功，主控正在重启。"
                    self.lastDeviceContactAt = nil
                    self.latestHeartbeat = nil
                    self.updateConnectionStatus()
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self.reconnect()
                }
            } catch {
                await MainActor.run {
                    self.isUploadingFirmware = false
                    self.firmwareUploadIssue = "OTA 刷固件失败：\(error.localizedDescription)"
                    NSLog("ORB App：OTA 刷固件失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func isEntryOnline(_ entry: RegistryEntry) -> Bool {
        sourceIsOnline && entry.present
    }

    func statusText(for entry: RegistryEntry) -> String {
        if !sourceIsOnline {
            return "随源离线"
        }
        return entry.present ? "在线" : "离线"
    }

    func smoothingConfig(for moduleType: ModuleType) -> SmoothingConfig {
        confirmedMotionProfiles().config(for: moduleType)
    }

    func motionDraftConfig(for moduleType: ModuleType) -> SmoothingConfig {
        resolvedMotionDraftProfiles().config(for: moduleType)
    }

    func updateMotionDraftDurationFactor(_ value: Double) {
        motionDraftDurationFactor = value
        noteMotionDraftChanged()
    }

    func updateSmoothingAMax(for moduleType: ModuleType, value: Double) {
        var config = motionDraftConfig(for: moduleType)
        config.aMax = value
        updateMotionDraftConfig(config, for: moduleType)
    }

    func updateSmoothingVMax(for moduleType: ModuleType, value: Double) {
        var config = motionDraftConfig(for: moduleType)
        config.vMax = value
        updateMotionDraftConfig(config, for: moduleType)
    }

    func updateJitterFrequency(for moduleType: ModuleType, value: Double) {
        var config = motionDraftConfig(for: moduleType)
        config.jitterFrequencyHz = value
        updateMotionDraftConfig(config, for: moduleType)
    }

    func updateJitterAmplitude(for moduleType: ModuleType, value: Double) {
        var config = motionDraftConfig(for: moduleType)
        config.jitterAmplitude = value
        updateMotionDraftConfig(config, for: moduleType)
    }

    func updateJitterDispersion(for moduleType: ModuleType, value: Double) {
        var config = motionDraftConfig(for: moduleType)
        config.jitterDispersion = value
        updateMotionDraftConfig(config, for: moduleType)
    }

    func resetMotionDraftToDefaults() {
        motionDraftProfiles = DeviceSmoothingProfiles()
        motionDraftDurationFactor = 0.7
        noteMotionDraftChanged()
    }

    func applyMotionSettings() {
        guard !isApplyingMotionSettings else { return }
        guard let endpoint = activeEndpoint, sourceIsOnline else {
            smoothingActionIssue = "当前主控离线，无法确认并下发运动参数。"
            return
        }
        guard hasPendingMotionChanges else { return }

        let desiredProfiles = resolvedMotionDraftProfiles()
        let desiredFactor = motionDraftDurationFactor

        smoothingActionIssue = nil
        clearMotionApplySuccessNotice()
        isApplyingMotionSettings = true

        Task { [weak self] in
            guard let self else { return }

            do {
                let radianceState = try await self.session.updateSmoothing(
                    moduleType: .radiance,
                    config: desiredProfiles.radiance,
                    endpoint: endpoint
                )
                try Self.validateMotionAck(
                    expected: desiredProfiles.radiance,
                    actual: radianceState.smoothing.radiance,
                    moduleType: .radiance
                )

                let finalState = try await self.session.updateSmoothing(
                    moduleType: .balance,
                    config: desiredProfiles.balance,
                    endpoint: endpoint
                )
                try Self.validateMotionAck(
                    expected: desiredProfiles.radiance,
                    actual: finalState.smoothing.radiance,
                    moduleType: .radiance
                )
                try Self.validateMotionAck(
                    expected: desiredProfiles.balance,
                    actual: finalState.smoothing.balance,
                    moduleType: .balance
                )

                await MainActor.run {
                    self.motionDurationFactor = desiredFactor
                    self.hasLocalMotionDraftEdits = false
                    self.isApplyingMotionSettings = false
                    self.smoothingActionIssue = nil
                    self.applyLoadedState(finalState, preserveSelection: true)
                    self.presentMotionApplySuccessNotice()
                    NSLog("ORB App：运动参数确认成功")
                }
            } catch {
                await MainActor.run {
                    self.isApplyingMotionSettings = false
                    self.smoothingActionIssue = "参数确认失败：\(error.localizedDescription)"
                    NSLog("ORB App：运动参数确认失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func calibrationStatusText(for entry: RegistryEntry, channelIndex: Int) -> String {
        guard let lut = calibrationLUTs.first(where: { $0.moduleID == entry.id && $0.channelIndex == channelIndex }) else {
            return "当前使用默认 LUT"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "自定义 LUT 已保存于 \(formatter.string(from: lut.updatedAt))"
    }

    func calibrationInstructionText(for draft: CalibrationDraft) -> String {
        switch draft.moduleType {
        case .radiance:
            switch Int((draft.currentStep.input * 100).rounded()) {
            case 0:
                return "拖动滑块，让绿色荧光刚好出现在荧光屏上。"
            case 50:
                return "拖动滑块，让荧光出现在 50% 的位置。"
            case 25:
                return "拖动滑块，让荧光出现在 25% 的位置。"
            case 100:
                return "拖动滑块，让绿色荧光刚好占满整个荧光屏，但不要出现重叠。"
            case 75:
                return "拖动滑块，让荧光出现在 75% 的位置。"
            default:
                return "拖动滑块，让荧光到达当前目标位置。"
            }
        case .balance:
            return "拖动滑块，让指针到达 \(calibrationStepDisplayLabel(for: draft)) 对应的大刻度位置。"
        case .unknown:
            return "拖动滑块，让模块到达当前目标位置。"
        }
    }

    func calibrationStepDisplayLabel(for draft: CalibrationDraft) -> String {
        guard draft.moduleType == .balance,
              let metric = calibrationMetricBinding(for: draft),
              let point = metric.scalePoints.first(where: { abs($0.percent - draft.currentStep.input) < 0.0001 })
        else {
            return "\(Int((draft.currentStep.input * 100).rounded()))%"
        }
        return point.label ?? debugRateText(point.value)
    }

    func calibrationMetricBinding(for draft: CalibrationDraft) -> MetricBinding? {
        moduleSettings
            .first(where: { $0.moduleID == draft.moduleID })?
            .channelBindings
            .first(where: { $0.channelIndex == draft.channelIndex })?
            .metric
    }

    func beginCalibration(for entry: RegistryEntry, channelIndex: Int) {
        moduleActionIssue = nil
        locatePreviewTask?.cancel()
        calibrationStartTask?.cancel()
        locatingChannelKey = nil

        guard let endpoint = activeEndpoint, sourceIsOnline else {
            moduleActionIssue = "当前没有可用的 ORB 连接，无法启动校准。"
            return
        }

        let existingLUT = calibrationLUT(for: entry, channelIndex: channelIndex)
        let metric = binding(for: entry, channelIndex: channelIndex).metric
        let draft = CalibrationDraft(
            moduleID: entry.id,
            moduleType: entry.moduleType,
            channelIndex: channelIndex,
            points: orderedCalibrationPoints(for: entry.moduleType, metric: metric, existingLUT: existingLUT),
            stepIndex: 0
        )
        let actionKey = channelActionKey(moduleID: draft.moduleID, channelIndex: draft.channelIndex)
        pendingCalibrationStartKey = actionKey

        let initialCode = Int((min(max(draft.currentStep.output, 0), 1) * 4095).rounded())
        calibrationStartTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await self.requestPreviewActivation(
                    mode: .calibration,
                    moduleID: draft.moduleID,
                    channelIndex: draft.channelIndex,
                    targetCode: initialCode,
                    endpoint: endpoint
                )

                await MainActor.run {
                    if self.pendingCalibrationStartKey == actionKey {
                        self.pendingCalibrationStartKey = nil
                    }
                    self.activeCalibration = draft
                    self.previewActiveCalibration()
                }
            } catch {
                await MainActor.run {
                    if self.pendingCalibrationStartKey == actionKey {
                        self.pendingCalibrationStartKey = nil
                    }
                    if !Task.isCancelled {
                        self.moduleActionIssue = "校准启动失败：\(error.localizedDescription)"
                    }
                    self.sendCurrentOutputsIfPossible()
                }
            }
        }
    }

    func dismissCalibration() {
        calibrationPreviewTask?.cancel()
        calibrationStartTask?.cancel()
        activeCalibration = nil
        moduleActionIssue = nil
        pendingCalibrationStartKey = nil
        sendCurrentOutputsIfPossible()
    }

    func updateActiveCalibrationOutput(_ output: Double) {
        guard var draft = activeCalibration else { return }
        draft.points[draft.stepIndex].output = min(max(output, 0), 1)
        activeCalibration = draft
        previewActiveCalibration()
    }

    func moveCalibrationStep(by offset: Int) {
        guard var draft = activeCalibration else { return }
        let nextIndex = min(max(draft.stepIndex + offset, 0), draft.points.count - 1)
        guard nextIndex != draft.stepIndex else { return }
        draft.stepIndex = nextIndex
        activeCalibration = draft
        previewActiveCalibration()
    }

    func saveActiveCalibration() {
        guard let draft = activeCalibration else { return }
        guard let endpoint = activeEndpoint else {
            moduleActionIssue = "当前没有可用的 ORB 连接，无法保存校准结果。"
            return
        }

        moduleActionIssue = nil
        pendingCalibrationStartKey = nil
        let sortedPoints = draft.points.sorted { $0.input < $1.input }

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.saveCalibrationLUT(
                    moduleID: draft.moduleID,
                    channelIndex: draft.channelIndex,
                    points: sortedPoints,
                    endpoint: endpoint
                )
                await MainActor.run {
                    self.upsertCalibrationLUT(
                        CalibrationLUT(
                            moduleID: draft.moduleID,
                            channelIndex: draft.channelIndex,
                            points: sortedPoints,
                            updatedAt: .now
                        )
                    )
                    self.calibrationPreviewTask?.cancel()
                    self.activeCalibration = nil
                    self.applyLoadedState(state, preserveSelection: true)
                    self.persistState()
                    self.sendCurrentOutputsIfPossible()
                }
            } catch {
                await MainActor.run {
                    self.moduleActionIssue = "保存校准失败：\(error.localizedDescription)"
                    NSLog("ORB App：保存校准失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func deleteSelectedModule() {
        guard let entry = selectedEntry else { return }
        guard let endpoint = activeEndpoint else {
            moduleActionIssue = "当前没有可用的 ORB 连接，无法删除这个模块。"
            return
        }

        moduleActionIssue = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.deleteModule(id: entry.id, endpoint: endpoint)
                await MainActor.run {
                    self.moduleSettings.removeAll { $0.moduleID == entry.id }
                    self.calibrationLUTs.removeAll { $0.moduleID == entry.id }
                    self.applyLoadedState(state, preserveSelection: false)
                    self.selectedModuleID = self.orderedModules.first?.id
                    self.persistState()
                }
            } catch {
                await MainActor.run {
                    self.moduleActionIssue = "删除失败：\(error.localizedDescription)"
                    NSLog("ORB App：删除模块失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func selectedUnknownDeviceNeedsReset() -> Bool {
        guard let selectedUnknownAddress else { return false }
        return flowForUnknownDevice(selectedUnknownAddress) == .resetBeforeRegister
    }

    func validRegistrationIDs(for address: Int) -> [Int] {
        switch flowForUnknownDevice(address) {
        case .registerToNewAddress:
            return availableFirstSevenIDs()
        case .registerAsFinalSlot:
            return isReservedSlotAvailable ? [8] : []
        case .resetBeforeRegister:
            return []
        }
    }

    func registrationTargetLabel(for id: Int) -> String {
        if id == 8 {
            return "ID 0（保留地址 0x60）"
        }

        return "ID \(slotLabel(for: id)) -> \(rawAddressLabel(addressForModuleID(id) ?? 0))"
    }

    func registerSelectedUnknownDevice() {
        guard
            let selectedUnknownAddress,
            let endpoint = activeEndpoint
        else {
            unknownDeviceIssue = "当前没有可用的 ORB 连接，无法注册新设备。"
            return
        }

        let validIDs = validRegistrationIDs(for: selectedUnknownAddress)
        let resolvedID = pendingUnknownModuleID ?? validIDs.first
        guard let resolvedID, validIDs.contains(resolvedID) else {
            unknownDeviceIssue = "当前没有可用的槽位可以分配给这个新设备。"
            return
        }

        isPerformingUnknownDeviceAction = true
        unknownDeviceIssue = nil
        unknownDeviceNotice = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.registerModule(
                    type: self.pendingUnknownModuleType,
                    id: resolvedID,
                    address: selectedUnknownAddress,
                    endpoint: endpoint
                )

                await MainActor.run {
                    self.isPerformingUnknownDeviceAction = false
                    self.applyLoadedState(state, preserveSelection: false)
                    self.selectedUnknownAddress = nil
                    self.selectedModuleID = resolvedID
                    self.pendingUnknownModuleID = nil
                    self.unknownDeviceNotice = nil
                    self.unknownDeviceIssue = nil
                }
            } catch {
                await MainActor.run {
                    self.isPerformingUnknownDeviceAction = false
                    self.unknownDeviceIssue = "注册失败：\(error.localizedDescription)"
                    NSLog("ORB App：注册新设备失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    func resetSelectedUnknownDevice() {
        guard
            let selectedUnknownAddress,
            let endpoint = activeEndpoint
        else {
            unknownDeviceIssue = "当前没有可用的 ORB 连接，无法重置这个设备。"
            return
        }

        guard selectedUnknownAddress != 0x60 else {
            unknownDeviceIssue = "这个设备已经在 0x60，不需要重置。"
            return
        }

        isPerformingUnknownDeviceAction = true
        unknownDeviceIssue = nil
        unknownDeviceNotice = nil

        Task { [weak self] in
            guard let self else { return }

            do {
                let state = try await self.session.resetUnknownDevice(
                    address: selectedUnknownAddress,
                    endpoint: endpoint
                )

                await MainActor.run {
                    self.isPerformingUnknownDeviceAction = false
                    self.applyLoadedState(state, preserveSelection: true)
                    if state.unknownI2CAddresses?.contains(0x60) == true {
                        self.selectedUnknownAddress = 0x60
                        self.pendingUnknownModuleID = self.suggestedRegistrationID(for: 0x60)
                        self.unknownDeviceNotice = "重置成功，设备已恢复到 0x60。请继续选择类型并分配新 ID。"
                    } else {
                        self.selectedUnknownAddress = nil
                        self.unknownDeviceNotice = "重置完成，但没有在 0x60 看到新设备，请检查硬件后重试。"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isPerformingUnknownDeviceAction = false
                    self.unknownDeviceIssue = "重置失败：\(error.localizedDescription)"
                    NSLog("ORB App：重置旧绑定设备失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    private func connect(to serviceName: String) {
        autoConnectName = serviceName
        NSLog("ORB App：开始连接服务 %@", serviceName)

        Task { [weak self] in
            guard let self else { return }

            do {
                let endpoint = try await self.discoveryService.resolve(serviceNamed: serviceName)
                await MainActor.run {
                    self.activeEndpoint = endpoint
                    NSLog("ORB App：服务 %@ 已解析为 %@:%ld", serviceName, endpoint.host, endpoint.port)
                }
                await self.loadState(from: endpoint, preserveSelection: false)
            } catch {
                await MainActor.run {
                    NSLog("ORB App：连接服务 %@ 失败，原因：%@", serviceName, error.localizedDescription)
                    self.activeEndpoint = nil
                    self.autoConnectName = nil
                    self.updateConnectionStatus()
                }
            }
        }
    }

    private func loadState(from endpoint: ORBEndpoint, preserveSelection: Bool) async {
        do {
            let state = try await session.fetchState(from: endpoint)
            await MainActor.run {
                self.localNetworkAccessIssue = nil
                self.activeEndpoint = endpoint
                self.applyLoadedState(state, preserveSelection: preserveSelection)
                self.requestHeartbeatRoutingSyncIfPossible()
            }
        } catch {
            await MainActor.run {
                NSLog("ORB App：拉取设备状态失败，原因：%@", error.localizedDescription)
                self.noteNetworkAccessFailure(error)
                self.autoConnectName = nil
                self.updateConnectionStatus()
            }
        }
    }

    private func applyLoadedState(_ state: ORBDeviceState, preserveSelection: Bool) {
        NSLog("ORB App：已获取设备状态 %@，IP=%@", state.deviceName, state.ip)
        let shouldKeepSourceSelection = preserveSelection && selectedModuleID == nil && selectedUnknownAddress == nil && !showingMaintenanceScreen
        activeEndpoint = ORBEndpoint(host: state.ip, port: activeEndpoint?.port ?? 80)
        deviceState = state
        calibrationLUTs = Self.expandedCalibrationLUTs(from: state.calibrationLUTs ?? calibrationLUTs)
        lastDeviceContactAt = .now
        lastAppliedStateRevision = state.stateRevision
        lastLivenessProbeAt = .now
        moduleActionIssue = nil
        smoothingActionIssue = nil
        let registeredModules = state.registeredModules
        ensureModuleSettings(for: registeredModules)
        mergeLayout(with: registeredModules)
        let unknownAddresses = (state.unknownI2CAddresses ?? []).sorted()

        if let selectedUnknownAddress,
           !unknownAddresses.contains(selectedUnknownAddress) {
            self.selectedUnknownAddress = nil
            pendingUnknownModuleID = nil
            clearUnknownDeviceFeedback()
        } else if let selectedUnknownAddress {
            pendingUnknownModuleID = suggestedRegistrationID(for: selectedUnknownAddress)
        }

        if selectedUnknownAddress == nil, !unknownAddresses.isEmpty {
            selectedModuleID = nil
            showingMaintenanceScreen = false
        } else if preserveSelection && showingMaintenanceScreen {
            selectedUnknownAddress = nil
            pendingUnknownModuleID = nil
            selectedModuleID = nil
            showingMaintenanceScreen = true
        } else if !shouldKeepSourceSelection && selectedUnknownAddress == nil && (!preserveSelection || selectedModuleID == nil) {
            selectedModuleID = orderedModules.first?.id
        }

        ensureI2CDebugSelection()
        autoConnectName = nil
        updateConnectionStatus()
        syncMotionDraftFromConfirmedState()
        persistState()
    }

    private func flowForUnknownDevice(_ address: Int) -> UnknownDeviceFlow {
        if !availableFirstSevenIDs().isEmpty {
            return .registerToNewAddress
        }

        if isReservedSlotAvailable {
            return .registerAsFinalSlot
        }

        return address == 0x60 ? .registerAsFinalSlot : .resetBeforeRegister
    }

    private func availableFirstSevenIDs() -> [Int] {
        let occupied = Set(registeredModules.map(\.id))
        return (1...7).filter { !occupied.contains($0) }
    }

    private var isReservedSlotAvailable: Bool {
        !registeredModules.contains(where: { $0.id == 8 })
    }

    private func suggestedRegistrationID(for address: Int) -> Int? {
        let validIDs = validRegistrationIDs(for: address)
        if address == 0x60, validIDs.contains(8), availableFirstSevenIDs().isEmpty {
            return 8
        }
        return validIDs.first
    }

    private func clearUnknownDeviceFeedback() {
        unknownDeviceNotice = nil
        unknownDeviceIssue = nil
    }

    private func preferredServiceNameForReconnect() -> String? {
        let targetName = deviceState?.deviceName ?? latestHeartbeat?.deviceName ?? autoConnectName
        guard let targetName else { return nil }
        return discoveredServices.contains(where: { $0.name == targetName }) ? targetName : nil
    }

    private func restartMetricsSampling() {
        metricsTask?.cancel()

        let interval = max(refreshInterval, 0.25)
        metricsTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let snapshot = await self.metricsService.sample()
                let transmission = await MainActor.run { () -> (ORBEndpoint, OutputFrame)? in
                    self.systemMetrics = snapshot
                    return self.buildOutputFrameIfReady(snapshot: snapshot)
                }

                if let transmission {
                    do {
                        try await self.session.sendOutputs(transmission.1, endpoint: transmission.0)
                        await MainActor.run {
                            self.noteDeviceContact(endpoint: transmission.0)
                        }
                    } catch {
                        await MainActor.run {
                            NSLog("ORB App：发送输出帧失败，原因：%@", error.localizedDescription)
                        }
                    }
                }

                let nanoseconds = UInt64(interval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
            }
        }
    }

    private func ensureModuleSettings(for modules: [RegistryEntry]) {
        moduleSettings = Self.clearingLegacyBalanceDefaults(in: moduleSettings)
        let existingIDs = Set(moduleSettings.map(\.moduleID))
        let defaults = modules
            .filter { !existingIDs.contains($0.id) }
            .map { ModuleSetting.default(for: $0) }

        moduleSettings.append(contentsOf: defaults)
        let validIDs = Set(modules.map(\.id))
        moduleSettings.removeAll { !validIDs.contains($0.moduleID) }
        moduleSettings.sort { $0.moduleID < $1.moduleID }
    }

    private static func clearingLegacyBalanceDefaults(in settings: [ModuleSetting]) -> [ModuleSetting] {
        settings.map { setting in
            guard setting.moduleType == .balance else {
                return setting
            }

            let bindings = setting.channelBindings.sorted { $0.channelIndex < $1.channelIndex }
            guard
                bindings.count == 2,
                bindings[0].channelIndex == 0,
                bindings[0].metric.kind == .networkDown,
                !bindings[0].metric.userAssigned,
                bindings[1].channelIndex == 1,
                bindings[1].metric.kind == .networkUp,
                !bindings[1].metric.userAssigned
            else {
                return setting
            }

            return ModuleSetting.default(for: RegistryEntry(
                id: setting.moduleID,
                registered: true,
                present: true,
                moduleType: .balance
            ))
        }
    }

    private static func rateValue(from valueText: String, unitText: String) -> Double? {
        let normalizedValue = valueText
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(normalizedValue) else {
            return nil
        }

        switch unitText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "", "b", "byte", "bytes":
            return value
        case "k", "kb":
            return value * 1_024
        case "m", "mb":
            return value * 1_024 * 1_024
        case "g", "gb":
            return value * 1_024 * 1_024 * 1_024
        default:
            return value
        }
    }

    private static func withSecurityScopedAccess<T>(to url: URL, _ work: () throws -> T) rethrows -> T {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try work()
    }

    private static func readSecurityScopedText(from url: URL) throws -> String {
        try withSecurityScopedAccess(to: url) {
            try String(contentsOf: url, encoding: .utf8)
        }
    }

    private static func candidateDialSVGURLs(for kind: MetricSourceKind, nextTo jsonURL: URL) -> [URL] {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        let sameNameURL = jsonURL
            .deletingPathExtension()
            .appendingPathExtension("svg")
        candidates.append(sameNameURL)

        if let filename = dialSVGFilename(for: kind) {
            candidates.append(
                jsonURL
                    .deletingLastPathComponent()
                    .appendingPathComponent(filename)
            )
        }

        let directoryURL = jsonURL.deletingLastPathComponent()
        let svgFiles = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension.lowercased() == "svg" }) ?? []
        if svgFiles.count == 1 {
            candidates.append(svgFiles[0])
        }

        var seen = Set<String>()
        return candidates.filter { url in
            let key = url.standardizedFileURL.path
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func promptForGaugeSVG(nextTo jsonURL: URL, metricKind: MetricSourceKind) -> URL? {
        let panel = NSOpenPanel()
        if let svgType = UTType(filenameExtension: "svg") {
            panel.allowedContentTypes = [svgType]
        }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = jsonURL.deletingLastPathComponent()
        panel.message = "选择对应的仪表盘 SVG"
        if let filename = dialSVGFilename(for: metricKind) {
            panel.nameFieldStringValue = filename
        }
        return panel.runModal() == .OK ? panel.url : nil
    }

    private static func dialSVGFilename(for kind: MetricSourceKind) -> String? {
        switch kind {
        case .networkUp:
            return "网速上行.svg"
        case .networkDown:
            return "网速下行.svg"
        case .diskRead:
            return "硬盘读取.svg"
        case .diskWrite:
            return "硬盘写入.svg"
        default:
            return nil
        }
    }

    private func mergeLayout(with modules: [RegistryEntry]) {
        if !layout.contains(where: { $0.kind == .source }) {
            layout.insert(.source, at: 0)
        }

        let validIDs = Set(modules.map(\.id))
        layout.removeAll { slot in
            guard slot.kind == .module else { return false }
            guard let moduleID = slot.moduleID else { return true }
            return !validIDs.contains(moduleID)
        }

        var nextPosition = (layout.map(\.position).max() ?? 0) + 1
        let existingModuleIDs = Set(layout.compactMap(\.moduleID))
        for module in modules where !existingModuleIDs.contains(module.id) {
            layout.append(.module(moduleID: module.id, position: nextPosition))
            nextPosition += 1
        }

        layout.sort { lhs, rhs in
            if lhs.position == rhs.position {
                return lhs.id < rhs.id
            }
            return lhs.position < rhs.position
        }
    }

    private func selectedModuleSetting(for entry: RegistryEntry) -> ModuleSetting? {
        moduleSettings.first(where: { $0.moduleID == entry.id })
    }

    private func ensureI2CDebugSelection(preferred: Int? = nil) {
        let detected = detectedI2CAddresses
        if let preferred, detected.contains(preferred) {
            i2cDebugSourceAddress = preferred
            return
        }

        if let current = i2cDebugSourceAddress, detected.contains(current) {
            return
        }

        i2cDebugSourceAddress = detected.first
    }

    private func updateBinding(for moduleID: Int, binding: ChannelBinding) {
        if let index = moduleSettings.firstIndex(where: { $0.moduleID == moduleID }) {
            moduleSettings[index].updateChannelBinding(binding)
        } else if let entry = registeredModules.first(where: { $0.id == moduleID }) {
            var setting = ModuleSetting.default(for: entry)
            setting.updateChannelBinding(binding)
            moduleSettings.append(setting)
        }
        moduleSettings.sort { $0.moduleID < $1.moduleID }
        persistState()
    }

    private func buildOutputFrameIfReady(snapshot: SystemMetricsSnapshot) -> (ORBEndpoint, OutputFrame)? {
        guard
            let endpoint = activeEndpoint,
            let state = deviceState,
            sourceIsOnline,
            activeCalibration == nil,
            locatingChannelKey == nil,
            pendingCalibrationStartKey == nil,
            (state.unknownI2CAddresses ?? []).isEmpty
        else {
            return nil
        }

        let channels = state.registeredModules.compactMap { entry -> [OutputChannelPayload]? in
            guard let setting = selectedModuleSetting(for: entry) else { return nil }

            return setting.channelBindings.sorted { $0.channelIndex < $1.channelIndex }.compactMap { binding in
                guard shouldSendOutput(for: binding.metric) else { return nil }
                let normalizedValue = normalizedValue(for: binding.metric, snapshot: snapshot)
                let lut = self.calibrationLUT(for: entry, channelIndex: binding.channelIndex)
                let targetCode = LUTMapper.map(normalizedValue: normalizedValue, with: lut)
                return OutputChannelPayload(
                    moduleID: entry.id,
                    channelIndex: binding.channelIndex,
                    targetCode: targetCode
                )
            }
        }.flatMap { $0 }

        guard !channels.isEmpty else {
            return nil
        }

        outputFrameID += 1
        return (endpoint, OutputFrame(frameID: outputFrameID, channels: channels))
    }

    private func normalizedValue(for metric: MetricBinding, snapshot: SystemMetricsSnapshot) -> Double {
        switch metric.kind {
        case .none:
            return 0
        case .cpuTotal:
            return min(max(snapshot.totalCPUUsagePercent / 100.0, 0), 1)
        case .cpuCore, .cpuCoreAverage:
            let indices = resolvedCPUCoreSelection(for: metric)
            let values = indices.compactMap { index in
                snapshot.cpuCoreLoads.first(where: { $0.index == index })?.usagePercent
            }
            guard !values.isEmpty else { return min(max(snapshot.totalCPUUsagePercent / 100.0, 0), 1) }
            let average = values.reduce(0, +) / Double(values.count)
            return min(max(average / 100.0, 0), 1)
        case .memoryUsage:
            return min(max(snapshot.memoryUsagePercent / 100.0, 0), 1)
        case .networkUp:
            return normalizedRate(snapshot.networkSendBytesPerSecond, for: metric, fallbackRanges: networkRanges)
        case .networkDown:
            return normalizedRate(snapshot.networkReceiveBytesPerSecond, for: metric, fallbackRanges: networkRanges)
        case .diskRead:
            return normalizedRate(snapshot.diskReadBytesPerSecond, for: metric, fallbackRanges: diskRanges)
        case .diskWrite:
            return normalizedRate(snapshot.diskWriteBytesPerSecond, for: metric, fallbackRanges: diskRanges)
        case .gpuPlaceholder:
            return min(max(snapshot.totalCPUUsagePercent / 100.0, 0), 1)
        }
    }

    private func normalizedRate(_ value: Double, for metric: MetricBinding, fallbackRanges: [PiecewiseRange]) -> Double {
        let points = metric.scalePoints
            .filter { $0.value >= 0 }
            .sorted { $0.value < $1.value }

        guard !points.isEmpty else {
            return piecewiseNormalizedRate(value, ranges: fallbackRanges)
        }

        var previous = MetricScalePoint(value: 0, percent: 0)
        for point in points {
            guard point.value > previous.value else {
                previous = point
                continue
            }
            if value <= point.value {
                let progress = (value - previous.value) / (point.value - previous.value)
                let percent = previous.percent + progress * (point.percent - previous.percent)
                return min(max(percent, 0), 1)
            }
            previous = point
        }

        return min(max(previous.percent, 0), 1)
    }

    private func shouldSendOutput(for metric: MetricBinding) -> Bool {
        switch metric.kind {
        case .none:
            return false
        case .cpuCore, .cpuCoreAverage:
            return !metric.coreIndices.isEmpty
        default:
            return true
        }
    }

    private func previewActiveCalibration() {
        guard
            let draft = activeCalibration,
            let endpoint = activeEndpoint,
            sourceIsOnline
        else {
            return
        }

        let targetCode = Int((min(max(draft.currentStep.output, 0), 1) * 4095).rounded())

        calibrationPreviewTask?.cancel()
        calibrationPreviewTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(nanoseconds: 90_000_000)
                _ = try await self.session.activatePreview(
                    mode: .calibration,
                    moduleID: draft.moduleID,
                    channelIndex: draft.channelIndex,
                    targetCode: targetCode,
                    endpoint: endpoint,
                    timeoutInterval: 0.9
                )
            } catch {
                await MainActor.run {
                    if self.shouldIgnorePreviewError(error) {
                        return
                    }
                    self.moduleActionIssue = "校准预览发送失败：\(error.localizedDescription)"
                    NSLog("ORB App：校准预览发送失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    deinit {
        metricsTask?.cancel()
        heartbeatWatchdogTask?.cancel()
        calibrationPreviewTask?.cancel()
        calibrationStartTask?.cancel()
        locatePreviewTask?.cancel()
        motionApplySuccessTask?.cancel()
        reconnectStatusNoticeTask?.cancel()
        heartbeatConfigTask?.cancel()
        pendingStateRefreshTask?.cancel()
        firmwareUploadTask?.cancel()
    }

    private func resolvedCPUCoreSelection(for metric: MetricBinding) -> [Int] {
        switch metric.kind {
        case .cpuTotal:
            return availableCPUCoreIndices
        case .cpuCore:
            return [metric.coreIndices.first ?? 0]
        case .cpuCoreAverage:
            return metric.coreIndices
        default:
            return availableCPUCoreIndices
        }
    }

    private func piecewiseNormalizedRate(_ rate: Double, ranges: [PiecewiseRange]) -> Double {
        let clampedRate = max(rate, 0)
        guard let last = ranges.last else { return 0 }

        if clampedRate >= last.upperValue {
            return 1
        }

        for range in ranges {
            if clampedRate <= range.upperValue {
                let span = max(range.upperValue - range.lowerValue, 1)
                let progress = (clampedRate - range.lowerValue) / span
                let percent = range.lowerPercent + ((range.upperPercent - range.lowerPercent) * progress)
                return min(max(percent, 0), 1)
            }
        }

        return 1
    }

    private var networkRanges: [PiecewiseRange] {
        let oneMB = 1_024.0 * 1_024.0
        return [
            PiecewiseRange(lowerValue: 0, upperValue: oneMB, lowerPercent: 0.0, upperPercent: 0.30),
            PiecewiseRange(lowerValue: oneMB, upperValue: 10 * oneMB, lowerPercent: 0.30, upperPercent: 0.50),
            PiecewiseRange(lowerValue: 10 * oneMB, upperValue: 50 * oneMB, lowerPercent: 0.50, upperPercent: 0.70),
            PiecewiseRange(lowerValue: 50 * oneMB, upperValue: 100 * oneMB, lowerPercent: 0.70, upperPercent: 0.90),
            PiecewiseRange(lowerValue: 100 * oneMB, upperValue: 500 * oneMB, lowerPercent: 0.90, upperPercent: 1.0)
        ]
    }

    private var diskRanges: [PiecewiseRange] {
        let oneMB = 1_024.0 * 1_024.0
        let oneGB = oneMB * 1_024.0
        return [
            PiecewiseRange(lowerValue: 0, upperValue: oneMB, lowerPercent: 0.0, upperPercent: 0.20),
            PiecewiseRange(lowerValue: oneMB, upperValue: 100 * oneMB, lowerPercent: 0.20, upperPercent: 0.60),
            PiecewiseRange(lowerValue: 100 * oneMB, upperValue: oneGB, lowerPercent: 0.60, upperPercent: 0.80),
            PiecewiseRange(lowerValue: oneGB, upperValue: 5 * oneGB, lowerPercent: 0.80, upperPercent: 0.90),
            PiecewiseRange(lowerValue: 5 * oneGB, upperValue: 10 * oneGB, lowerPercent: 0.90, upperPercent: 1.0)
        ]
    }

    private var heartbeatGraceWindow: TimeInterval {
        let intervalMs = latestHeartbeat?.heartbeatIntervalMs ?? deviceState?.heartbeatIntervalMs ?? 1500
        return max(Double(intervalMs) / 1000.0 * 3.2, 2.5)
    }

    private func orderedCalibrationPoints(
        for moduleType: ModuleType,
        metric: MetricBinding,
        existingLUT: CalibrationLUT
    ) -> [LUTPoint] {
        var lookup: [Double: Double] = [:]
        for point in existingLUT.points {
            lookup[point.input] = point.output
        }
        let orderedInputs: [Double]

        switch moduleType {
        case .radiance:
            orderedInputs = [0.0, 0.5, 0.25, 1.0, 0.75]
        case .balance:
            let importedPercents = metric.scalePoints
                .map(\.percent)
                .sorted()
            var dedupedPercents: [Double] = []
            for percent in importedPercents {
                if dedupedPercents.last.map({ abs($0 - percent) < 0.0001 }) != true {
                    dedupedPercents.append(percent)
                }
            }
            orderedInputs = dedupedPercents.isEmpty ? stride(from: 0.0, through: 1.0, by: 0.1).map { $0 } : dedupedPercents
        case .unknown:
            orderedInputs = stride(from: 0.0, through: 1.0, by: 0.1).map { $0 }
        }

        return orderedInputs.map { input in
            LUTPoint(input: input, output: lookup[input] ?? input)
        }
    }

    private func shouldIgnorePreviewError(_ error: Error) -> Bool {
        if Task.isCancelled {
            return true
        }
        if let urlError = error as? URLError {
            return urlError.code == .cancelled || urlError.code == .networkConnectionLost
        }
        return false
    }

    private func channelActionKey(moduleID: Int, channelIndex: Int) -> String {
        "\(moduleID)-\(channelIndex)"
    }

    private func requestPreviewActivation(
        mode: OutputPreviewMode,
        moduleID: Int,
        channelIndex: Int,
        targetCode: Int,
        endpoint: ORBEndpoint,
        totalTimeout: TimeInterval = 3.0,
        retryDelay: TimeInterval = 0.35
    ) async throws {
        let startedAt = Date()
        var lastError: Error?

        while Date().timeIntervalSince(startedAt) < totalTimeout {
            do {
                let elapsed = Date().timeIntervalSince(startedAt)
                let remaining = max(totalTimeout - elapsed, 0.25)
                let response = try await session.activatePreview(
                    mode: mode,
                    moduleID: moduleID,
                    channelIndex: channelIndex,
                    targetCode: targetCode,
                    endpoint: endpoint,
                    timeoutInterval: min(0.9, remaining)
                )
                try Self.validatePreviewAck(
                    expectedMode: mode,
                    moduleID: moduleID,
                    channelIndex: channelIndex,
                    targetCode: targetCode,
                    response: response
                )
                return
            } catch {
                if Task.isCancelled {
                    throw error
                }
                lastError = error
                if !Self.shouldRetryPreviewActivation(after: error) {
                    throw error
                }
            }

            let remaining = totalTimeout - Date().timeIntervalSince(startedAt)
            guard remaining > 0 else { break }
            let pause = min(retryDelay, remaining)
            try? await Task.sleep(nanoseconds: UInt64(max(pause, 0.05) * 1_000_000_000))
        }

        let actionLabel = mode == .calibration ? "校准" : "寻找通道"
        if let lastError {
            throw PreviewAckError("\(actionLabel)启动超时，请重新点击。最后一次错误：\(lastError.localizedDescription)")
        }
        throw PreviewAckError("\(actionLabel)启动超时，请重新点击。")
    }

    private static func validatePreviewAck(
        expectedMode: OutputPreviewMode,
        moduleID: Int,
        channelIndex: Int,
        targetCode: Int,
        response: ORBPreviewActivationResponse
    ) throws {
        guard response.ok == true else {
            throw PreviewAckError("ESP32 没有确认预览请求。")
        }
        guard response.previewActive == true else {
            throw PreviewAckError("ESP32 没有进入预览状态。")
        }
        guard response.mode == expectedMode.rawValue else {
            throw PreviewAckError("ESP32 返回的预览模式不一致。")
        }
        guard response.moduleId == moduleID else {
            throw PreviewAckError("ESP32 返回的模块号不一致。")
        }
        guard response.channelIndex == channelIndex else {
            throw PreviewAckError("ESP32 返回的通道号不一致。")
        }
        guard response.targetCode == targetCode else {
            throw PreviewAckError("ESP32 返回的目标码不一致。")
        }
    }

    private static func shouldRetryPreviewActivation(after error: Error) -> Bool {
        if let sessionError = error as? ORBSessionError {
            switch sessionError {
            case .invalidURL, .invalidResponse, .decodingFailed, .fileReadFailed:
                return false
            case .requestFailed(let code):
                return code >= 500
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
                return true
            case .cancelled:
                return false
            default:
                return true
            }
        }

        return true
    }

    private func sendCurrentOutputsIfPossible() {
        guard let transmission = buildOutputFrameIfReady(snapshot: systemMetrics) else { return }

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.session.sendOutputs(transmission.1, endpoint: transmission.0)
                await MainActor.run {
                    self.noteDeviceContact(endpoint: transmission.0)
                }
            } catch {
                await MainActor.run {
                    NSLog("ORB App：恢复实时输出失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    private func noteDeviceContact(endpoint: ORBEndpoint? = nil) {
        if let endpoint {
            activeEndpoint = endpoint
        }
        localNetworkAccessIssue = nil
        lastDeviceContactAt = .now
        updateConnectionStatus()
    }

    private func startHeartbeatWatchdog() {
        heartbeatWatchdogTask?.cancel()
        heartbeatWatchdogTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                let probeEndpoint = await MainActor.run { () -> ORBEndpoint? in
                    self.updateConnectionStatus()
                    return self.nextLivenessProbeEndpoint()
                }

                if let probeEndpoint {
                    await self.performLivenessProbe(to: probeEndpoint)
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }

    private func handleHeartbeat(_ heartbeat: ORBHeartbeat) {
        latestHeartbeat = heartbeat
        lastDeviceContactAt = heartbeat.receivedAt
        applyHeartbeatRoute(
            defaultPort: heartbeat.defaultPort,
            targetPort: heartbeat.targetPort,
            configuredPort: heartbeat.configuredPort,
            delivery: heartbeat.delivery
        )

        let activeDeviceName = deviceState?.deviceName
        let activeMac = deviceState?.mac?.uppercased()
        let isRelevant =
            activeDeviceName == nil ||
            activeDeviceName == heartbeat.deviceName ||
            activeMac == heartbeat.mac.uppercased()

        if isRelevant {
            activeEndpoint = heartbeat.endpoint
            updateConnectionStatus()
        }

        if deviceState == nil, activeEndpoint != nil {
            pendingStateRefreshTask?.cancel()
            pendingStateRefreshTask = Task { [weak self] in
                guard let self else { return }
                await self.loadState(from: heartbeat.endpoint, preserveSelection: false)
            }
            return
        }

        if isRelevant,
           heartbeat.stateRevision != lastAppliedStateRevision,
           activeCalibration == nil,
           !isPerformingUnknownDeviceAction,
           let endpoint = activeEndpoint {
            pendingStateRefreshTask?.cancel()
            pendingStateRefreshTask = Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: 120_000_000)
                await self.loadState(from: endpoint, preserveSelection: true)
            }
        }
    }

    private func updateConnectionStatus() {
        if sourceIsOnline {
            connectionStatus = .online
            return
        }

        if hasKnownDevice {
            connectionStatus = .offline
        } else {
            connectionStatus = .notFound
        }
    }

    private var hasKnownDevice: Bool {
        deviceState != nil || activeEndpoint != nil || latestHeartbeat != nil
    }

    private func calibrationLUT(for entry: RegistryEntry, channelIndex: Int) -> CalibrationLUT {
        calibrationLUTs.first(where: {
            $0.moduleID == entry.id && $0.channelIndex == channelIndex
        }) ?? LUTMapper.defaultLUT(for: entry.moduleType, moduleID: entry.id, channelIndex: channelIndex)
    }

    private func updateMotionDraftConfig(_ config: SmoothingConfig, for moduleType: ModuleType) {
        motionDraftProfiles.update(config, for: moduleType)
        noteMotionDraftChanged()
    }

    private func noteMotionDraftChanged() {
        hasLocalMotionDraftEdits = true
        smoothingActionIssue = nil
        clearMotionApplySuccessNotice()
    }

    private func resolvedMotionDraftProfiles() -> DeviceSmoothingProfiles {
        var profiles = motionDraftProfiles
        let settleTimeMs = Int((motionDraftMovementDurationSeconds * 1000).rounded())
        profiles.radiance.settleTimeMs = settleTimeMs
        profiles.balance.settleTimeMs = settleTimeMs
        return profiles
    }

    private func confirmedMotionProfiles() -> DeviceSmoothingProfiles {
        if let deviceState {
            return deviceState.smoothing
        }

        var profiles = DeviceSmoothingProfiles()
        let settleTimeMs = Int((movementDurationSeconds * 1000).rounded())
        profiles.radiance.settleTimeMs = settleTimeMs
        profiles.balance.settleTimeMs = settleTimeMs
        return profiles
    }

    private func syncMotionDraftFromConfirmedState(force: Bool = false) {
        guard force || (!hasLocalMotionDraftEdits && !isApplyingMotionSettings) else { return }

        let confirmedProfiles = confirmedMotionProfiles()
        motionDraftProfiles = confirmedProfiles

        let settleTimeSeconds = Double(confirmedProfiles.radiance.settleTimeMs) / 1000.0
        let factor = clampMotionDurationFactor(settleTimeSeconds / max(refreshInterval, 0.25))
        motionDurationFactor = factor
        motionDraftDurationFactor = factor
    }

    private func presentMotionApplySuccessNotice() {
        motionApplySuccessTask?.cancel()
        motionApplySuccessNotice = "参数设置成功"
        motionApplySuccessTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.motionApplySuccessNotice = nil
            }
        }
    }

    private func clearMotionApplySuccessNotice() {
        motionApplySuccessTask?.cancel()
        motionApplySuccessNotice = nil
    }

    private func presentReconnectStatusNotice() {
        reconnectStatusNoticeTask?.cancel()
        reconnectStatusNotice = "已发起重新连接"
        reconnectStatusNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.reconnectStatusNotice = nil
            }
        }
    }

    private func clampMotionDurationFactor(_ value: Double) -> Double {
        min(max(value, 0.10), 1.50)
    }

    private func applyHeartbeatRoute(
        defaultPort: Int?,
        targetPort: Int?,
        configuredPort: Bool?,
        delivery: String?
    ) {
        guard defaultPort != nil || targetPort != nil || configuredPort != nil || delivery != nil else {
            return
        }

        guard var currentState = deviceState else {
            return
        }

        if let defaultPort {
            currentState.heartbeatDefaultPort = defaultPort
        }
        if let targetPort {
            currentState.heartbeatTargetPort = targetPort
        }
        if let configuredPort {
            currentState.heartbeatConfiguredPort = configuredPort
        }
        if let delivery {
            currentState.heartbeatDelivery = delivery
        }

        deviceState = currentState
    }

    private func requestHeartbeatRoutingSyncIfPossible() {
        guard
            heartbeatListenerStatus.isAvailable,
            let listenerPort = heartbeatListenerStatus.localPort,
            let endpoint = activeEndpoint,
            deviceSupportsHeartbeatRouting
        else {
            return
        }

        let currentTargetPort = deviceState?.heartbeatTargetPort
        let isConfigured = deviceState?.heartbeatConfiguredPort ?? false
        if currentTargetPort == listenerPort && isConfigured {
            return
        }

        heartbeatConfigTask?.cancel()
        heartbeatConfigTask = Task { [weak self] in
            guard let self else { return }

            do {
                let response = try await self.session.configureHeartbeat(listenerPort: listenerPort, endpoint: endpoint)
                try Self.validateHeartbeatConfigAck(expectedPort: listenerPort, response: response)

                await MainActor.run {
                    self.heartbeatRoutingIssue = nil
                    self.applyHeartbeatRoute(
                        defaultPort: response.heartbeatDefaultPort,
                        targetPort: response.heartbeatTargetPort,
                        configuredPort: response.heartbeatConfiguredPort,
                        delivery: response.heartbeatDelivery
                    )
                }
            } catch {
                await MainActor.run {
                    self.heartbeatRoutingIssue = "UDP 心跳端口同步失败：\(error.localizedDescription)"
                    NSLog("ORB App：UDP 心跳端口同步失败，原因：%@", error.localizedDescription)
                }
            }
        }
    }

    private var deviceSupportsHeartbeatRouting: Bool {
        deviceState?.heartbeatDefaultPort != nil ||
            deviceState?.heartbeatTargetPort != nil ||
            deviceState?.heartbeatConfiguredPort != nil ||
            deviceState?.heartbeatDelivery != nil
    }

    private func nextLivenessProbeEndpoint() -> ORBEndpoint? {
        guard let endpoint = latestHeartbeat?.endpoint ?? activeEndpoint else { return nil }
        guard shouldUseHTTPProbe else { return nil }

        let minimumGap = max(min(heartbeatGraceWindow * 0.5, 2.0), 1.0)
        if let lastLivenessProbeAt, Date().timeIntervalSince(lastLivenessProbeAt) < minimumGap {
            return nil
        }

        lastLivenessProbeAt = .now
        return endpoint
    }

    private var shouldUseHTTPProbe: Bool {
        if !heartbeatListenerStatus.isAvailable {
            return true
        }

        guard let lastDeviceContactAt else {
            return activeEndpoint != nil || latestHeartbeat != nil
        }

        if latestHeartbeat == nil {
            return Date().timeIntervalSince(lastDeviceContactAt) >= max(heartbeatGraceWindow * 0.4, 1.0)
        }

        return Date().timeIntervalSince(lastDeviceContactAt) >= heartbeatGraceWindow
    }

    private func performLivenessProbe(to endpoint: ORBEndpoint) async {
        do {
            let ping = try await session.ping(endpoint: endpoint)
            await MainActor.run {
                self.localNetworkAccessIssue = nil
                self.activeEndpoint = endpoint
                self.lastDeviceContactAt = .now
                self.applyHeartbeatRoute(
                    defaultPort: ping.heartbeatDefaultPort,
                    targetPort: ping.heartbeatTargetPort,
                    configuredPort: ping.heartbeatConfiguredPort,
                    delivery: ping.heartbeatDelivery
                )
                self.updateConnectionStatus()
                self.requestHeartbeatRoutingSyncIfPossible()
            }

            let needsFullRefresh = await MainActor.run { () -> Bool in
                self.deviceState == nil || ping.stateRevision != self.lastAppliedStateRevision
            }

            if needsFullRefresh {
                await loadState(from: endpoint, preserveSelection: true)
            }
        } catch {
            await MainActor.run {
                NSLog("ORB App：HTTP 探活失败，原因：%@", error.localizedDescription)
                self.noteNetworkAccessFailure(error)
                self.updateConnectionStatus()
            }
        }
    }

    private func noteNetworkAccessFailure(_ error: any Error) {
        guard Self.isLocalNetworkProhibited(error) else { return }
        localNetworkAccessIssue = "macOS 已禁止 ORB 访问本地网络。请在“系统设置 > 隐私与安全性 > 本地网络”里允许 ORB。"
    }

    private static func isLocalNetworkProhibited(_ error: any Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain,
           nsError.code == URLError.notConnectedToInternet.rawValue,
           String(describing: nsError.userInfo).contains("Local network prohibited") {
            return true
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isLocalNetworkProhibited(underlying)
        }

        return false
    }

    private static func expandedCalibrationLUTs(from stored: [CalibrationLUT]) -> [CalibrationLUT] {
        var expanded: [CalibrationLUT] = []
        var seen = Set<String>()

        for lut in stored {
            let primary = CalibrationLUT(
                moduleID: lut.moduleID,
                channelIndex: lut.channelIndex,
                points: lut.points,
                updatedAt: lut.updatedAt
            )
            if seen.insert(primary.id).inserted {
                expanded.append(primary)
            }

            if lut.legacyShared {
                for channelIndex in 0..<2 {
                    let migrated = CalibrationLUT(
                        moduleID: lut.moduleID,
                        channelIndex: channelIndex,
                        points: lut.points,
                        updatedAt: lut.updatedAt
                    )
                    if seen.insert(migrated.id).inserted {
                        expanded.append(migrated)
                    }
                }
            }
        }

        return expanded.sorted {
            if $0.moduleID == $1.moduleID {
                return $0.channelIndex < $1.channelIndex
            }
            return $0.moduleID < $1.moduleID
        }
    }

    private func upsertCalibrationLUT(_ lut: CalibrationLUT) {
        calibrationLUTs.removeAll { $0.moduleID == lut.moduleID && $0.channelIndex == lut.channelIndex }
        calibrationLUTs.append(lut)
        calibrationLUTs.sort {
            if $0.moduleID == $1.moduleID {
                return $0.channelIndex < $1.channelIndex
            }
            return $0.moduleID < $1.moduleID
        }
    }

    private func persistedCalibrationLUTs() -> [CalibrationLUT] {
        var deduped: [CalibrationLUT] = []
        var seen = Set<String>()

        for lut in calibrationLUTs.sorted(by: { lhs, rhs in
            if lhs.moduleID == rhs.moduleID {
                return lhs.channelIndex < rhs.channelIndex
            }
            return lhs.moduleID < rhs.moduleID
        }) {
            if seen.insert(lut.id).inserted {
                deduped.append(
                    CalibrationLUT(
                        moduleID: lut.moduleID,
                        channelIndex: lut.channelIndex,
                        points: lut.points.sorted { $0.input < $1.input },
                        updatedAt: lut.updatedAt
                    )
                )
            }
        }

        return deduped
    }

    private func timestampLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func debugRateText(_ value: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return "\(formatter.string(fromByteCount: Int64(max(value, 0))))/s"
    }

    private func debugPercentText(_ value: Double) -> String {
        String(format: "%.1f%%", value)
    }

    private func debugMemoryText() -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .binary
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return "\(formatter.string(fromByteCount: Int64(systemMetrics.memoryUsedBytes))) / \(formatter.string(fromByteCount: Int64(systemMetrics.memoryTotalBytes)))"
    }

    private static func validateHeartbeatConfigAck(
        expectedPort: Int,
        response: ORBHeartbeatConfigResponse
    ) throws {
        guard response.ok == true else {
            throw HeartbeatConfigAckError("ESP32 没有确认新的 UDP 心跳端口。")
        }
        guard response.heartbeatTargetPort == expectedPort else {
            throw HeartbeatConfigAckError("ESP32 返回的心跳端口不一致：期望 \(expectedPort)，收到 \(response.heartbeatTargetPort ?? -1)。")
        }
        guard response.heartbeatConfiguredPort == true else {
            throw HeartbeatConfigAckError("ESP32 没有切换到上位机请求的 UDP 端口。")
        }
    }

    private static func validateMotionAck(
        expected: SmoothingConfig,
        actual: SmoothingConfig,
        moduleType: ModuleType
    ) throws {
        let typeLabel = moduleType.displayName
        let tolerance = 0.0015

        guard expected.settleTimeMs == actual.settleTimeMs else {
            throw MotionAckError("\(typeLabel) 到位时间确认不一致：期望 \(expected.settleTimeMs) ms，收到 \(actual.settleTimeMs) ms。")
        }
        guard abs(expected.aMax - actual.aMax) <= tolerance else {
            throw MotionAckError("\(typeLabel) a_max 确认不一致：期望 \(String(format: "%.3f", expected.aMax))，收到 \(String(format: "%.3f", actual.aMax))。")
        }
        guard abs(expected.vMax - actual.vMax) <= tolerance else {
            throw MotionAckError("\(typeLabel) v_max 确认不一致：期望 \(String(format: "%.3f", expected.vMax))，收到 \(String(format: "%.3f", actual.vMax))。")
        }
        guard abs(expected.jitterFrequencyHz - actual.jitterFrequencyHz) <= tolerance else {
            throw MotionAckError("\(typeLabel) 抖动频率确认不一致：期望 \(String(format: "%.3f", expected.jitterFrequencyHz))，收到 \(String(format: "%.3f", actual.jitterFrequencyHz))。")
        }
        guard abs(expected.jitterAmplitude - actual.jitterAmplitude) <= tolerance else {
            throw MotionAckError("\(typeLabel) 抖动振幅确认不一致：期望 \(String(format: "%.3f", expected.jitterAmplitude))，收到 \(String(format: "%.3f", actual.jitterAmplitude))。")
        }
        guard abs(expected.jitterDispersion - actual.jitterDispersion) <= tolerance else {
            throw MotionAckError("\(typeLabel) 抖动离散程度确认不一致：期望 \(String(format: "%.3f", expected.jitterDispersion))，收到 \(String(format: "%.3f", actual.jitterDispersion))。")
        }
    }
}

private struct MotionAckError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private struct HeartbeatConfigAckError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}

private struct PreviewAckError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
