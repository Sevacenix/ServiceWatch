import Foundation

struct AuthorizationArchive: Codable {
    var schemaVersion = 2
    var services: [Service]
    var changes: [ServiceChange] = []
    func migrated() throws -> AuthorizationArchive {
        guard [1, 2].contains(schemaVersion) else { throw AuthorizationStorageError.unsupportedVersion }
        var result = self
        result.schemaVersion = 2
        result.services = services.map { service in
            guard service.renewalPlan == nil else { return service }
            var value = service
            value.renewalPlan = RenewalPlan.migrate(service: service, history: changes)
            return value
        }
        return result
    }
}

enum AuthorizationStorageError: LocalizedError {
    case unsupportedVersion, invalidRecords, unavailable
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "本地数据版本不兼容，已停止写入以保留原文件。"
        case .invalidRecords: "数据包含重复标识、无效授权或扣款记录，已保留原文件。"
        case .unavailable: "原有数据未能读取，暂不能保存。请先处理读取错误。"
        }
    }
}

struct AuthorizationRepository {
    let fileURL: URL
    static var defaultURL: URL {
        #if DEBUG
        // A test bundle keeps its isolation even if Launch Services opens it without arguments.
        if Bundle.main.object(forInfoDictionaryKey: "ServiceWatchIsolatedData") as? Bool == true {
            return Bundle.main.bundleURL.deletingLastPathComponent()
                .appendingPathComponent("data", isDirectory: true).appendingPathComponent("authorizations.json")
        }
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "--data-file"), args.indices.contains(flag + 1), args[flag + 1].hasPrefix("/") {
            return URL(fileURLWithPath: args[flag + 1])
        }
        #endif
        return defaultProductionURL
    }
    static var defaultProductionURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ServiceWatch Open", isDirectory: true).appendingPathComponent("authorizations.json")
    }
    func load() throws -> AuthorizationArchive? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let archive = try JSONDecoder().decode(AuthorizationArchive.self, from: Data(contentsOf: fileURL)).migrated()
        try validate(archive)
        return archive
    }
    func save(_ archive: AuthorizationArchive) throws {
        try validate(archive)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(archive)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: fileURL.path),
           let previous = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any],
           previous["schemaVersion"] as? Int == 1 {
            let backup = fileURL.deletingLastPathComponent().appendingPathComponent("authorizations-v1-backup-\(UUID().uuidString).json")
            try FileManager.default.copyItem(at: fileURL, to: backup)
        }
        try data.write(to: fileURL, options: .atomic)
    }
    private func validate(_ archive: AuthorizationArchive) throws {
        guard archive.schemaVersion == 2 else { throw AuthorizationStorageError.unsupportedVersion }
        guard Set(archive.services.map(\.id)).count == archive.services.count else { throw AuthorizationStorageError.invalidRecords }
        for service in archive.services {
            guard service.renewalPlan?.isValid ?? true else { throw AuthorizationStorageError.invalidRecords }
            guard !service.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  Set(service.entitlements.map(\.id)).count == service.entitlements.count else { throw AuthorizationStorageError.invalidRecords }
            for entitlement in service.entitlements {
                guard !entitlement.tier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !(entitlement.perpetual && entitlement.expires != nil),
                      entitlement.expires.map({ ServiceDate.parse($0) != nil }) ?? true else { throw AuthorizationStorageError.invalidRecords }
            }
        }
    }
}
