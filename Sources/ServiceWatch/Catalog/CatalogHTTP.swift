import Foundation

protocol CatalogTransport: Sendable {
    func get(_ url: URL, cache: CachedCatalogPage?) async throws -> FetchedCatalogPage
}

private actor CatalogRequestLimit {
    private var active = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private var nextStart = Date.distantPast
    func acquire() async {
        if active < 2 { active += 1 }
        else { await withCheckedContinuation { waiting.append($0) } }
        let delay = max(0, nextStart.timeIntervalSinceNow)
        nextStart = Date().addingTimeInterval(delay + 0.75)
        if delay > 0 { try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
    }
    func release() {
        if waiting.isEmpty { active -= 1 } else { waiting.removeFirst().resume() }
    }
}
private final class CatalogRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(request.url.map(CatalogSource.allowed) == true ? request : nil)
    }
}

final class CatalogHTTP: CatalogTransport, @unchecked Sendable {
    private let session: URLSession
    private let limit = CatalogRequestLimit()
    init(configuration config: URLSessionConfiguration = .ephemeral) {
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.urlCache = nil
        session = URLSession(configuration: config, delegate: CatalogRedirectPolicy(), delegateQueue: nil)
    }
    func get(_ url: URL, cache: CachedCatalogPage?) async throws -> FetchedCatalogPage {
        guard CatalogSource.allowed(url) else { throw CatalogError.invalid(tr("拒绝读取非公开目录或站外链接。")) }
        await limit.acquire()
        do {
            try Task.checkCancellation()
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            request.setValue("ServiceWatch/1.0 (macOS; public offer catalog)", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html, text/plain;q=0.9", forHTTPHeaderField: "Accept")
            if let etag = cache?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            if let modified = cache?.modified { request.setValue(modified, forHTTPHeaderField: "If-Modified-Since") }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CatalogError.invalid(tr("优惠站响应无效。")) }
            if response.statusCode == 429 || response.statusCode == 503 {
                let text = response.value(forHTTPHeaderField: "Retry-After") ?? "300"
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
                let until = TimeInterval(text).map { Date().addingTimeInterval(max(60, $0)) } ?? formatter.date(from: text) ?? Date().addingTimeInterval(3600)
                throw CatalogError.retryAfter(until)
            }
            let result: FetchedCatalogPage
            if response.statusCode == 304 {
                guard var existing = cache else { throw CatalogError.invalid(tr("站点返回304但没有本地缓存，请稍后重试。")) }
                existing.etag = response.value(forHTTPHeaderField: "ETag") ?? existing.etag
                existing.modified = response.value(forHTTPHeaderField: "Last-Modified") ?? existing.modified
                result = .init(cache: existing, notModified: true)
            } else {
                guard response.statusCode == 200 else { throw CatalogError.http(response.statusCode) }
                guard data.count < 3_000_000, let body = String(data: data, encoding: .utf8), !body.isEmpty else { throw CatalogError.invalid(tr("优惠页面不是有效UTF-8文本，保留旧数据。")) }
                result = .init(cache: .init(body: body, etag: response.value(forHTTPHeaderField: "ETag"), modified: response.value(forHTTPHeaderField: "Last-Modified")), notModified: false)
            }
            await limit.release()
            return result
        } catch { await limit.release(); throw error }
    }
}
