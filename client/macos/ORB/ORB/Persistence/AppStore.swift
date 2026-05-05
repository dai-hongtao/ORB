import Foundation

struct StoredAppState: Codable {
    var layout: [LayoutSlot] = [LayoutSlot.source]
    var moduleSettings: [ModuleSetting] = []
    var refreshInterval: Double = 0.5
    var motionDurationFactor: Double = 0.7
    var calibrationLUTs: [CalibrationLUT] = []
    var appLanguage: AppLanguage = .system

    init(
        layout: [LayoutSlot] = [LayoutSlot.source],
        moduleSettings: [ModuleSetting] = [],
        refreshInterval: Double = 0.5,
        motionDurationFactor: Double = 0.7,
        calibrationLUTs: [CalibrationLUT] = [],
        appLanguage: AppLanguage = .system
    ) {
        self.layout = layout
        self.moduleSettings = moduleSettings
        self.refreshInterval = refreshInterval
        self.motionDurationFactor = motionDurationFactor
        self.calibrationLUTs = calibrationLUTs
        self.appLanguage = appLanguage
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        layout = try container.decodeIfPresent([LayoutSlot].self, forKey: .layout) ?? [LayoutSlot.source]
        moduleSettings = try container.decodeIfPresent([ModuleSetting].self, forKey: .moduleSettings) ?? []
        refreshInterval = try container.decodeIfPresent(Double.self, forKey: .refreshInterval) ?? 0.5
        motionDurationFactor = try container.decodeIfPresent(Double.self, forKey: .motionDurationFactor) ?? 0.7
        calibrationLUTs = try container.decodeIfPresent([CalibrationLUT].self, forKey: .calibrationLUTs) ?? []
        appLanguage = try container.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? .system
    }
}

final class AppStore {
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let saveQueue = DispatchQueue(label: "orb.app-store.save", qos: .utility)

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() -> StoredAppState {
        guard let data = try? Data(contentsOf: stateURL) else {
            return StoredAppState()
        }

        do {
            return try decoder.decode(StoredAppState.self, from: data)
        } catch {
            NSLog("ORB 读取应用状态失败，已回退到默认状态：\(error.localizedDescription)")
            return StoredAppState()
        }
    }

    func save(_ state: StoredAppState) {
        let fileManager = self.fileManager
        let baseDirectory = self.baseDirectory
        let stateURL = self.stateURL

        do {
            let data = try encoder.encode(state)
            saveQueue.async {
                do {
                    try fileManager.createDirectory(
                        at: baseDirectory,
                        withIntermediateDirectories: true
                    )
                    try data.write(to: stateURL, options: .atomic)
                } catch {
                    NSLog("ORB 保存应用状态失败：\(error.localizedDescription)")
                }
            }
        } catch {
            NSLog("ORB 保存应用状态失败：\(error.localizedDescription)")
        }
    }

    private var baseDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORB", isDirectory: true)
    }

    private var stateURL: URL {
        baseDirectory.appendingPathComponent("app_state.json", isDirectory: false)
    }
}
