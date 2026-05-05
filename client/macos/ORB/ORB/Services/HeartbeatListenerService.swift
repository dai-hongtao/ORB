import Foundation
import Network

enum HeartbeatListenerMode: Equatable {
    case preferredUDP
    case dynamicUDP
    case unavailable
}

struct HeartbeatListenerStatus: Equatable {
    var mode: HeartbeatListenerMode
    var localPort: Int?
    var message: String?

    static let booting = HeartbeatListenerStatus(
        mode: .unavailable,
        localPort: nil,
        message: "UDP 心跳监听正在启动。"
    )

    var isAvailable: Bool {
        mode != .unavailable && localPort != nil
    }
}

final class HeartbeatListenerService {
    static let preferredPort: UInt16 = 43981

    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "orb.heartbeat.listener", qos: .userInitiated)
    private var listener: NWListener?
    private var hasRetriedWithDynamicPort = false

    var onHeartbeat: ((ORBHeartbeat) -> Void)?
    var onStatusChanged: ((HeartbeatListenerStatus) -> Void)?

    init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    func start() {
        guard listener == nil else { return }
        hasRetriedWithDynamicPort = false
        publishStatus(.booting)
        startListener(requestedPort: Self.preferredPort)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        hasRetriedWithDynamicPort = false
        publishStatus(.booting)
    }

    private func startListener(requestedPort: UInt16?) {
        do {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            let endpointPort = requestedPort.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
            let listener = try NWListener(using: parameters, on: endpointPort)
            let usesPreferredPort = requestedPort == Self.preferredPort

            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self else { return }
                NSLog("ORB 心跳：监听状态=%@", String(describing: state))

                switch state {
                case .ready:
                    let actualPort = Int(listener?.port?.rawValue ?? requestedPort ?? 0)
                    if usesPreferredPort {
                        self.publishStatus(
                            HeartbeatListenerStatus(
                                mode: .preferredUDP,
                                localPort: actualPort,
                                message: "UDP 心跳已监听默认端口 \(actualPort)。"
                            )
                        )
                        NSLog("ORB 心跳：开始监听 UDP %d（默认端口）", actualPort)
                    } else {
                        self.publishStatus(
                            HeartbeatListenerStatus(
                                mode: .dynamicUDP,
                                localPort: actualPort,
                                message: "固定端口 \(Self.preferredPort) 不可用，已改监听动态端口 \(actualPort)。"
                            )
                        )
                        NSLog("ORB 心跳：开始监听 UDP %d（动态端口）", actualPort)
                    }
                case .waiting(let error), .failed(let error):
                    if usesPreferredPort && !self.hasRetriedWithDynamicPort {
                        self.hasRetriedWithDynamicPort = true
                        NSLog("ORB 心跳：默认端口 %u 不可用，准备切换动态端口，原因：%@", Self.preferredPort, error.localizedDescription)
                        listener?.cancel()
                        self.listener = nil
                        self.startListener(requestedPort: nil)
                        return
                    }

                    self.publishStatus(
                        HeartbeatListenerStatus(
                            mode: .unavailable,
                            localPort: nil,
                            message: "UDP 心跳不可用：\(error.localizedDescription)。当前会改用 Bonjour + HTTP ping/state。"
                        )
                    )
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.startReceiving(on: connection)
            }

            self.listener = listener
            listener.start(queue: queue)
        } catch {
            if requestedPort == Self.preferredPort && !hasRetriedWithDynamicPort {
                hasRetriedWithDynamicPort = true
                NSLog("ORB 心跳：默认端口 %u 创建失败，改尝试动态端口，原因：%@", Self.preferredPort, error.localizedDescription)
                startListener(requestedPort: nil)
                return
            }

            NSLog("ORB 心跳：启动失败，原因：%@", error.localizedDescription)
            publishStatus(
                HeartbeatListenerStatus(
                    mode: .unavailable,
                    localPort: nil,
                    message: "UDP 心跳端口无法监听：\(error.localizedDescription)。当前会改用 Bonjour + HTTP ping/state。"
                )
            )
        }
    }

    private func publishStatus(_ status: HeartbeatListenerStatus) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.onStatusChanged?(status)
        }
    }

    private func startReceiving(on connection: NWConnection) {
        connection.start(queue: queue)
        receiveNextMessage(on: connection)
    }

    private func receiveNextMessage(on connection: NWConnection) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }

            if let error {
                NSLog("ORB 心跳：接收失败，原因：%@", error.localizedDescription)
                connection.cancel()
                return
            }

            if let data, !data.isEmpty {
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    do {
                        var heartbeat = try self.decoder.decode(ORBHeartbeat.self, from: data)
                        heartbeat.receivedAt = .now
                        self.onHeartbeat?(heartbeat)
                    } catch {
                        NSLog("ORB 心跳：解码失败，正文=%@", String(decoding: data, as: UTF8.self))
                    }
                }
            }

            self.receiveNextMessage(on: connection)
        }
    }
}
