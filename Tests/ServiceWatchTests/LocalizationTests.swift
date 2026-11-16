import XCTest
@testable import ServiceWatch

final class LocalizationTests: XCTestCase {
    func testSystemUsesFirstSupportedLanguageAndFallsBackToEnglish() {
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["fr-FR", "zh-HK", "en-GB"]), .simplifiedChinese)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["en-US", "zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.system.resolved(preferredLanguages: ["de-DE"]), .english)
        XCTAssertEqual(AppLanguage.english.resolved(preferredLanguages: ["zh-Hans"]), .english)
        XCTAssertEqual(AppLanguage.simplifiedChinese.resolved(preferredLanguages: ["en-US"]), .simplifiedChinese)
    }

    func testTranslationsKeepUserEnteredContent() {
        let tier = "卓越 {0} 😀"
        XCTAssertEqual(L10n.text("修改\(tier)授权", language: .english), "Edit 卓越 {0} 😀 license")
        XCTAssertEqual(L10n.text("修改\(tier)授权", language: .simplifiedChinese), "修改卓越 {0} 😀授权")
        XCTAssertEqual(L10n.text("与“\(tier)”匹配的服务为空", language: .english), "No services match “卓越 {0} 😀”.")
    }
}
