import XCTest
import Security
@testable import RackyCore

final class LegacyKeychainInteractionTests: XCTestCase {
    func testRestoresInteractionAfterOperationThrows() {
        var enabled = true
        XCTAssertThrowsError(try LegacyKeychainInteraction.withoutUI(
            get: { $0.pointee = DarwinBoolean(enabled); return errSecSuccess },
            set: { enabled = $0; return errSecSuccess },
            operation: { () -> Int in
                XCTAssertFalse(enabled)
                throw BrowserComputerError.missingToken
            }))
        XCTAssertTrue(enabled)
    }
    func testPreservesAlreadyDisabledStateAndDoesNotRunOnSuppressionFailure() throws {
        var enabled = false
        let value = try LegacyKeychainInteraction.withoutUI(
            get: { $0.pointee = DarwinBoolean(enabled); return errSecSuccess },
            set: { enabled = $0; return errSecSuccess }, operation: { 42 })
        XCTAssertEqual(value, 42)
        XCTAssertFalse(enabled)
        var ran = false
        XCTAssertThrowsError(try LegacyKeychainInteraction.withoutUI(
            get: { $0.pointee = true; return errSecSuccess },
            set: { _ in errSecParam }, operation: { ran = true }))
        XCTAssertFalse(ran)
    }
}
