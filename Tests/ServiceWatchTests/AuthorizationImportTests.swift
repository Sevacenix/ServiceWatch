import XCTest
@testable import ServiceWatch

final class AuthorizationImportTests: XCTestCase {
    private func fixture(_ name: String) throws -> URL {
        let base = try XCTUnwrap(Bundle.module.resourceURL)
        return base.appendingPathComponent("Fixtures/Authorization/" + name)
    }

    private func recognize(_ text: String, origin: ImportOrigin = .email, names: [String] = []) -> ImportRecognition {
        let lines = text.components(separatedBy: .newlines).map { ImportLine(text: $0) }
        return AuthorizationRecognition.recognize(.init(origin: origin, lines: lines), names: names)
    }

    func testEMLDecodesNestedMIMEAndIgnoresBillingAttachmentAndSecrets() throws {
        let document = try ImportInput.read(fixture("Parallels-Pro.eml"))
        let result = AuthorizationRecognition.recognize(document, names: ["Keep", "Parallels Desktop"])
        XCTAssertEqual(result.origin, .email)
        XCTAssertEqual(result.service, "Parallels Desktop")
        XCTAssertEqual(result.candidates.map(\.tier), ["Pro"])
        XCTAssertEqual(result.candidates.compactMap(\.expiry), ["2027-02-18"])
        XCTAssertFalse(result.excerpt.contains("EXAMPLE-NOTREAL-0000"))
        XCTAssertFalse(result.excerpt.contains("2099"))
        XCTAssertFalse(result.excerpt.contains("Promotion"))
    }

    func testHTMLOnlyAndBase64DecodeWithoutExternalContent() throws {
        let html = """
        <html><head><script>Subscription expires on 2099-01-01</script></head>
        <body><p>WPS&nbsp;超级会员</p><table><tr><td>有效期至</td><td>2037&#45;05&#45;10</td></tr></table>
        <img src="https://example.invalid/unread">
        <blockquote>有效期至 2099-12-01</blockquote></body></html>
        """
        let raw = """
        Subject: WPS
        Content-Type: text/html; charset="UTF-8"
        Content-Transfer-Encoding: base64

        \(Data(html.utf8).base64EncodedString())
        """
        let result = recognize(try MailBodyDecoder.decode(Data(raw.utf8)))
        XCTAssertEqual(result.service, "WPS")
        XCTAssertEqual(result.candidates.map(\.tier), ["超级会员"])
        XCTAssertEqual(result.candidates.compactMap(\.expiry), ["2037-05-10"])
        XCTAssertFalse(result.excerpt.contains("https://"))
        XCTAssertFalse(result.excerpt.contains("2099"))
        XCTAssertThrowsError(try MailBodyDecoder.decode(Data("bad message".utf8)))
    }

    func testVisionReadsChineseMembershipScreenshotAndPairsBothTiers() throws {
        let document = try ImportInput.read(fixture("Tencent-Membership.png"))
        let result = AuthorizationRecognition.recognize(document, names: ["腾讯视频", "QQ 音乐"])
        XCTAssertEqual(result.origin, .screenshot)
        XCTAssertEqual(result.service, "腾讯视频", result.excerpt)
        XCTAssertEqual(result.candidates.map { "\($0.tier):\($0.expiry ?? "?")" }.sorted(),
                       ["SVIP:2031-09-14", "VIP:2032-10-02"], result.excerpt)
    }

    func testBilibiliHistoryPairsTiersWithoutTreatingNextChargeAsExpiry() {
        let result = recognize("""
        超级大会员 227 天后到期
        到期转成大会员至 2032–11–12
        下次扣费时间 2031-02-14
        超级大会员 +372天
        开通时间 2030-01-20 19:05:44
        有效期至 2031-02-20 00:00:00
        大会员 +372天
        开通时间 2030-01-20 19:05:43
        有效期至 2032-11-12
        大会员 +366天
        开通时间 2029-10-02 01:50:17
        有效期至 2031-03-02
        """, origin: .screenshot)
        XCTAssertEqual(result.service, "哔哩哔哩")
        XCTAssertEqual(result.candidates.map { "\($0.tier):\($0.expiry ?? "?")" }.sorted(),
                       ["大会员:2031-03-02", "大会员:2032-11-12", "超级大会员:2031-02-20"].sorted())
    }

    func testQQColumnsDoNotSwapTierDates() {
        func line(_ text: String, _ x: Double, _ y: Double, _ width: Double) -> ImportLine {
            .init(text: text, box: .init(x: x, y: y, width: width, height: 0.025))
        }
        let document = ImportDocument(origin: .screenshot, lines: ImportInput.layout([
            line("QQ 音乐", 0.05, 0.90, 0.12),
            line("超级会员", 0.10, 0.80, 0.17), line("豪华绿钻", 0.55, 0.80, 0.16),
            line("2032-03-07 续费", 0.10, 0.75, 0.25), line("2033-11-21 续费", 0.55, 0.75, 0.25),
            line("听书会员", 0.10, 0.66, 0.18), line("2032-03-07 续费", 0.10, 0.61, 0.25)
        ]))
        let result = AuthorizationRecognition.recognize(document, names: [])
        XCTAssertEqual(result.service, "QQ 音乐")
        XCTAssertEqual(result.candidates.map { "\($0.tier):\($0.expiry ?? "?")" }.sorted(),
                       ["超级会员:2032-03-07", "豪华绿钻:2033-11-21", "听书会员:2032-03-07"].sorted())
    }

    func testOtherScreenshotFormatsAndUnknownProduct() {
        let examples: [(String, String, String, String)] = [
            ("京东 PLUS\nPLUS会员 年卡\n33.02.15到期", "京东 PLUS", "PLUS 年卡", "2033-02-15"),
            ("会员至 2034/01/03\n语音轻松跑", "Keep", "Keep 会员", "2034-01-03"),
            ("库库 AI\nSVIP9\nSVIP 至：2036-03-19", "百度网盘", "超级会员 SVIP", "2036-03-19"),
            ("WPS 云服务\n超级会员 有效期至 2037年5月10日", "WPS", "超级会员", "2037-05-10")
        ]
        for (text, service, tier, date) in examples {
            let result = recognize(text, origin: .screenshot)
            XCTAssertEqual(result.service, service, text)
            XCTAssertEqual(result.candidates.first?.tier, tier, text)
            XCTAssertEqual(result.candidates.first?.expiry, date, text)
        }
        let unknown = recognize("A New Product\nPlan: Family Plus\nExpiration date: 18 Feb 2027")
        XCTAssertNil(unknown.service)
        XCTAssertEqual(unknown.candidates.first?.tier, "Family Plus")
        XCTAssertEqual(unknown.candidates.first?.expiry, "2027-02-18")
    }

    func testRelativeDateRenewalPromotionAndInvalidDatesRemainUnknown() {
        let result = recognize("""
        Parallels Desktop Pro Edition
        Subscription: 12 months
        Next renewal date: 2027-03-01
        Offer expires on 2027-01-01
        Your subscription expires on 2027-02-29
        上次付款日期 2026-03-01
        超过30天后到期
        """)
        XCTAssertEqual(result.service, "Parallels Desktop")
        XCTAssertEqual(result.candidates.first?.tier, "Pro")
        XCTAssertTrue(result.candidates.allSatisfy { $0.expiry == nil && !$0.perpetual })
    }

    func testPerpetualLicenseDoesNotInheritSupportEndAndRangesUseEnd() {
        let perpetual = recognize("Parallels Desktop Standard Edition\nPerpetual license; support expires on February 18, 2027.")
        XCTAssertEqual(perpetual.candidates.count, 1)
        XCTAssertEqual(perpetual.candidates.first?.tier, "Standard")
        XCTAssertTrue(perpetual.candidates.first?.perpetual == true)
        XCTAssertNil(perpetual.candidates.first?.expiry)

        let dateRange = recognize("WPS 超级会员 有效期：2026-03-01 至 2027-03-01")
        XCTAssertEqual(dateRange.candidates.compactMap(\.expiry), ["2027-03-01"])
    }

    func testMultiServiceAndQuotedDatesDoNotPickAccountSilently() {
        let ambiguous = recognize("腾讯视频 SVIP：2031-09-14\nWPS 超级会员 有效期至 2037-05-10", origin: .screenshot)
        XCTAssertNil(ambiguous.service)
        XCTAssertTrue(ambiguous.ambiguousService)
        let quoted = recognize("Parallels Desktop Pro\nNext billing date: 2027-02-14\n-----Original Message-----\nValid until February 18, 2099")
        XCTAssertTrue(quoted.candidates.allSatisfy { $0.expiry == nil })
    }

    @MainActor private func repository() throws -> AuthorizationRepository {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ServiceWatch-Import-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return .init(fileURL: folder.appendingPathComponent("authorizations.json"))
    }

    @MainActor func testReviewAndNewServiceSaveAreSeparateAndPersistOnlyConfirmedFields() async throws {
        let repo = try repository()
        let store = DemoStore(repository: repo)
        let result = AuthorizationRecognition.recognize(try ImportInput.read(fixture("Parallels-Pro.eml")), names: [])
        let candidate = try XCTUnwrap(result.candidates.first)
        var draft = AuthorizationImportDraft(origin: .email, name: "Parallels Desktop", service: nil, candidate: candidate)
        draft.expiry = "2027-02-19"
        XCTAssertEqual(try store.prepareImport(draft).entitlements.first?.expires, "2027-02-19")
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo.fileURL.path))
        let id = try store.saveImport(draft)
        let reopened = DemoStore(repository: repo)
        let service = try XCTUnwrap(reopened.services.first { $0.id == id })
        XCTAssertEqual(service.entitlements.first?.tier, "Pro")
        XCTAssertEqual(service.entitlements.first?.expires, "2027-02-19")
        XCTAssertEqual(service.entitlements.first?.importOrigin, .email)
        XCTAssertEqual(reopened.changes.last?.summary, "导入添加服务与授权")
        XCTAssertThrowsError(try reopened.saveImport(draft))
        let saved = try String(contentsOf: repo.fileURL, encoding: .utf8)
        XCTAssertFalse(saved.contains("EXAMPLE-NOTREAL"))
        XCTAssertFalse(saved.contains("Your subscription"))
        XCTAssertFalse(saved.contains("receipt@example.invalid"))
    }

    @MainActor func testUpdateRequiresTargetAndPreservesOtherTierAndRenewal() async throws {
        let repo = try repository()
        try ServiceFixtures.seed(repo)
        let store = DemoStore(repository: repo)
        let bili = try XCTUnwrap(store.services.first { $0.name == "示例影院" })
        let original = try Data(contentsOf: repo.fileURL)
        let parsed = RecognizedAuthorization(tier: "超级大会员", expiry: "2035-03-06", evidence: "Synthetic")
        var draft = AuthorizationImportDraft(origin: .screenshot, name: bili.name, service: bili, candidate: parsed)
        XCTAssertThrowsError(try store.saveImport(draft))
        draft = draft.selection(.add, in: bili)
        XCTAssertThrowsError(try store.saveImport(draft))
        draft = draft.selection(.update(bili.entitlements[0].id), in: bili)
        draft.validity = "待确认"
        XCTAssertThrowsError(try store.saveImport(draft))
        XCTAssertEqual(try Data(contentsOf: repo.fileURL), original)

        draft.validity = "有到期日"
        try store.saveImport(draft)
        let loaded = DemoStore(repository: repo)
        let updated = try XCTUnwrap(loaded.services.first { $0.id == bili.id })
        XCTAssertEqual(updated.entitlements[0].id, bili.entitlements[0].id)
        XCTAssertEqual(updated.entitlements[0].expires, "2035-03-06")
        XCTAssertEqual(updated.entitlements[0].importOrigin, .screenshot)
        XCTAssertEqual(updated.entitlements[1], bili.entitlements[1])
        XCTAssertEqual(updated.renewalPlan, bili.renewalPlan)
        XCTAssertEqual(updated.paidAmount, bili.paidAmount)
        XCTAssertThrowsError(try store.saveImport(draft)) // A stale review cannot replace a newer record.
    }
}
