import Foundation
import Darwin

enum DeviceDiscoveryError: LocalizedError {
    case noService
    case unknownService
    case resolveFailed

    var errorDescription: String? {
        switch self {
        case .noService:
            return "当前没有可发现的 ORB 设备。"
        case .unknownService:
            return "请求的 ORB 服务已经不可用了。"
        case .resolveFailed:
            return "Bonjour 已返回解析结果，但没有得到可用的主机名或端口。"
        }
    }
}

@MainActor
final class DeviceDiscoveryService: NSObject {
    private let browser = NetServiceBrowser()
    private var servicesByName: [String: NetService] = [:]
    private var resolvedEndpointsByName: [String: ORBEndpoint] = [:]
    private var resolvingServiceNames: Set<String> = []
    private var pendingContinuationsByServiceName: [String: [CheckedContinuation<ORBEndpoint, Error>]] = [:]

    var onServicesChanged: (([DiscoveredService]) -> Void)?

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        NSLog("ORB 发现：开始浏览 _orb._tcp.local.")
        browser.searchForServices(ofType: "_orb._tcp.", inDomain: "local.")
    }

    func stop() {
        NSLog("ORB 发现：停止浏览")
        browser.stop()
        servicesByName.values.forEach { $0.stop() }
        finishPendingResolutions(throwing: DeviceDiscoveryError.resolveFailed)
        servicesByName.removeAll()
        resolvedEndpointsByName.removeAll()
        resolvingServiceNames.removeAll()
        publishServices()
    }

    func resolveFirst() async throws -> ORBEndpoint {
        guard let first = servicesByName.keys.sorted().first else {
            throw DeviceDiscoveryError.noService
        }
        return try await resolve(serviceNamed: first)
    }

    func resolve(serviceNamed name: String) async throws -> ORBEndpoint {
        if let resolved = resolvedEndpointsByName[name] {
            NSLog("ORB 发现：命中缓存解析结果 %@ -> %@:%ld", name, resolved.host, resolved.port)
            return resolved
        }

        guard let service = servicesByName[name] else {
            NSLog("ORB 发现：尝试解析未知服务 %@", name)
            throw DeviceDiscoveryError.unknownService
        }

        return try await withCheckedThrowingContinuation { continuation in
            pendingContinuationsByServiceName[name, default: []].append(continuation)
            beginResolving(service)
        }
    }

    private func publishServices() {
        let services = servicesByName.values
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map {
                let resolved = resolvedEndpointsByName[$0.name]
                return DiscoveredService(
                    name: $0.name,
                    hostName: resolved?.host ?? resolvedHost(for: $0),
                    port: resolved?.port ?? ($0.port > 0 ? Int($0.port) : nil)
                )
            }

        NSLog(
            "ORB 发现：当前可见服务数 %ld，列表：%@",
            services.count,
            services.map(\.name).joined(separator: ", ")
        )
        onServicesChanged?(services)
    }

    private func resolvedHost(for service: NetService) -> String? {
        if let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty {
            return host
        }

        guard let addresses = service.addresses else {
            return nil
        }

        for address in addresses {
            let host: String? = address.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else { return nil }
                let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
                var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    socketAddress,
                    socklen_t(socketAddress.pointee.sa_len),
                    &hostBuffer,
                    socklen_t(hostBuffer.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                guard result == 0 else { return nil }
                return String(cString: hostBuffer)
            }

            if let host, !host.isEmpty {
                return host
            }
        }

        return nil
    }

    private func beginResolving(_ service: NetService) {
        guard !resolvingServiceNames.contains(service.name) else {
            return
        }

        resolvingServiceNames.insert(service.name)
        service.delegate = self
        service.stop()
        NSLog("ORB 发现：开始解析服务 %@", service.name)
        service.resolve(withTimeout: 5)
    }

    private func finishPendingResolutions(
        for serviceName: String,
        returning endpoint: ORBEndpoint
    ) {
        let continuations = pendingContinuationsByServiceName.removeValue(forKey: serviceName) ?? []
        continuations.forEach { $0.resume(returning: endpoint) }
    }

    private func finishPendingResolutions(
        for serviceName: String,
        throwing error: Error
    ) {
        let continuations = pendingContinuationsByServiceName.removeValue(forKey: serviceName) ?? []
        continuations.forEach { $0.resume(throwing: error) }
    }

    private func finishPendingResolutions(throwing error: Error) {
        let pendingContinuations = pendingContinuationsByServiceName
        pendingContinuationsByServiceName.removeAll()
        for continuations in pendingContinuations.values {
            continuations.forEach { $0.resume(throwing: error) }
        }
    }
}

extension DeviceDiscoveryService: NetServiceBrowserDelegate {
    func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        NSLog("ORB 发现：Bonjour 浏览已启动")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        NSLog("ORB 发现：Bonjour 浏览失败 %@", errorDict)
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        NSLog("ORB 发现：Bonjour 浏览已停止")
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        servicesByName[service.name] = service
        NSLog("ORB 发现：找到服务 %@，moreComing=%@", service.name, moreComing ? "true" : "false")
        beginResolving(service)
        publishServices()
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        servicesByName.removeValue(forKey: service.name)
        resolvedEndpointsByName.removeValue(forKey: service.name)
        resolvingServiceNames.remove(service.name)
        finishPendingResolutions(for: service.name, throwing: DeviceDiscoveryError.unknownService)
        NSLog("ORB 发现：服务移除 %@，moreComing=%@", service.name, moreComing ? "true" : "false")
        publishServices()
    }
}

extension DeviceDiscoveryService: NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        resolvingServiceNames.remove(sender.name)

        guard
            let host = resolvedHost(for: sender),
            sender.port > 0
        else {
            NSLog(
                "ORB 发现：服务 %@ 解析后缺少主机或端口，host=%@ port=%ld",
                sender.name,
                sender.hostName ?? "nil",
                Int(sender.port)
            )
            finishPendingResolutions(for: sender.name, throwing: DeviceDiscoveryError.resolveFailed)
            publishServices()
            return
        }

        let endpoint = ORBEndpoint(host: host, port: Int(sender.port))
        resolvedEndpointsByName[sender.name] = endpoint
        publishServices()

        guard pendingContinuationsByServiceName[sender.name]?.isEmpty == false else {
            NSLog("ORB 发现：服务 %@ 已解析，维护模式可直接显示 %@", sender.name, endpoint.host)
            return
        }

        NSLog("ORB 发现：服务 %@ 解析成功 -> %@:%ld", sender.name, endpoint.host, endpoint.port)
        finishPendingResolutions(for: sender.name, returning: endpoint)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        NSLog("ORB 发现：服务 %@ 解析失败 %@", sender.name, errorDict)
        resolvingServiceNames.remove(sender.name)
        finishPendingResolutions(for: sender.name, throwing: DeviceDiscoveryError.resolveFailed)
        publishServices()
    }
}
