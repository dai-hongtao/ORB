import Foundation

enum ORBSessionError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(Int)
    case decodingFailed
    case fileReadFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "ORB 设备地址无法组成有效 URL。"
        case .invalidResponse:
            return "ORB 设备返回了无法识别的响应。"
        case .requestFailed(let code):
            return "ORB 设备返回了 HTTP \(code)。"
        case .decodingFailed:
            return "ORB 设备返回了无法解析的 JSON。"
        case .fileReadFailed:
            return "无法读取要上传的固件文件。"
        }
    }
}

struct ORBMutationResponse: Decodable {
    var ok: Bool?
}

struct ORBPreviewActivationResponse: Decodable {
    var ok: Bool?
    var previewActive: Bool?
    var mode: String?
    var moduleId: Int?
    var channelIndex: Int?
    var targetCode: Int?
}

struct ORBPingResponse: Decodable {
    var ok: Bool?
    var deviceName: String
    var firmwareVersion: String
    var ip: String
    var mac: String?
    var port: Int
    var stateRevision: Int
    var heartbeatIntervalMs: Int
    var heartbeatDefaultPort: Int?
    var heartbeatTargetPort: Int?
    var heartbeatConfiguredPort: Bool?
    var heartbeatDelivery: String?
}

struct ORBFrameResponse: Decodable {
    var ok: Bool?
    var frameId: Int?
    var applied: Int?
}

struct ORBHeartbeatConfigResponse: Decodable {
    var ok: Bool?
    var heartbeatDefaultPort: Int?
    var heartbeatTargetPort: Int?
    var heartbeatConfiguredPort: Bool?
    var heartbeatDelivery: String?
}

struct ORBFirmwareUploadResponse: Decodable {
    var ok: Bool?
    var rebooting: Bool?
    var message: String?
    var firmwareVersion: String?
}

@MainActor
final class ORBSession {
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func fetchState(from endpoint: ORBEndpoint) async throws -> ORBDeviceState {
        try await performRequest(
            path: "/api/v1/state",
            method: "GET",
            endpoint: endpoint
        )
    }

    func ping(endpoint: ORBEndpoint) async throws -> ORBPingResponse {
        try await performRequest(
            path: "/api/v1/ping",
            method: "GET",
            endpoint: endpoint
        )
    }

    func configureHeartbeat(
        listenerPort: Int,
        endpoint: ORBEndpoint
    ) async throws -> ORBHeartbeatConfigResponse {
        try await performFormRequest(
            path: "/api/v1/heartbeat/config",
            method: "POST",
            fields: [
                "udp_port": String(listenerPort)
            ],
            endpoint: endpoint
        )
    }

    func updateSmoothing(
        moduleType: ModuleType,
        config: SmoothingConfig,
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        try await performFormRequest(
            path: "/api/v1/smoothing",
            method: "POST",
            fields: [
                "module_type": String(moduleType.rawValue),
                "settle_time_ms": String(config.settleTimeMs),
                "a_max": String(format: "%.3f", config.aMax),
                "v_max": String(format: "%.3f", config.vMax),
                "jitter_frequency_hz": String(format: "%.3f", config.jitterFrequencyHz),
                "jitter_amplitude": String(format: "%.3f", config.jitterAmplitude),
                "jitter_dispersion": String(format: "%.3f", config.jitterDispersion)
            ],
            endpoint: endpoint
        )
    }

    func sendOutputs(
        _ frame: OutputFrame,
        endpoint: ORBEndpoint
    ) async throws {
        guard !frame.channels.isEmpty else { return }

        let channelPayload = frame.channels
            .map { "\($0.moduleID),\($0.channelIndex),\($0.targetCode)" }
            .joined(separator: ";")

        _ = try await performFormRequest(
            path: "/api/v1/frame",
            method: "POST",
            fields: [
                "frame_id": String(frame.frameID),
                "channels": channelPayload
            ],
            endpoint: endpoint
        ) as ORBFrameResponse
    }

    func activatePreview(
        mode: OutputPreviewMode,
        moduleID: Int,
        channelIndex: Int,
        targetCode: Int,
        endpoint: ORBEndpoint,
        timeoutInterval: TimeInterval = 0.75
    ) async throws -> ORBPreviewActivationResponse {
        try await performFormRequest(
            path: "/api/v1/preview",
            method: "POST",
            fields: [
                "mode": mode.rawValue,
                "module_id": String(moduleID),
                "channel_index": String(channelIndex),
                "target_code": String(targetCode)
            ],
            endpoint: endpoint,
            timeoutInterval: timeoutInterval
        )
    }

    func deleteModule(
        id: Int,
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        try await performFormRequest(
            path: "/api/v1/modules/delete",
            method: "POST",
            fields: [
                "id": String(id)
            ],
            endpoint: endpoint
        )
    }

    func registerModule(
        type: ModuleType,
        id: Int,
        address: Int,
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        try await performFormRequest(
            path: "/api/v1/modules/register",
            method: "POST",
            fields: [
                "module_type": String(type.rawValue),
                "id": String(id),
                "address": String(address)
            ],
            endpoint: endpoint
        )
    }

    func resetUnknownDevice(
        address: Int,
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        try await performFormRequest(
            path: "/api/v1/modules/reset",
            method: "POST",
            fields: [
                "address": String(address)
            ],
            endpoint: endpoint
        )
    }

    func writeI2CAddress(
        oldAddress: Int,
        newAddress: Int,
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        try await performFormRequest(
            path: "/api/v1/i2c/write_address",
            method: "POST",
            fields: [
                "old_address": String(oldAddress),
                "new_address": String(newAddress)
            ],
            endpoint: endpoint
        )
    }

    func saveCalibrationLUT(
        moduleID: Int,
        channelIndex: Int,
        points: [LUTPoint],
        endpoint: ORBEndpoint
    ) async throws -> ORBDeviceState {
        let payload = points
            .map { String(format: "%.4f:%.4f", $0.input, $0.output) }
            .joined(separator: ";")

        return try await performFormRequest(
            path: "/api/v1/calibration/save",
            method: "POST",
            fields: [
                "module_id": String(moduleID),
                "channel_index": String(channelIndex),
                "points": payload,
                "updated_at_epoch": String(Int(Date().timeIntervalSince1970))
            ],
            endpoint: endpoint
        )
    }

    func uploadFirmware(
        fileURL: URL,
        endpoint: ORBEndpoint
    ) async throws -> ORBFirmwareUploadResponse {
        let needsScopedAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if needsScopedAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw ORBSessionError.fileReadFailed
        }

        let boundary = "ORB-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"firmware\"; filename=\"\(fileURL.lastPathComponent)\"\r\n")
        body.append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        let url = try makeURL(endpoint: endpoint, path: "/api/v1/firmware/upload")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 180
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        NSLog("ORB 会话：上传固件 %@ -> %@", fileURL.lastPathComponent, url.absoluteString)
        do {
            let (data, response) = try await URLSession.shared.upload(for: request, from: body)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ORBSessionError.invalidResponse
            }
            guard (200..<300).contains(httpResponse.statusCode) else {
                NSLog("ORB 会话：固件上传返回 HTTP %ld", httpResponse.statusCode)
                throw ORBSessionError.requestFailed(httpResponse.statusCode)
            }
            do {
                return try decoder.decode(ORBFirmwareUploadResponse.self, from: data)
            } catch {
                NSLog("ORB 会话：固件上传响应解码失败，正文=%@", String(decoding: data, as: UTF8.self))
                throw ORBSessionError.decodingFailed
            }
        } catch {
            NSLog("ORB 会话：固件上传失败，原因：%@", error.localizedDescription)
            throw error
        }
    }

    private func performRequest<Response: Decodable>(
        path: String,
        method: String,
        endpoint: ORBEndpoint,
        timeoutInterval: TimeInterval = 5
    ) async throws -> Response {
        let url = try makeURL(endpoint: endpoint, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval

        NSLog("ORB 会话：%@ %@", method, url.absoluteString)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ORBSessionError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                NSLog("ORB 会话：%@ 返回 HTTP %ld", url.absoluteString, httpResponse.statusCode)
                throw ORBSessionError.requestFailed(httpResponse.statusCode)
            }

            NSLog("ORB 会话：%@ 成功，收到 %ld 字节", url.absoluteString, data.count)
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                NSLog("ORB 会话：%@ JSON 解码失败，响应正文=%@", url.absoluteString, String(decoding: data, as: UTF8.self))
                throw ORBSessionError.decodingFailed
            }
        } catch {
            NSLog("ORB 会话：%@ 失败，原因：%@", url.absoluteString, error.localizedDescription)
            throw error
        }
    }

    private func performRequest<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body,
        endpoint: ORBEndpoint,
        timeoutInterval: TimeInterval = 5
    ) async throws -> Response {
        let url = try makeURL(endpoint: endpoint, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval

        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        NSLog("ORB 会话：%@ %@", method, url.absoluteString)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ORBSessionError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                NSLog("ORB 会话：%@ 返回 HTTP %ld", url.absoluteString, httpResponse.statusCode)
                throw ORBSessionError.requestFailed(httpResponse.statusCode)
            }

            NSLog("ORB 会话：%@ 成功，收到 %ld 字节", url.absoluteString, data.count)
            if data.isEmpty, Response.self == ORBMutationResponse.self {
                return ORBMutationResponse(ok: true) as! Response
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                NSLog("ORB 会话：%@ JSON 解码失败，响应正文=%@", url.absoluteString, String(decoding: data, as: UTF8.self))
                throw ORBSessionError.decodingFailed
            }
        } catch {
            NSLog("ORB 会话：%@ 失败，原因：%@", url.absoluteString, error.localizedDescription)
            throw error
        }
    }

    private func performFormRequest<Response: Decodable>(
        path: String,
        method: String,
        fields: [String: String],
        endpoint: ORBEndpoint,
        timeoutInterval: TimeInterval = 5
    ) async throws -> Response {
        let url = try makeURL(endpoint: endpoint, path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeoutInterval
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(percentEncode(key))=\(percentEncode(value))"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        NSLog("ORB 会话：%@ %@ 表单=%@", method, url.absoluteString, fields.description)
        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw ORBSessionError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                NSLog("ORB 会话：%@ 返回 HTTP %ld，正文=%@", url.absoluteString, httpResponse.statusCode, String(decoding: data, as: UTF8.self))
                throw ORBSessionError.requestFailed(httpResponse.statusCode)
            }

            NSLog("ORB 会话：%@ 成功，收到 %ld 字节", url.absoluteString, data.count)
            if data.isEmpty, Response.self == ORBMutationResponse.self {
                return ORBMutationResponse(ok: true) as! Response
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                NSLog("ORB 会话：%@ JSON 解码失败，响应正文=%@", url.absoluteString, String(decoding: data, as: UTF8.self))
                throw ORBSessionError.decodingFailed
            }
        } catch {
            NSLog("ORB 会话：%@ 失败，原因：%@", url.absoluteString, error.localizedDescription)
            throw error
        }
    }

    private func makeURL(endpoint: ORBEndpoint, path: String) throws -> URL {
        var components = URLComponents()
        components.scheme = "http"
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = path

        guard let url = components.url else {
            throw ORBSessionError.invalidURL
        }

        return url
    }

    private func percentEncode(_ string: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8) ?? Data())
    }
}
