import Foundation
import AppKit
import ImageIO
import CryptoKit
import Observation

enum BrandIconSource {
    static func allowed(_ url: URL) -> Bool {
        url.scheme == "https" && ["deals-cdn.iplaysoft.com", "deals.iplaysoft.com"].contains(url.host ?? "") &&
        url.user == nil && url.password == nil && url.port == nil && url.query == nil &&
        url.path.range(of: "^/assets/icons/[A-Za-z0-9_-]+\\.(png|jpg|jpeg|webp|ico|icns)$", options: .regularExpression) != nil
    }
    static func filename(_ source: String) -> String {
        SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined() + ".image"
    }
    static func validCustomName(_ name: String) -> Bool {
        name.range(of: "^custom-[A-Fa-f0-9-]{36}\\.image$", options: .regularExpression) != nil
    }
}

private final class BrandIconRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(BrandIconSource.allowed) == true ? request : nil)
    }
}

protocol BrandIconFetching: Sendable {
    func data(_ url: URL) async throws -> Data
}

private actor BrandIconDownloads: BrandIconFetching {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var nextStart = Date.distantPast
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil; config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 20; config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config, delegate: BrandIconRedirects(), delegateQueue: nil)
    }
    func data(_ url: URL) async throws -> Data {
        guard BrandIconSource.allowed(url) else { throw CatalogError.invalid(tr("不支持的图标来源。")) }
        if active < 2 { active += 1 } else { await withCheckedContinuation { waiting.append($0) } }
        let delay = max(0, nextStart.timeIntervalSinceNow)
        nextStart = Date().addingTimeInterval(delay + 0.15)
        defer { if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() } }
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        let (data, response) = try await session.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2_000_000 else { throw CatalogError.invalid(tr("图标暂不可用。")) }
        return data
    }
}

@MainActor @Observable final class BrandIconStore {
    let folder: URL
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private let downloads: any BrandIconFetching
    @ObservationIgnored private var tasks: [String: Task<NSImage?, Never>] = [:]
    @ObservationIgnored private var failedAt: [String: Date] = [:]
    init(folder: URL, downloads: (any BrandIconFetching)? = nil) {
        self.folder = folder
        self.downloads = downloads ?? BrandIconDownloads()
    }
    var cachedRemoteCount: Int { images.keys.filter { $0.hasPrefix("https://") }.count }
    static func decode(_ data: Data) -> NSImage? {
        guard data.count <= 2_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, let height = props[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { return nil }
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
    func image(_ source: String) -> NSImage? { images[source] }
    func customImage(_ name: String?) -> NSImage? {
        guard let name, BrandIconSource.validCustomName(name) else { return nil }
        if let cached = images[name] { return cached }
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        return Self.decode(data)
    }
    func saveCustom(_ data: Data) throws -> String {
        guard let image = Self.decode(data) else { throw CatalogError.invalid(tr("请选择2MB以内、可读取的图标图片。")) }
        let name = "custom-\(UUID().uuidString).image"
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent(name), options: .atomic)
        images[name] = image
        return name
    }
    func prefetch(_ sources: [String]) {
        for source in Set(sources) where images[source] == nil && tasks[source] == nil {
            Task { await load(source) }
        }
    }
    @discardableResult func load(_ source: String) async -> NSImage? {
        if let image = images[source] { return image }
        if let task = tasks[source] { return await task.value }
        guard let url = URL(string: source), BrandIconSource.allowed(url) else { return nil }
        let file = folder.appendingPathComponent(BrandIconSource.filename(source))
        if let data = try? Data(contentsOf: file), let image = Self.decode(data) { images[source] = image; return image }
        if let date = failedAt[source], Date().timeIntervalSince(date) < 300 { return nil }
        let task = Task { () -> NSImage? in
            do {
                let data = try await downloads.data(url)
                guard let image = Self.decode(data) else { throw CatalogError.invalid(tr("无法读取服务图标。")) }
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try data.write(to: file, options: .atomic)
                images[source] = image
                return image
            } catch { failedAt[source] = Date(); return nil }
        }
        tasks[source] = task
        let image = await task.value
        tasks[source] = nil
        return image
    }
}
