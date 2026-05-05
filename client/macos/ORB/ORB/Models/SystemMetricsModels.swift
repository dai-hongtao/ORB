import Foundation

enum CPUCoreKind: String, Codable, Equatable {
    case performance
    case efficiency
    case unknown

    var label: String {
        switch self {
        case .performance:
            return "性能核心"
        case .efficiency:
            return "能效核心"
        case .unknown:
            return "未分类核心"
        }
    }
}

struct CPUCoreDescriptor: Identifiable, Equatable {
    let index: Int
    let kind: CPUCoreKind

    var id: Int { index }
}

struct CPUCoreLoad: Identifiable, Equatable {
    let index: Int
    let usagePercent: Double

    var id: Int { index }
}

struct SystemMetricsSnapshot: Equatable {
    var sampledAt: Date
    var totalCPUUsagePercent: Double
    var cpuCoreLoads: [CPUCoreLoad]
    var memoryUsedBytes: UInt64
    var memoryTotalBytes: UInt64
    var networkReceiveBytesPerSecond: Double
    var networkSendBytesPerSecond: Double
    var diskReadBytesPerSecond: Double
    var diskWriteBytesPerSecond: Double
    var gpuUsagePercent: Double?

    static let empty = SystemMetricsSnapshot(
        sampledAt: .distantPast,
        totalCPUUsagePercent: 0,
        cpuCoreLoads: [],
        memoryUsedBytes: 0,
        memoryTotalBytes: 0,
        networkReceiveBytesPerSecond: 0,
        networkSendBytesPerSecond: 0,
        diskReadBytesPerSecond: 0,
        diskWriteBytesPerSecond: 0,
        gpuUsagePercent: nil
    )

    static let preview = SystemMetricsSnapshot(
        sampledAt: Date(),
        totalCPUUsagePercent: 37.4,
        cpuCoreLoads: [
            CPUCoreLoad(index: 0, usagePercent: 44.2),
            CPUCoreLoad(index: 1, usagePercent: 38.5),
            CPUCoreLoad(index: 2, usagePercent: 21.3),
            CPUCoreLoad(index: 3, usagePercent: 19.9),
            CPUCoreLoad(index: 4, usagePercent: 54.7),
            CPUCoreLoad(index: 5, usagePercent: 47.8),
            CPUCoreLoad(index: 6, usagePercent: 25.4),
            CPUCoreLoad(index: 7, usagePercent: 18.6)
        ],
        memoryUsedBytes: 28 * 1_024 * 1_024 * 1_024,
        memoryTotalBytes: 64 * 1_024 * 1_024 * 1_024,
        networkReceiveBytesPerSecond: 8_420_000,
        networkSendBytesPerSecond: 1_640_000,
        diskReadBytesPerSecond: 3_200_000,
        diskWriteBytesPerSecond: 980_000,
        gpuUsagePercent: 12
    )

    var memoryUsagePercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }
}
