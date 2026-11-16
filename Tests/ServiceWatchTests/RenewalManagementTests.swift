import XCTest
@testable import ServiceWatch

final class RenewalManagementTests: XCTestCase {
    private func repository() throws -> AuthorizationRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceWatch-Renewal-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return .init(fileURL: folder.appendingPathComponent("authorizations.json"))
    }

    private func legacyRenewal() -> AuthorizationArchive {
        let old = ServiceFixtures.services.first { $0.id == 2 }!
        var renewed = old
        renewed.entitlements[0].expires = "2033-07-03"
        renewed.entitlements[1].expires = "2034-04-08"
        renewed.channel = "示例商店"
        renewed.method = "网银支付"
        renewed.billingCycle = "一次性购买"
        renewed.paidAmount = "129"
        renewed.evidence = "用户手动更新"
        return AuthorizationArchive(schemaVersion: 1, services: [renewed], changes: [.init(before: old, after: renewed)])
    }

    private func writeLegacy(to repo: AuthorizationRepository) throws -> Data {
        let bytes = try JSONEncoder().encode(legacyRenewal())
        try bytes.write(to: repo.fileURL)
        return bytes
    }

    func testLegacyMigrationSeparatesAppleAgreementFromNewPurchaseWithoutWriting() throws {
        let repo = try repository()
        let bytes = try writeLegacy(to: repo)
        let archive = try XCTUnwrap(repo.load())
        let service = try XCTUnwrap(archive.services.first)
        let plan = try XCTUnwrap(service.renewalPlan)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(service.entitlements, legacyRenewal().services[0].entitlements)
        XCTAssertEqual(service.channel, "示例商店")
        XCTAssertEqual(service.method, "网银支付")
        XCTAssertEqual(service.billingCycle, "一次性购买")
        XCTAssertEqual(service.paidAmount, "129")
        XCTAssertEqual(plan.channel, "App Store")
        XCTAssertEqual(plan.method, "苹果支付")
        XCTAssertEqual(plan.cycle, "连续包年")
        XCTAssertEqual(plan.amount, "159")
        XCTAssertEqual(plan.nextCharge, "2031-02-14")
        XCTAssertEqual(plan.status, .unverified)
        XCTAssertNil(plan.verifiedAt)
        XCTAssertTrue(plan.showsReviewPrompt)
        XCTAssertNil(archive.changes[0].before?.renewalPlan)
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
    }

    @MainActor func testFirstSaveBacksUpLegacyAndDoesNotResurrectOptOutAfterRelaunch() async throws {
        let repo = try repository()
        let originalBytes = try writeLegacy(to: repo)
        let store = DemoStore(repository: repo)
        var plan = try XCTUnwrap(store.services.first?.renewalPlan)
        plan.isTracked = false
        plan.remindersEnabled = false
        try store.updateRenewal(serviceID: 2, plan: plan)
        let files = try FileManager.default.contentsOfDirectory(at: repo.fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil)
        let backups = files.filter { $0.lastPathComponent.hasPrefix("authorizations-v1-backup-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), originalBytes)
        let reopened = DemoStore(repository: repo)
        let saved = try XCTUnwrap(reopened.services.first?.renewalPlan)
        XCTAssertFalse(saved.isTracked)
        XCTAssertFalse(saved.remindersEnabled)
        XCTAssertEqual(saved.status, .unverified)
        XCTAssertEqual(reopened.pendingRenewalCount, 0)
        XCTAssertEqual(reopened.changes.count, 2)
        XCTAssertEqual(reopened.services.first?.entitlements, store.services.first?.entitlements)
    }

    func testPromptAndReminderEligibilityMatrix() {
        for status in RenewalStatus.allCases {
            for tracked in [false, true] {
                for reminders in [false, true] {
                    var plan = RenewalPlan()
                    plan.status = status
                    plan.isTracked = tracked
                    plan.remindersEnabled = reminders
                    XCTAssertEqual(plan.showsReviewPrompt, tracked && reminders && status == .unverified)
                    XCTAssertEqual(plan.allowsLocalReminders, tracked && reminders && status != .disabled)
                }
            }
        }
    }

    @MainActor func testVerificationMuteStopAndResumePersistWithoutChangingMembership() async throws {
        let repo = try repository()
        _ = try writeLegacy(to: repo)
        var store = DemoStore(repository: repo)
        let membership = try XCTUnwrap(store.services.first)
        XCTAssertEqual(store.pendingRenewalCount, 1)
        var plan = try XCTUnwrap(membership.renewalPlan)
        plan.status = .enabled
        try store.updateRenewal(serviceID: 2, plan: plan)
        store = DemoStore(repository: repo)
        XCTAssertEqual(store.pendingRenewalCount, 0)
        XCTAssertNotNil(store.services.first?.renewalPlan?.verifiedAt)
        XCTAssertTrue(try XCTUnwrap(store.services.first?.renewalPlan).allowsLocalReminders)

        plan = try XCTUnwrap(store.services.first?.renewalPlan)
        plan.status = .disabled
        try store.updateRenewal(serviceID: 2, plan: plan)
        store = DemoStore(repository: repo)
        XCTAssertEqual(store.services.first?.renewalPlan?.status, .disabled)
        XCTAssertEqual(store.services.first?.renewalPlan?.nextCharge, "2031-02-14")
        XCTAssertFalse(try XCTUnwrap(store.services.first?.renewalPlan).allowsLocalReminders)

        plan = try XCTUnwrap(store.services.first?.renewalPlan)
        plan.status = .unverified
        plan.remindersEnabled = false
        try store.updateRenewal(serviceID: 2, plan: plan)
        store = DemoStore(repository: repo)
        XCTAssertEqual(store.pendingRenewalCount, 0)
        XCTAssertTrue(try XCTUnwrap(store.services.first?.renewalPlan).isTracked)
        XCTAssertEqual(store.services.first?.renewalPlan?.status, .unverified)
        XCTAssertNil(store.services.first?.renewalPlan?.verifiedAt)

        plan = try XCTUnwrap(store.services.first?.renewalPlan)
        plan.isTracked = false
        plan.remindersEnabled = true
        try store.updateRenewal(serviceID: 2, plan: plan)
        store = DemoStore(repository: repo)
        XCTAssertEqual(store.pendingRenewalCount, 0)
        plan = try XCTUnwrap(store.services.first?.renewalPlan)
        plan.isTracked = true
        try store.updateRenewal(serviceID: 2, plan: plan)
        store = DemoStore(repository: repo)
        XCTAssertEqual(store.pendingRenewalCount, 1)
        let final = try XCTUnwrap(store.services.first)
        XCTAssertEqual(final.entitlements, membership.entitlements)
        XCTAssertEqual(final.channel, membership.channel)
        XCTAssertEqual(final.method, membership.method)
        XCTAssertEqual(final.billingCycle, membership.billingCycle)
        XCTAssertEqual(final.paidAmount, membership.paidAmount)
        XCTAssertEqual(final.evidence, membership.evidence)
    }

    @MainActor func testEditingMembershipDoesNotDismissPendingAgreementAndManagerUsesLatestMembership() async throws {
        let repo = try repository()
        _ = try writeLegacy(to: repo)
        let store = DemoStore(repository: repo)
        var openManagerPlan = try XCTUnwrap(store.services.first?.renewalPlan)
        var laterMembership = try XCTUnwrap(store.services.first)
        laterMembership.entitlements[0].expires = "2035-07-05"
        laterMembership.paidAmount = "120"
        try store.save(laterMembership)
        XCTAssertEqual(store.pendingRenewalCount, 1)
        openManagerPlan.remindersEnabled = false
        try store.updateRenewal(serviceID: 2, plan: openManagerPlan)
        let final = try XCTUnwrap(DemoStore(repository: repo).services.first)
        XCTAssertEqual(final.entitlements, laterMembership.entitlements)
        XCTAssertEqual(final.paidAmount, "120")
        XCTAssertEqual(final.renewalPlan?.status, .unverified)
        XCTAssertFalse(try XCTUnwrap(final.renewalPlan).remindersEnabled)
    }

    @MainActor func testUnchangedSaveDoesNotCreateHistoryAndMutePreservesVerificationTime() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        var plan = try XCTUnwrap(store.services.first { $0.id == 2 }?.renewalPlan)
        try store.updateRenewal(serviceID: 2, plan: plan)
        XCTAssertTrue(store.changes.isEmpty)
        plan.status = .enabled
        try store.updateRenewal(serviceID: 2, plan: plan)
        plan = try XCTUnwrap(store.services.first { $0.id == 2 }?.renewalPlan)
        let verifiedAt = try XCTUnwrap(plan.verifiedAt)
        plan.remindersEnabled = false
        try store.updateRenewal(serviceID: 2, plan: plan)
        XCTAssertEqual(store.services.first { $0.id == 2 }?.renewalPlan?.verifiedAt, verifiedAt)
        XCTAssertEqual(store.changes.count, 2)
    }

    @MainActor func testInvalidPlanCannotBeSavedAndUnknownDetailsRemainAllowed() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let before = store.services
        let bytes = try Data(contentsOf: repo.fileURL)
        var plan = RenewalPlan()
        XCTAssertTrue(plan.isValid)
        plan.nextCharge = "2027-02-29"
        XCTAssertThrowsError(try store.updateRenewal(serviceID: 2, plan: plan))
        plan.nextCharge = nil
        for invalid in ["-1", "NaN", "1.234", "1,200", ""] {
            plan.amount = invalid
            XCTAssertThrowsError(try store.updateRenewal(serviceID: 2, plan: plan))
        }
        plan.amount = nil
        plan.currency = "人民币"
        XCTAssertThrowsError(try store.updateRenewal(serviceID: 2, plan: plan))
        XCTAssertEqual(store.services, before)
        XCTAssertTrue(store.changes.isEmpty)
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), bytes)
        plan.currency = "USD"
        plan.amount = "0.00"
        plan.nextCharge = "2028-02-29"
        XCTAssertTrue(plan.isValid)
    }

    @MainActor func testFailedPlanWriteDoesNotAppearSaved() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let before = store.services
        var plan = try XCTUnwrap(store.services.first { $0.id == 2 }?.renewalPlan)
        plan.isTracked = false
        try FileManager.default.removeItem(at: repo.fileURL.deletingLastPathComponent())
        try Data("not a directory".utf8).write(to: repo.fileURL.deletingLastPathComponent())
        XCTAssertThrowsError(try store.updateRenewal(serviceID: 2, plan: plan))
        XCTAssertEqual(store.services, before)
        XCTAssertEqual(store.pendingRenewalCount, 1)
        XCTAssertTrue(store.changes.isEmpty)
    }

    func testEmptyLegacyFieldsDoNotCreateFalsePendingAndOldDatesAreLabeled() {
        var service = ServiceFixtures.services[0]
        service.nextCharge = "  "
        service.nextAmount = ""
        XCTAssertNil(RenewalPlan.migrate(service: service, history: []))
        service.nextCharge = "2000-01-01"
        let plan = RenewalPlan.migrate(service: service, history: [])
        XCTAssertEqual(plan?.status, .unverified)
        XCTAssertEqual(plan?.dateLabel, "记录日期 2000-01-01（已过）")
        XCTAssertEqual(plan?.amountLabel, "金额待确认")
    }
}
