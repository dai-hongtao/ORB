import SwiftUI

enum ModuleType: Int, Codable, CaseIterable {
    case unknown = 0
    case radiance = 1
    case balance = 2

    static var registrationOptions: [ModuleType] {
        [.radiance, .balance]
    }

    var displayName: String {
        switch self {
        case .unknown:
            return "未定义"
        case .radiance:
            return "曜"
        case .balance:
            return "衡"
        }
    }

    var symbolName: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .radiance:
            return "sparkles"
        case .balance:
            return "gauge.medium"
        }
    }

    var accentColor: Color {
        switch self {
        case .unknown:
            return Color.gray
        case .radiance:
            return Color(red: 0.77, green: 0.30, blue: 0.16)
        case .balance:
            return Color(red: 0.17, green: 0.46, blue: 0.52)
        }
    }

    var registrationLabel: String {
        switch self {
        case .unknown:
            return "未定义"
        case .radiance:
            return "电子管"
        case .balance:
            return "指针"
        }
    }
}

enum SlotKind: String, Codable {
    case source
    case module
}

enum MetricSourceKind: String, Codable, CaseIterable {
    case none
    case cpuTotal
    case cpuCore
    case cpuCoreAverage
    case memoryUsage
    case networkUp
    case networkDown
    case diskRead
    case diskWrite
    case gpuPlaceholder

    var label: String {
        switch self {
        case .none:
            return ""
        case .cpuTotal:
            return "全部 CPU"
        case .cpuCore:
            return "单个核心"
        case .cpuCoreAverage:
            return "核心组平均"
        case .memoryUsage:
            return "内存占用"
        case .networkUp:
            return "网络上传"
        case .networkDown:
            return "网络下载"
        case .diskRead:
            return "磁盘读取"
        case .diskWrite:
            return "磁盘写入"
        case .gpuPlaceholder:
            return "GPU 负载"
        }
    }

    var localizedLabelKey: String {
        switch self {
        case .none:
            return ""
        case .cpuTotal:
            return "metric.cpu_total"
        case .cpuCore:
            return "metric.cpu_core"
        case .cpuCoreAverage:
            return "metric.cpu_core_average"
        case .memoryUsage:
            return "metric.memory_usage"
        case .networkUp:
            return "metric.network_up"
        case .networkDown:
            return "metric.network_down"
        case .diskRead:
            return "metric.disk_read"
        case .diskWrite:
            return "metric.disk_write"
        case .gpuPlaceholder:
            return "metric.gpu_usage"
        }
    }

    static func options(for moduleType: ModuleType) -> [MetricSourceKind] {
        switch moduleType {
        case .radiance:
            return [.cpuCoreAverage, .memoryUsage]
        case .balance:
            return [.networkDown, .networkUp, .diskRead, .diskWrite]
        case .unknown:
            return []
        }
    }

    var requiresCoreSelection: Bool {
        self == .cpuCore || self == .cpuCoreAverage
    }

    var allowsMultipleCoreSelection: Bool {
        self == .cpuCoreAverage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        switch rawValue {
        case "none":
            self = .none
        case "cpuTotal":
            self = .cpuTotal
        case "cpuCore":
            self = .cpuCore
        case "cpuCoreAverage":
            self = .cpuCoreAverage
        case "cpuTemperature", "fanSpeed":
            self = .memoryUsage
        case "memoryUsage":
            self = .memoryUsage
        case "networkUp":
            self = .networkUp
        case "networkDown":
            self = .networkDown
        case "diskRead":
            self = .diskRead
        case "diskWrite":
            self = .diskWrite
        case "gpuPlaceholder":
            self = .gpuPlaceholder
        default:
            self = .none
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct MetricBinding: Codable, Equatable {
    var kind: MetricSourceKind
    var coreIndices: [Int] = []
    var userAssigned: Bool = false
    var scalePoints: [MetricScalePoint] = []
    var dialSVGPath: String?
    var dialSVGMarkup: String?

    init(
        kind: MetricSourceKind,
        coreIndices: [Int] = [],
        userAssigned: Bool = false,
        scalePoints: [MetricScalePoint] = [],
        dialSVGPath: String? = nil,
        dialSVGMarkup: String? = nil
    ) {
        self.kind = kind
        self.coreIndices = coreIndices
        self.userAssigned = userAssigned
        self.scalePoints = scalePoints
        self.dialSVGPath = dialSVGPath
        self.dialSVGMarkup = dialSVGMarkup
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(MetricSourceKind.self, forKey: .kind)
        coreIndices = try container.decodeIfPresent([Int].self, forKey: .coreIndices) ?? []
        userAssigned = try container.decodeIfPresent(Bool.self, forKey: .userAssigned) ?? false
        scalePoints = try container.decodeIfPresent([MetricScalePoint].self, forKey: .scalePoints) ?? []
        dialSVGPath = try container.decodeIfPresent(String.self, forKey: .dialSVGPath)
        dialSVGMarkup = try container.decodeIfPresent(String.self, forKey: .dialSVGMarkup)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(coreIndices, forKey: .coreIndices)
        try container.encode(userAssigned, forKey: .userAssigned)
        try container.encode(scalePoints, forKey: .scalePoints)
        try container.encodeIfPresent(dialSVGPath, forKey: .dialSVGPath)
        try container.encodeIfPresent(dialSVGMarkup, forKey: .dialSVGMarkup)
    }

    var label: String {
        switch kind {
        case .none:
            return ""
        case .cpuTotal:
            return "全部核心平均"
        case .cpuCore where !coreIndices.isEmpty:
            return "核心 \(coreIndices[0])"
        case .cpuCoreAverage where coreIndices.count == 1:
            return "核心 \(coreIndices[0])"
        case .cpuCoreAverage where coreIndices.count > 4:
            return "已选 \(coreIndices.count) 个核心"
        case .cpuCoreAverage where !coreIndices.isEmpty:
            let joined = coreIndices.map(String.init).joined(separator: ", ")
            return "核心组 \(joined)"
        case .memoryUsage:
            return "内存占用"
        default:
            return kind.label
        }
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case coreIndices
        case userAssigned
        case scalePoints
        case dialSVGPath
        case dialSVGMarkup
    }
}

struct MetricScalePoint: Codable, Equatable {
    var value: Double
    var percent: Double
    var label: String?

    init(value: Double, percent: Double, label: String? = nil) {
        self.value = value
        self.percent = percent
        self.label = label
    }
}

struct ChannelBinding: Codable, Identifiable, Equatable {
    let channelIndex: Int
    var metric: MetricBinding

    var id: Int { channelIndex }
}

struct RegistryEntry: Codable, Identifiable, Equatable {
    let id: Int
    var registered: Bool
    var present: Bool
    var moduleType: ModuleType

    var displaySlotLabel: String {
        slotLabel(for: id)
    }

    var addressLabel: String {
        switch id {
        case 1...7:
            return String(format: "I2C 0x%02X", 0x60 + id)
        case 8:
            return "I2C 0x60"
        default:
            return "I2C --"
        }
    }
}

func rawAddressLabel(_ address: Int) -> String {
    String(format: "I2C 0x%02X", address)
}

func slotLabel(for id: Int) -> String {
    id == 8 ? "0" : String(id)
}

func addressForModuleID(_ id: Int) -> Int? {
    switch id {
    case 1...7:
        return 0x60 + id
    case 8:
        return 0x60
    default:
        return nil
    }
}

struct SmoothingConfig: Codable, Equatable {
    var settleTimeMs: Int
    var aMax: Double
    var vMax: Double
    var jitterFrequencyHz: Double
    var jitterAmplitude: Double
    var jitterDispersion: Double

    init(
        settleTimeMs: Int = 250,
        aMax: Double = 6.0,
        vMax: Double = 2.6,
        jitterFrequencyHz: Double = 0.0,
        jitterAmplitude: Double = 0.0,
        jitterDispersion: Double = 0.25
    ) {
        self.settleTimeMs = settleTimeMs
        self.aMax = aMax
        self.vMax = vMax
        self.jitterFrequencyHz = jitterFrequencyHz
        self.jitterAmplitude = jitterAmplitude
        self.jitterDispersion = jitterDispersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        settleTimeMs = try container.decodeIfPresent(Int.self, forKey: .settleTimeMs) ?? 250
        aMax = try container.decodeIfPresent(Double.self, forKey: .aMax) ?? 6.0
        vMax = try container.decodeIfPresent(Double.self, forKey: .vMax) ?? 2.6
        jitterFrequencyHz = try container.decodeIfPresent(Double.self, forKey: .jitterFrequencyHz) ?? 0.0
        jitterAmplitude = try container.decodeIfPresent(Double.self, forKey: .jitterAmplitude) ?? 0.0
        jitterDispersion = try container.decodeIfPresent(Double.self, forKey: .jitterDispersion) ?? 0.25
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settleTimeMs, forKey: .settleTimeMs)
        try container.encode(aMax, forKey: .aMax)
        try container.encode(vMax, forKey: .vMax)
        try container.encode(jitterFrequencyHz, forKey: .jitterFrequencyHz)
        try container.encode(jitterAmplitude, forKey: .jitterAmplitude)
        try container.encode(jitterDispersion, forKey: .jitterDispersion)
    }

    private enum CodingKeys: String, CodingKey {
        case settleTimeMs
        case aMax
        case vMax
        case jitterFrequencyHz
        case jitterAmplitude
        case jitterDispersion
    }
}

struct DeviceSmoothingProfiles: Codable, Equatable {
    var radiance: SmoothingConfig
    var balance: SmoothingConfig

    init(
        radiance: SmoothingConfig = DeviceSmoothingProfiles.defaultRadianceConfig,
        balance: SmoothingConfig = DeviceSmoothingProfiles.defaultBalanceConfig
    ) {
        self.radiance = radiance
        self.balance = balance
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let radiance = try container.decodeIfPresent(SmoothingConfig.self, forKey: .radiance),
           let balance = try container.decodeIfPresent(SmoothingConfig.self, forKey: .balance) {
            self.radiance = SmoothingConfig(
                settleTimeMs: radiance.settleTimeMs,
                aMax: radiance.aMax,
                vMax: radiance.vMax,
                jitterFrequencyHz: radiance.jitterFrequencyHz,
                jitterAmplitude: radiance.jitterAmplitude,
                jitterDispersion: radiance.jitterDispersion
            )
            self.balance = SmoothingConfig(
                settleTimeMs: balance.settleTimeMs,
                aMax: balance.aMax,
                vMax: balance.vMax,
                jitterFrequencyHz: balance.jitterFrequencyHz,
                jitterAmplitude: balance.jitterAmplitude,
                jitterDispersion: balance.jitterDispersion
            )
            return
        }

        let legacyAMax = try container.decodeIfPresent(Double.self, forKey: .aMax)
        let legacyVMax = try container.decodeIfPresent(Double.self, forKey: .vMax)
        radiance = SmoothingConfig(
            settleTimeMs: 250,
            aMax: legacyAMax ?? DeviceSmoothingProfiles.defaultRadianceConfig.aMax,
            vMax: legacyVMax ?? DeviceSmoothingProfiles.defaultRadianceConfig.vMax
        )
        balance = SmoothingConfig(
            settleTimeMs: 250,
            aMax: legacyAMax ?? DeviceSmoothingProfiles.defaultBalanceConfig.aMax,
            vMax: legacyVMax ?? DeviceSmoothingProfiles.defaultBalanceConfig.vMax
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(radiance, forKey: .radiance)
        try container.encode(balance, forKey: .balance)
    }

    func config(for moduleType: ModuleType) -> SmoothingConfig {
        switch moduleType {
        case .radiance:
            return radiance
        case .balance:
            return balance
        case .unknown:
            return radiance
        }
    }

    mutating func update(_ config: SmoothingConfig, for moduleType: ModuleType) {
        switch moduleType {
        case .radiance:
            radiance = config
        case .balance:
            balance = config
        case .unknown:
            radiance = config
        }
    }

    private enum CodingKeys: String, CodingKey {
        case radiance
        case balance
        case aMax
        case vMax
    }

    static let defaultRadianceConfig = SmoothingConfig(
        settleTimeMs: 250,
        aMax: 7.1,
        vMax: 2.6,
        jitterFrequencyHz: 2.5,
        jitterAmplitude: 0.8,
        jitterDispersion: 0.32
    )

    static let defaultBalanceConfig = SmoothingConfig(
        settleTimeMs: 250,
        aMax: 8.0,
        vMax: 5.8,
        jitterFrequencyHz: 0.0,
        jitterAmplitude: 0.0,
        jitterDispersion: 0.25
    )
}

struct ORBDeviceState: Codable, Equatable {
    var deviceName: String
    var firmwareVersion: String
    var ip: String
    var mac: String?
    var modules: [RegistryEntry]
    var detectedI2CAddresses: [Int]?
    var unknownI2CAddresses: [Int]?
    var unknownCandidatePresent: Bool
    var calibrationLUTs: [CalibrationLUT]?
    var smoothing: DeviceSmoothingProfiles
    var stateRevision: Int?
    var heartbeatIntervalMs: Int?
    var heartbeatDefaultPort: Int?
    var heartbeatTargetPort: Int?
    var heartbeatConfiguredPort: Bool?
    var heartbeatDelivery: String?

    var registeredModules: [RegistryEntry] {
        modules.filter(\.registered)
    }
}

struct ORBHeartbeat: Decodable, Equatable {
    var type: String?
    var protocolVersion: Int?
    var deviceName: String
    var firmwareVersion: String
    var ip: String
    var mac: String
    var port: Int
    var sequence: Int
    var stateRevision: Int
    var heartbeatIntervalMs: Int
    var uptimeMs: Int
    var registeredCount: Int
    var presentCount: Int
    var defaultPort: Int?
    var targetPort: Int?
    var configuredPort: Bool?
    var delivery: String?
    var receivedAt: Date = .now

    var endpoint: ORBEndpoint {
        ORBEndpoint(host: ip, port: port)
    }
}

struct LayoutSlot: Codable, Identifiable, Equatable {
    let id: String
    var position: Int
    var moduleID: Int?
    var kind: SlotKind

    static let source = LayoutSlot(id: "source", position: 0, moduleID: nil, kind: .source)

    static func module(moduleID: Int, position: Int) -> LayoutSlot {
        LayoutSlot(id: "module-\(moduleID)", position: position, moduleID: moduleID, kind: .module)
    }
}

struct ModuleSetting: Codable, Identifiable, Equatable {
    let moduleID: Int
    var moduleType: ModuleType
    var channelBindings: [ChannelBinding]

    var id: Int { moduleID }

    var summary: String {
        channelBindings
            .sorted { $0.channelIndex < $1.channelIndex }
            .map { "通道 \($0.channelIndex + 1)：\($0.metric.label)" }
            .joined(separator: " · ")
    }

    init(moduleID: Int, moduleType: ModuleType, channelBindings: [ChannelBinding]) {
        self.moduleID = moduleID
        self.moduleType = moduleType
        self.channelBindings = channelBindings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moduleID = try container.decode(Int.self, forKey: .moduleID)
        moduleType = try container.decode(ModuleType.self, forKey: .moduleType)

        if let channelBindings = try container.decodeIfPresent([ChannelBinding].self, forKey: .channelBindings) {
            self.channelBindings = channelBindings
        } else if let legacyBinding = try container.decodeIfPresent(MetricBinding.self, forKey: .legacyBinding) {
            self.channelBindings = [
                ChannelBinding(channelIndex: 0, metric: legacyBinding),
                ChannelBinding(channelIndex: 1, metric: legacyBinding)
            ]
        } else {
            self.channelBindings = []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moduleID, forKey: .moduleID)
        try container.encode(moduleType, forKey: .moduleType)
        try container.encode(channelBindings, forKey: .channelBindings)
    }

    func binding(for channelIndex: Int) -> ChannelBinding? {
        channelBindings.first(where: { $0.channelIndex == channelIndex })
    }

    static func `default`(for entry: RegistryEntry) -> ModuleSetting {
        switch entry.moduleType {
        case .radiance:
            return ModuleSetting(
                moduleID: entry.id,
                moduleType: .radiance,
                channelBindings: [
                    ChannelBinding(channelIndex: 0, metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: [0])),
                    ChannelBinding(channelIndex: 1, metric: MetricBinding(kind: .cpuCoreAverage, coreIndices: [0]))
                ]
            )
        case .balance:
            return ModuleSetting(
                moduleID: entry.id,
                moduleType: .balance,
                channelBindings: [
                    ChannelBinding(channelIndex: 0, metric: MetricBinding(kind: .none)),
                    ChannelBinding(channelIndex: 1, metric: MetricBinding(kind: .none))
                ]
            )
        case .unknown:
            return ModuleSetting(
                moduleID: entry.id,
                moduleType: .unknown,
                channelBindings: [
                    ChannelBinding(channelIndex: 0, metric: MetricBinding(kind: .cpuTotal))
                ]
            )
        }
    }

    mutating func updateChannelBinding(_ binding: ChannelBinding) {
        if let index = channelBindings.firstIndex(where: { $0.channelIndex == binding.channelIndex }) {
            channelBindings[index] = binding
        } else {
            channelBindings.append(binding)
            channelBindings.sort { $0.channelIndex < $1.channelIndex }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case moduleID
        case moduleType
        case channelBindings
        case legacyBinding = "binding"
    }
}

struct LUTPoint: Codable, Identifiable, Equatable {
    var input: Double
    var output: Double

    var id: Double { input }
}

struct CalibrationLUT: Codable, Identifiable, Equatable {
    let moduleID: Int
    let channelIndex: Int
    var points: [LUTPoint]
    var updatedAt: Date
    var legacyShared: Bool = false

    var id: String { "\(moduleID)-\(channelIndex)" }

    init(
        moduleID: Int,
        channelIndex: Int,
        points: [LUTPoint],
        updatedAt: Date,
        legacyShared: Bool = false
    ) {
        self.moduleID = moduleID
        self.channelIndex = channelIndex
        self.points = points
        self.updatedAt = updatedAt
        self.legacyShared = legacyShared
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        moduleID = try container.decode(Int.self, forKey: .moduleID)
        points = try container.decode([LUTPoint].self, forKey: .points)
        if let date = try? container.decode(Date.self, forKey: .updatedAt) {
            updatedAt = date
        } else if let epoch = try? container.decode(Double.self, forKey: .updatedAtEpoch) {
            updatedAt = Date(timeIntervalSince1970: epoch)
        } else if let epoch = try? container.decode(Int.self, forKey: .updatedAtEpoch) {
            updatedAt = Date(timeIntervalSince1970: Double(epoch))
        } else {
            updatedAt = .now
        }

        if let channelIndex = try container.decodeIfPresent(Int.self, forKey: .channelIndex) {
            self.channelIndex = channelIndex
            legacyShared = false
        } else {
            self.channelIndex = 0
            legacyShared = true
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(moduleID, forKey: .moduleID)
        try container.encode(channelIndex, forKey: .channelIndex)
        try container.encode(points, forKey: .points)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case moduleID
        case channelIndex
        case points
        case updatedAt
        case updatedAtEpoch
    }
}

struct CalibrationDraft: Identifiable, Equatable {
    let moduleID: Int
    let moduleType: ModuleType
    let channelIndex: Int
    var points: [LUTPoint]
    var stepIndex: Int

    var id: String { "\(moduleID)-\(channelIndex)" }

    var currentStep: LUTPoint {
        points[stepIndex]
    }
}

enum OutputPreviewMode: String, Codable, Equatable {
    case locate
    case calibration
}

struct OutputChannelPayload: Codable, Equatable {
    let moduleID: Int
    let channelIndex: Int
    let targetCode: Int

    init(
        moduleID: Int,
        channelIndex: Int,
        targetCode: Int
    ) {
        self.moduleID = moduleID
        self.channelIndex = channelIndex
        self.targetCode = targetCode
    }
}

struct OutputFrame: Codable, Equatable {
    let frameID: Int
    let channels: [OutputChannelPayload]
}

struct DiscoveredService: Identifiable, Equatable {
    let name: String
    var hostName: String?
    var port: Int?

    var id: String { name }

    var endpointLabel: String {
        switch (hostName, port) {
        case let (host?, port?) where !host.isEmpty:
            return "\(host):\(port)"
        case let (host?, _):
            return host
        case let (_, port?):
            return "端口 \(port)"
        default:
            return "解析中..."
        }
    }
}

struct ORBEndpoint: Equatable {
    let host: String
    let port: Int
}

extension ORBDeviceState {
    static let preview = ORBDeviceState(
        deviceName: "ORB-预览",
        firmwareVersion: "0.1.0",
        ip: "192.168.1.120",
        mac: "AA:BB:CC:DD:EE:FF",
        modules: [
            RegistryEntry(id: 1, registered: true, present: true, moduleType: .radiance),
            RegistryEntry(id: 2, registered: true, present: false, moduleType: .balance),
            RegistryEntry(id: 3, registered: true, present: true, moduleType: .radiance)
        ],
        detectedI2CAddresses: [0x60, 0x61, 0x62, 0x63],
        unknownI2CAddresses: [0x60],
        unknownCandidatePresent: false,
        calibrationLUTs: [],
        smoothing: DeviceSmoothingProfiles(
            radiance: DeviceSmoothingProfiles.defaultRadianceConfig,
            balance: DeviceSmoothingProfiles.defaultBalanceConfig
        ),
        stateRevision: 12,
        heartbeatIntervalMs: 1500,
        heartbeatDefaultPort: 43981,
        heartbeatTargetPort: 43981,
        heartbeatConfiguredPort: false,
        heartbeatDelivery: "udp_broadcast"
    )
}
