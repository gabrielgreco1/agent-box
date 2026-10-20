import Foundation
import AppKit
import XCTest
@testable import Racky

final class DesktopStreamTests: XCTestCase {
    func testShiftPunctuationUsesTypedCharactersInsteadOfDroppingSymbols() {
        for character in [":", "<", ">", "\"", "A"] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .shift,
                                        timestamp: 0, windowNumber: 0, context: nil, characters: character,
                                        charactersIgnoringModifiers: character, isARepeat: false, keyCode: 0)!
            XCTAssertEqual(DesktopKeyboardMapping.text(for: event), character)
        }
        let shortcut = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                       timestamp: 0, windowNumber: 0, context: nil, characters: "l",
                                       charactersIgnoringModifiers: "l", isARepeat: false, keyCode: 37)!
        XCTAssertNil(DesktopKeyboardMapping.text(for: shortcut))
    }
    func testCFNetworkJPEGPartsRequireValidatedDesktopMultipartResponse() {
        func response(_ type: String, status: Int = 200, source: String = "desktop") -> HTTPURLResponse {
            HTTPURLResponse(url: URL(string: "http://127.0.0.1:8765/v1/stream")!, statusCode: status,
                            httpVersion: "HTTP/1.1", headerFields: ["Content-Type": type, "X-Racky-Frame-Source": source])!
        }
        var validator = DesktopStreamResponseValidator()
        XCTAssertFalse(validator.accepts(response("image/jpeg")))
        XCTAssertFalse(validator.accepts(response("multipart/x-mixed-replace", source: "browser")))
        XCTAssertTrue(validator.accepts(response("multipart/x-mixed-replace; boundary=rackyframe")))
        XCTAssertTrue(validator.accepts(response("image/jpeg")))
        XCTAssertTrue(validator.accepts(response("image/jpeg")))
        XCTAssertFalse(validator.accepts(response("application/json")))
        XCTAssertFalse(validator.accepts(response("image/jpeg", status: 401)))
    }
}
