import Foundation
import CSQLite

// Owned by CatalogEngine. SQLite also arbitrates daily claims between app instances.
final class CatalogDatabase {
    private var db: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw CatalogError.invalid(tr("无法打开优惠数据库。"))
        }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;")
        let version = try rows("PRAGMA user_version").first?["user_version"] ?? "0"
        guard ["0", "1"].contains(version) else { throw CatalogError.invalid(tr("优惠数据库版本不兼容，未覆盖原文件。")) }
        try exec("""
        CREATE TABLE IF NOT EXISTS products(path TEXT PRIMARY KEY, payload TEXT NOT NULL, listed INTEGER NOT NULL DEFAULT 1);
        CREATE TABLE IF NOT EXISTS offers(id TEXT PRIMARY KEY, product_path TEXT NOT NULL, group_key TEXT NOT NULL, payload TEXT NOT NULL, active INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS observations(id TEXT PRIMARY KEY, group_key TEXT NOT NULL, observed_at REAL NOT NULL, payload TEXT NOT NULL);
        CREATE INDEX IF NOT EXISTS observations_group ON observations(group_key, observed_at);
        CREATE TABLE IF NOT EXISTS http_cache(url TEXT PRIMARY KEY, body TEXT NOT NULL, etag TEXT, modified TEXT);
        CREATE TABLE IF NOT EXISTS runs(id TEXT PRIMARY KEY, daily_day TEXT UNIQUE, started_at REAL NOT NULL, payload TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
        PRAGMA user_version=1;
        """)
        try hydrateIconsFromCachedDirectory()
    }
    deinit { sqlite3_close(db) }
    private func failure() -> CatalogError { .invalid(tr("优惠数据库写入失败：\(String(cString: sqlite3_errmsg(db)))")) }
    private func exec(_ sql: String) throws { guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure() } }
    private func statement(_ sql: String, _ params: [String?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { throw failure() }
        for (offset, value) in params.enumerated() {
            let rc = value.map { sqlite3_bind_text(stmt, Int32(offset + 1), $0, -1, transient) } ?? sqlite3_bind_null(stmt, Int32(offset + 1))
            if rc != SQLITE_OK { sqlite3_finalize(stmt); throw failure() }
        }
        return stmt
    }
    private func run(_ sql: String, _ params: [String?] = []) throws {
        let stmt = try statement(sql, params); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    private func rows(_ sql: String, _ params: [String?] = []) throws -> [[String: String]] {
        let stmt = try statement(sql, params); defer { sqlite3_finalize(stmt) }
        var result: [[String: String]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { return result }
            guard rc == SQLITE_ROW else { throw failure() }
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(stmt) {
                if let value = sqlite3_column_text(stmt, index) { row[String(cString: sqlite3_column_name(stmt, index))] = String(cString: value) }
            }
            result.append(row)
        }
    }
    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try exec("BEGIN IMMEDIATE")
        do { let result = try action(); try exec("COMMIT"); return result }
        catch { try? exec("ROLLBACK"); throw error }
    }
    private func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try JSONEncoder().encode(value), as: UTF8.self) }
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T { try JSONDecoder().decode(type, from: Data(text.utf8)) }
    func setting(_ key: String) throws -> String? { try rows("SELECT value FROM settings WHERE key=?", [key]).first?["value"] }
    func setSetting(_ key: String, _ value: String) throws { try run("INSERT INTO settings VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", [key, value]) }
    func cache(_ url: URL) throws -> CachedCatalogPage? {
        guard let row = try rows("SELECT * FROM http_cache WHERE url=?", [url.absoluteString]).first else { return nil }
        return .init(body: row["body"] ?? "", etag: row["etag"], modified: row["modified"])
    }
    func saveCache(_ url: URL, _ value: CachedCatalogPage) throws {
        try run("INSERT INTO http_cache VALUES(?,?,?,?) ON CONFLICT(url) DO UPDATE SET body=excluded.body,etag=excluded.etag,modified=excluded.modified", [url.absoluteString, value.body, value.etag, value.modified])
    }
    func products() throws -> [CatalogProduct] {
        try rows("SELECT payload,listed FROM products ORDER BY path").map {
            var value = try decode(CatalogProduct.self, $0["payload"]!)
            value.listed = $0["listed"] == "1"
            return value
        }
    }
    func replaceDirectory(_ products: [CatalogProduct]) throws {
        let previous = Dictionary(uniqueKeysWithValues: try self.products().map { ($0.path, $0) })
        try transaction {
            try run("UPDATE products SET listed=0")
            for var product in products {
                product.lastVerified = previous[product.path]?.lastVerified
                product.lastError = previous[product.path]?.lastError
                product.iconURLs = product.iconURLs ?? previous[product.path]?.iconURLs
                try run("INSERT INTO products VALUES(?,?,1) ON CONFLICT(path) DO UPDATE SET payload=excluded.payload,listed=1", [product.path, try json(product)])
            }
        }
    }
    private func hydrateIconsFromCachedDirectory() throws {
        let current = try products()
        guard current.contains(where: { ($0.iconURLs ?? []).isEmpty }) else { return }
        var sources: [String: [String]] = [:]
        for row in try rows("SELECT body FROM http_cache WHERE url LIKE ?", [CatalogSource.base.absoluteString + "/page/%"]) {
            guard let body = row["body"], let parsed = try? CatalogParser.directory(body) else { continue }
            for product in parsed.products { if let icons = product.iconURLs { sources[product.path] = icons } }
        }
        try transaction {
            for var product in current where (product.iconURLs ?? []).isEmpty {
                guard let icons = sources[product.path] else { continue }
                product.iconURLs = icons
                try run("UPDATE products SET payload=? WHERE path=?", [try json(product), product.path])
            }
        }
    }
    func saveProduct(_ product: CatalogProduct, offers: [CatalogOffer], runID: String, page: FetchedCatalogPage) throws {
        guard !offers.isEmpty else { throw CatalogError.invalid(tr("空报价不覆盖已有方案。")) }
        try transaction {
            let existing = try rows("SELECT payload FROM products WHERE path=?", [product.path]).first?["payload"]
                .map { try decode(CatalogProduct.self, $0) }
            let newer = (existing?.lastVerified ?? .distantPast) <= offers[0].observedAt
            var current = product
            current.lastVerified = offers[0].observedAt
            current.lastError = nil
            current.iconURLs = product.iconURLs ?? existing?.iconURLs
            if newer {
                try run("INSERT INTO products VALUES(?,?,?) ON CONFLICT(path) DO UPDATE SET payload=excluded.payload", [current.path, try json(current), current.listed ? "1" : "0"])
                try run("UPDATE offers SET active=0 WHERE product_path=?", [product.path])
            }
            for offer in offers {
                if newer {
                    try run("INSERT INTO offers VALUES(?,?,?,?,1) ON CONFLICT(id) DO UPDATE SET group_key=excluded.group_key,payload=excluded.payload,active=1", [offer.id, product.path, offer.groupKey, try json(offer)])
                }
                let observation = OfferObservation(id: UUID().uuidString, quote: offer, runID: runID, notModified: page.notModified)
                try run("INSERT INTO observations VALUES(?,?,?,?)", [observation.id, offer.groupKey, String(offer.observedAt.timeIntervalSince1970), try json(observation)])
            }
            if newer { try saveCache(product.sourceURL, page.cache) }
        }
    }
    func failProduct(_ path: String, message: String) throws {
        guard var product = try products().first(where: { $0.path == path }) else { return }
        product.lastError = message
        try run("UPDATE products SET payload=? WHERE path=?", [try json(product), path])
    }
    func offers(path: String? = nil) throws -> [CatalogOffer] {
        let sql = "SELECT payload FROM offers WHERE active=1" + (path == nil ? "" : " AND product_path=?") + " ORDER BY product_path,id"
        return try rows(sql, path.map { [$0] } ?? []).map { try decode(CatalogOffer.self, $0["payload"]!) }
    }
    func history(groupKey: String) throws -> [OfferObservation] {
        try rows("SELECT payload FROM observations WHERE group_key=? ORDER BY observed_at DESC LIMIT 200", [groupKey]).map { try decode(OfferObservation.self, $0["payload"]!) }
    }
    func comparison(groupKeys: [String], currency: String, now: Date) throws -> PriceComparison {
        var result = PriceComparison()
        guard !groupKeys.isEmpty else { return result }
        var recent: [OfferObservation] = []
        // Bound variables even if the site rotated through many descriptions of a single offer.
        for start in stride(from: 0, to: groupKeys.count, by: 400) {
            let keys = groupKeys[start..<min(start + 400, groupKeys.count)]
            let slots = keys.map { _ in "?" }.joined(separator: ",")
            let filter = "WHERE group_key IN (\(slots)) AND json_extract(payload, '$.quote.currency')=? AND observed_at<=?"
            let params = Array(keys) + [currency, String(now.timeIntervalSince1970)]
            let statement = try statement("SELECT json_extract(payload, '$.quote.price'), observed_at FROM observations \(filter)", params)
            defer { sqlite3_finalize(statement) }
            while true {
                let status = sqlite3_step(statement)
                if status == SQLITE_DONE { break }
                guard status == SQLITE_ROW else { throw failure() }
                let date = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let price = sqlite3_column_text(statement, 0).map { String(cString: $0) }
                if let point = PricePoint(price: price, at: date) { result.observe(point) }
            }
            let chartRows = try rows("SELECT payload FROM observations \(filter) ORDER BY observed_at DESC, rowid DESC LIMIT 200", params)
            recent += try chartRows.map { try decode(OfferObservation.self, $0["payload"]!) }
        }
        result.chart = Array(recent.sorted { $0.quote.observedAt > $1.quote.observedAt }.prefix(200))
        return result
    }
    func begin(_ trigger: CatalogTrigger, now: Date) throws -> CatalogRun? {
        try transaction {
            let day = trigger == .daily ? CatalogSource.day(now) : nil
            if let day, !(try rows("SELECT id FROM runs WHERE daily_day=?", [day])).isEmpty { return nil }
            let value = CatalogRun(id: UUID().uuidString, trigger: trigger, startedAt: now, finishedAt: nil, status: "进行中", note: "")
            try run("INSERT INTO runs VALUES(?,?,?,?)", [value.id, day, String(now.timeIntervalSince1970), try json(value)])
            return value
        }
    }
    func finish(_ run: CatalogRun, status: String, note: String, now: Date) throws {
        var value = run; value.finishedAt = now; value.status = status; value.note = note
        try self.run("UPDATE runs SET payload=? WHERE id=?", [try json(value), run.id])
    }
    func snapshot() throws -> CatalogSnapshot {
        let runs = try rows("SELECT payload FROM runs ORDER BY started_at DESC LIMIT 30").map { try decode(CatalogRun.self, $0["payload"]!) }
        let groups = try rows("SELECT payload,MAX(observed_at) FROM observations GROUP BY group_key,json_extract(payload, '$.quote.currency') ORDER BY MAX(observed_at) DESC")
            .map { try decode(OfferObservation.self, $0["payload"]!).quote }
        let revision = try rows("SELECT MAX(rowid) AS revision FROM observations").first?["revision"].flatMap(Int64.init) ?? 0
        return try .init(products: products(), offers: offers(), historyGroups: groups, historyRevision: revision,
                         runs: runs, dailyEnabled: setting("daily_enabled") == "true")
    }
}
