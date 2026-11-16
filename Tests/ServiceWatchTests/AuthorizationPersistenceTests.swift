import XCTest
@testable import ServiceWatch

final class AuthorizationPersistenceTests: XCTestCase {
    private func repository() throws -> AuthorizationRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceWatch-Tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return .init(fileURL: folder.appendingPathComponent("authorizations.json"))
    }

    @MainActor func testFirstLaunchStartsEmptyWithoutAnAuthorizationArchive() async throws {
        let repo = try repository()
        let store = DemoStore(repository: repo)
        XCTAssertNil(store.storageIssue)
        XCTAssertTrue(store.services.isEmpty)
        XCTAssertTrue(store.changes.isEmpty)
        XCTAssertNil(store.selectedID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.fileURL.path))
        await store.catalog.reload()
        XCTAssertTrue(store.catalog.snapshot.offers.isEmpty)
        XCTAssertTrue(store.catalog.snapshot.runs.isEmpty)
        XCTAssertFalse(store.catalog.snapshot.dailyEnabled)
    }

    @MainActor func testEditingSecondTierSurvivesRelaunchWithoutChangingOtherDates() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let baseline = store.services
        var music = try XCTUnwrap(store.services.first { $0.id == 5 })
        let original = music.entitlements
        music.entitlements[1].expires = "2033-02-17"
        try store.save(music)
        let reopened = DemoStore(repository: repo)
        let actual = try XCTUnwrap(reopened.services.first { $0.id == 5 })
        XCTAssertEqual(actual.entitlements[1].expires, "2033-02-17")
        XCTAssertEqual(actual.entitlements[1].id, original[1].id)
        XCTAssertEqual(actual.entitlements[0], original[0])
        XCTAssertEqual(actual.entitlements[2], original[2])
        XCTAssertEqual(reopened.services.filter { $0.id != 5 }, baseline.filter { $0.id != 5 })
        XCTAssertEqual(reopened.changes.count, 1)
        XCTAssertEqual(reopened.changes[0].before?.entitlements[1].expires, "2032-02-17")
        XCTAssertEqual(reopened.changes[0].after.entitlements[1].expires, "2033-02-17")
    }

    @MainActor func testCustomTierDoesNotRequireAWebsiteCatalogEntry() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        var service = try XCTUnwrap(store.services.first { $0.id == 3 })
        let original = service.entitlements
        let custom = Entitlement(tier: "家庭旗舰版 · 自定义", expires: "2030-02-28", note: "用户手动续费")
        service.entitlements.append(custom)
        try store.save(service)
        let saved = try XCTUnwrap(DemoStore(repository: repo).services.first { $0.id == 3 })
        XCTAssertEqual(Array(saved.entitlements.prefix(2)), original)
        XCTAssertEqual(saved.entitlements.last, custom)
    }

    @MainActor func testNewManualServiceWithPermanentAndUnknownRightsPersists() async throws {
        let repo = try repository()
        let store = DemoStore(repository: repo)
        let service = Service(id: 13, name: "Parallels Desktop", category: "软件授权", symbol: "key.horizontal.fill", tint: .teal, paid: true,
            entitlements: [.init(tier: "Standard 26 永久版", expires: nil, perpetual: true), .init(tier: "升级权益待确认", expires: nil)],
            offerPath: nil, evidence: "手动录入")
        try store.save(service)
        let reopened = DemoStore(repository: repo)
        XCTAssertEqual(reopened.services.last, service)
        XCTAssertNil(reopened.services.last?.nextExpiry)
        XCTAssertFalse(try XCTUnwrap(reopened.services.last).example)
        XCTAssertEqual(reopened.changes.last?.summary, "手动添加服务与授权")
    }

    @MainActor func testUnsubmittedDraftDoesNotModifyStoredAuthorization() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let originalBytes = try Data(contentsOf: repo.fileURL)
        var draft = EntitlementDraft(try XCTUnwrap(store.services.first?.entitlements.first))
        draft.expiryText = "2035-01-01"
        XCTAssertTrue(draft.isValid)
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), originalBytes)
        XCTAssertEqual(DemoStore(repository: repo).services, store.services)
    }

    @MainActor func testCorruptArchiveIsPreserved() async throws {
        let repo = try repository()
        let bytes = Data("not valid JSON".utf8)
        try bytes.write(to: repo.fileURL)
        let store = DemoStore(repository: repo)
        XCTAssertNotNil(store.storageIssue)
        XCTAssertTrue(store.services.isEmpty)
        XCTAssertThrowsError(try store.save(ServiceFixtures.services[0]))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
    }

    func testUnsupportedSchemaIsNotSilentlyAccepted() throws {
        let repo = try repository()
        let archive = AuthorizationArchive(schemaVersion: 99, services: [])
        try JSONEncoder().encode(archive).write(to: repo.fileURL)
        XCTAssertThrowsError(try repo.load())
    }

    @MainActor func testFailedWriteDoesNotUpdateVisibleDataOrHistory() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let before = store.services
        var service = before[0]
        service.entitlements[0].expires = "2030-01-01"
        try FileManager.default.removeItem(at: repo.fileURL.deletingLastPathComponent())
        try Data("not a directory".utf8).write(to: repo.fileURL.deletingLastPathComponent())
        XCTAssertThrowsError(try store.save(service))
        XCTAssertEqual(store.services, before)
        XCTAssertTrue(store.changes.isEmpty)
    }

    func testDatesRejectImpossibleDaysAndDraftKeepsIdentity() throws {
        XCTAssertNil(ServiceDate.parse("2027-02-29"))
        XCTAssertNotNil(ServiceDate.parse("2028-02-29"))
        XCTAssertNil(ServiceDate.parse("2028-6-2"))
        let entitlement = Entitlement(tier: "自定义", expires: "2037-01-09", note: "后续生效")
        var draft = EntitlementDraft(entitlement)
        XCTAssertEqual(draft.value, entitlement)
        draft.validity = "永久授权"
        XCTAssertTrue(draft.isValid)
        XCTAssertTrue(draft.value.perpetual)
        XCTAssertNil(draft.value.expires)
        XCTAssertEqual(draft.value.id, entitlement.id)
    }

    @MainActor func testCustomSecondaryTierContributesToExpiryOverview() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let oldCount = store.expiringSoonCount
        var service = try XCTUnwrap(store.services.first { $0.id == 12 })
        let due = ServiceDate.string(ServiceDate.today.addingTimeInterval(7 * 24 * 60 * 60))
        service.entitlements.append(.init(tier: "单独购买的升级权益", expires: due))
        try store.save(service)
        XCTAssertEqual(store.expiringSoonCount, oldCount + 1)
        XCTAssertEqual(store.nextExpiryNote, "最近授权到期还有 7 天")
        XCTAssertEqual(service.nextExpiry, "2090-03-18")
    }
}
