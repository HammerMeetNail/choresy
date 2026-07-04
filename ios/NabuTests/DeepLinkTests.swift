import XCTest
@testable import Nabu

/// Parsing tests for universal links and the quicklog deep link. The handled
/// paths must stay in sync with the backend's apple-app-site-association
/// (internal/app/server.go) and the PWA's route handling.
final class DeepLinkTests: XCTestCase {

    private func parse(_ string: String) -> DeepLink? {
        DeepLink.parse(URL(string: string)!)
    }

    func testVerifyEmail() {
        XCTAssertEqual(
            parse("https://nabu-app.com/verify-email?token=tok123"),
            .verifyEmail(token: "tok123")
        )
    }

    func testVerifyEmailWithoutTokenIsIgnored() {
        XCTAssertNil(parse("https://nabu-app.com/verify-email"))
        XCTAssertNil(parse("https://nabu-app.com/verify-email?token="))
    }

    func testMagicLogin() {
        XCTAssertEqual(
            parse("https://nabu-app.com/magic-login?token=abc"),
            .magicLogin(token: "abc")
        )
    }

    func testJoinHousehold() {
        XCTAssertEqual(
            parse("https://nabu-app.com/join?code=ABC123"),
            .joinHousehold(code: "ABC123")
        )
    }

    func testQuickLogChore() {
        // Parity with the PWA's /?quicklog=chore:<id> notification deep link.
        XCTAssertEqual(
            parse("https://nabu-app.com/?quicklog=chore:42"),
            .quickLog(choreId: 42)
        )
    }

    func testQuickLogMalformedIdIsIgnored() {
        XCTAssertNil(parse("https://nabu-app.com/?quicklog=chore:abc"))
        XCTAssertNil(parse("https://nabu-app.com/?quicklog=activity"))
    }

    func testUnrelatedURLsAreIgnored() {
        XCTAssertNil(parse("https://nabu-app.com/reset-password?token=t"))
        XCTAssertNil(parse("https://nabu-app.com/settings"))
        XCTAssertNil(parse("nabu://callback"))
    }

    func testTokenWithURLEncodedCharactersDecodes() {
        XCTAssertEqual(
            parse("https://nabu-app.com/verify-email?token=a%2Bb"),
            .verifyEmail(token: "a+b")
        )
    }
}
