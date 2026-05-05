import Darwin
import Foundation
import IOKit

private struct NetworkCounters {
    var receivedBytes: UInt64
    var sentBytes: UInt64
}

private struct DiskCounters {
    var readBytes: UInt64
    var writeBytes: UInt64
}

actor SystemMetricsService {
    private var previousCPUTicks: [[UInt32]]?
    private var previousNetworkCounters: NetworkCounters?
    private var previousDiskCounters: DiskCounters?
    private var previousSampleDate: Date?

    func sample() -> SystemMetricsSnapshot {
        let now = Date()
        let elapsed = previousSampleDate.map { max(now.timeIntervalSince($0), 0.001) } ?? 0

        let (totalCPUUsagePercent, cpuCoreLoads) = sampleCPU()
        let (memoryUsedBytes, memoryTotalBytes) = sampleMemory()
        let currentNetworkCounters = sampleNetworkCounters()
        let currentDiskCounters = sampleDiskCounters()
        let gpuUsagePercent = sampleGPUUsage()

        let networkReceiveBytesPerSecond: Double
        let networkSendBytesPerSecond: Double
        if let previousNetworkCounters, elapsed > 0 {
            networkReceiveBytesPerSecond = bytesPerSecond(
                current: currentNetworkCounters.receivedBytes,
                previous: previousNetworkCounters.receivedBytes,
                elapsed: elapsed
            )
            networkSendBytesPerSecond = bytesPerSecond(
                current: currentNetworkCounters.sentBytes,
                previous: previousNetworkCounters.sentBytes,
                elapsed: elapsed
            )
        } else {
            networkReceiveBytesPerSecond = 0
            networkSendBytesPerSecond = 0
        }

        let diskReadBytesPerSecond: Double
        let diskWriteBytesPerSecond: Double
        if let previousDiskCounters, elapsed > 0 {
            diskReadBytesPerSecond = bytesPerSecond(
                current: currentDiskCounters.readBytes,
                previous: previousDiskCounters.readBytes,
                elapsed: elapsed
            )
            diskWriteBytesPerSecond = bytesPerSecond(
                current: currentDiskCounters.writeBytes,
                previous: previousDiskCounters.writeBytes,
                elapsed: elapsed
            )
        } else {
            diskReadBytesPerSecond = 0
            diskWriteBytesPerSecond = 0
        }

        previousNetworkCounters = currentNetworkCounters
        previousDiskCounters = currentDiskCounters
        previousSampleDate = now

        return SystemMetricsSnapshot(
            sampledAt: now,
            totalCPUUsagePercent: totalCPUUsagePercent,
            cpuCoreLoads: cpuCoreLoads,
            memoryUsedBytes: memoryUsedBytes,
            memoryTotalBytes: memoryTotalBytes,
            networkReceiveBytesPerSecond: networkReceiveBytesPerSecond,
            networkSendBytesPerSecond: networkSendBytesPerSecond,
            diskReadBytesPerSecond: diskReadBytesPerSecond,
            diskWriteBytesPerSecond: diskWriteBytesPerSecond,
            gpuUsagePercent: gpuUsagePercent
        )
    }

    private func sampleCPU() -> (Double, [CPUCoreLoad]) {
        var cpuCount: natural_t = 0
        var cpuInfo: processor_info_array_t?
        var cpuInfoCount: mach_msg_type_number_t = 0

        let result = withUnsafeMutablePointer(to: &cpuInfo) {
            $0.withMemoryRebound(to: processor_info_array_t?.self, capacity: 1) { pointer in
                host_processor_info(
                    mach_host_self(),
                    PROCESSOR_CPU_LOAD_INFO,
                    &cpuCount,
                    pointer,
                    &cpuInfoCount
                )
            }
        }

        guard result == KERN_SUCCESS, let cpuInfo else {
            return (0, [])
        }

        let cpuInfoBuffer = UnsafeBufferPointer(start: cpuInfo, count: Int(cpuInfoCount))
        let stride = Int(CPU_STATE_MAX)
        var currentTicks: [[UInt32]] = []
        currentTicks.reserveCapacity(Int(cpuCount))

        for index in 0..<Int(cpuCount) {
            let base = index * stride
            currentTicks.append(
                (0..<stride).map { cpuInfoBuffer[base + $0] }.map(UInt32.init)
            )
        }

        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: cpuInfo),
            vm_size_t(Int(cpuInfoCount) * MemoryLayout<integer_t>.stride)
        )

        defer {
            previousCPUTicks = currentTicks
        }

        guard let previousCPUTicks, previousCPUTicks.count == currentTicks.count else {
            return (
                0,
                currentTicks.enumerated().map { index, _ in
                    CPUCoreLoad(index: index, usagePercent: 0)
                }
            )
        }

        let coreLoads = zip(currentTicks.indices, zip(currentTicks, previousCPUTicks)).map { index, pair in
            let current = pair.0
            let previous = pair.1

            let user = tickDelta(current[Int(CPU_STATE_USER)], previous[Int(CPU_STATE_USER)])
            let system = tickDelta(current[Int(CPU_STATE_SYSTEM)], previous[Int(CPU_STATE_SYSTEM)])
            let nice = tickDelta(current[Int(CPU_STATE_NICE)], previous[Int(CPU_STATE_NICE)])
            let idle = tickDelta(current[Int(CPU_STATE_IDLE)], previous[Int(CPU_STATE_IDLE)])

            let busy = Double(user + system + nice)
            let total = busy + Double(idle)
            let usagePercent = total > 0 ? busy / total * 100 : 0

            return CPUCoreLoad(index: index, usagePercent: usagePercent)
        }

        let totalCPUUsagePercent = coreLoads.isEmpty
            ? 0
            : coreLoads.reduce(0) { $0 + $1.usagePercent } / Double(coreLoads.count)

        return (totalCPUUsagePercent, coreLoads)
    }

    private func sampleMemory() -> (UInt64, UInt64) {
        var pageSize: vm_size_t = 0
        host_page_size(mach_host_self(), &pageSize)

        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { pointer in
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    pointer,
                    &count
                )
            }
        }

        let totalMemory = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return (0, totalMemory)
        }

        let usedPages =
            UInt64(statistics.active_count) +
            UInt64(statistics.wire_count) +
            UInt64(statistics.compressor_page_count)

        return (usedPages * UInt64(pageSize), totalMemory)
    }

    private func sampleNetworkCounters() -> NetworkCounters {
        var totalReceivedBytes: UInt64 = 0
        var totalSentBytes: UInt64 = 0

        var interfaceAddresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaceAddresses) == 0, let interfaceAddresses else {
            return NetworkCounters(receivedBytes: 0, sentBytes: 0)
        }

        defer {
            freeifaddrs(interfaceAddresses)
        }

        var cursor: UnsafeMutablePointer<ifaddrs>? = interfaceAddresses
        while let entry = cursor?.pointee {
            defer {
                cursor = entry.ifa_next
            }

            let flags = Int32(entry.ifa_flags)
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            guard
                entry.ifa_addr.pointee.sa_family == UInt8(AF_LINK),
                !isLoopback,
                let rawData = entry.ifa_data
            else {
                continue
            }

            let interfaceData = rawData.assumingMemoryBound(to: if_data.self).pointee
            totalReceivedBytes += UInt64(interfaceData.ifi_ibytes)
            totalSentBytes += UInt64(interfaceData.ifi_obytes)
        }

        return NetworkCounters(receivedBytes: totalReceivedBytes, sentBytes: totalSentBytes)
    }

    private func sampleDiskCounters() -> DiskCounters {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
        guard result == KERN_SUCCESS else {
            return DiskCounters(readBytes: 0, writeBytes: 0)
        }

        defer {
            IOObjectRelease(iterator)
        }

        var totalReadBytes: UInt64 = 0
        var totalWriteBytes: UInt64 = 0

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            guard
                let statistics = IORegistryEntryCreateCFProperty(
                    service,
                    "Statistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any]
            else {
                continue
            }

            totalReadBytes += uint64Value(from: statistics["Bytes (Read)"])
            totalWriteBytes += uint64Value(from: statistics["Bytes (Write)"])
        }

        return DiskCounters(readBytes: totalReadBytes, writeBytes: totalWriteBytes)
    }

    private func sampleGPUUsage() -> Double? {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
        guard result == KERN_SUCCESS else {
            return nil
        }

        defer {
            IOObjectRelease(iterator)
        }

        var bestUsage: Double?

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer {
                IOObjectRelease(service)
            }

            guard
                let statistics = IORegistryEntryCreateCFProperty(
                    service,
                    "PerformanceStatistics" as CFString,
                    kCFAllocatorDefault,
                    0
                )?.takeRetainedValue() as? [String: Any]
            else {
                continue
            }

            let deviceUsage = doubleValue(from: statistics["Device Utilization %"])
            let rendererUsage = doubleValue(from: statistics["Renderer Utilization %"])
            let tilerUsage = doubleValue(from: statistics["Tiler Utilization %"])
            let usage = deviceUsage ?? rendererUsage ?? tilerUsage

            if let usage {
                bestUsage = max(bestUsage ?? 0, usage)
            }
        }

        return bestUsage
    }

    private func uint64Value(from rawValue: Any?) -> UInt64 {
        if let number = rawValue as? NSNumber {
            return number.uint64Value
        }

        if let value = rawValue as? UInt64 {
            return value
        }

        if let value = rawValue as? Int {
            return UInt64(max(value, 0))
        }

        return 0
    }

    private func doubleValue(from rawValue: Any?) -> Double? {
        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }

        if let value = rawValue as? Double {
            return value
        }

        if let value = rawValue as? Int {
            return Double(value)
        }

        return nil
    }

    private func bytesPerSecond(current: UInt64, previous: UInt64, elapsed: TimeInterval) -> Double {
        guard current >= previous, elapsed > 0 else {
            return 0
        }

        return Double(current - previous) / elapsed
    }

    private func tickDelta(_ current: UInt32, _ previous: UInt32) -> UInt32 {
        current >= previous ? current - previous : 0
    }
}
