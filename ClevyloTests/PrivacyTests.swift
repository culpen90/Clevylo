import XCTest
@testable import Clevylo

final class PrivacyTests: XCTestCase {
    func testMarkdownCannotOpenExecutableOrLocalURLSchemes() {
        for url in ["file:///Applications/Calculator.app", "javascript:alert(1)", "data:text/html,hello", "x-apple.systempreferences:test"] {
            XCTAssertFalse(MarkdownSafety.allowsLink(URL(string: url)!))
        }
        XCTAssertTrue(MarkdownSafety.allowsLink(URL(string: "https://example.org/lesson")!))
    }

    func testKeychainRoundtripUsesIsolatedService() throws {
        let keychain = KeychainStore(service: "com.clevylo.tests.\(UUID().uuidString)")
        defer { try? keychain.delete() }
        XCTAssertNil(try keychain.load())
        try keychain.save("synthetic-test-value-not-an-api-key")
        XCTAssertEqual(try keychain.load(), "synthetic-test-value-not-an-api-key")
        try keychain.save("replacement-synthetic-test-value")
        XCTAssertEqual(try keychain.load(), "replacement-synthetic-test-value")
        try keychain.delete()
        XCTAssertNil(try keychain.load())
    }
}
