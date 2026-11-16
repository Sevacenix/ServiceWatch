import XCTest
@testable import ServiceWatch

private final class CatalogURLProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let respond = Self.respond else { throw CatalogError.invalid("Missing test handler") }
            let (response, data) = try respond(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class CatalogHTTPTests: XCTestCase {
    override func tearDown() { CatalogURLProtocol.respond = nil; super.tearDown() }
    private func client() -> CatalogHTTP {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CatalogURLProtocol.self]
        return CatalogHTTP(configuration: config)
    }
    func testConditionalGETUsesServerValidatorsAnd304RetainsExactBody() async throws {
        let url = CatalogSource.url("/vip/bilibili")
        CatalogURLProtocol.respond = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"tag-1\"")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "Mon, 09 Nov 2026 01:00:00 GMT")
            XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return (HTTPURLResponse(url: url, statusCode: 304, httpVersion: nil, headerFields: ["ETag": "\"tag-1\""])!, Data())
        }
        let cached = CachedCatalogPage(body: "original html content", etag: "\"tag-1\"", modified: "Mon, 09 Nov 2026 01:00:00 GMT")
        let result = try await client().get(url, cache: cached)
        XCTAssertTrue(result.notModified)
        XCTAssertEqual(result.cache.body, cached.body)
    }
    func test429ReturnsRetryAfterInsteadOfFakeEmptyQuote() async throws {
        let url = CatalogSource.url("/vip/bilibili")
        CatalogURLProtocol.respond = { _ in
            (HTTPURLResponse(url: url, statusCode: 429, httpVersion: nil, headerFields: ["Retry-After": "300"])!, Data())
        }
        do { _ = try await client().get(url, cache: nil); XCTFail("Expected Retry-After") }
        catch CatalogError.retryAfter(let until) { XCTAssertGreaterThan(until.timeIntervalSinceNow, 250) }
    }
}
