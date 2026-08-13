import XCTest
@testable import ImmichSwiftUI

final class QRServerConfigParserTests: XCTestCase {

    func test_parse_jsonServerUrl() {
        let url = QRServerConfigParser.parse(#"{"serverUrl": "https://photos.example.com"}"#)
        XCTAssertEqual(url?.absoluteString, "https://photos.example.com")
    }

    func test_parse_jsonUrlAlias() {
        let url = QRServerConfigParser.parse(#"{"url": "photos.example.com"}"#)
        XCTAssertEqual(url?.absoluteString, "https://photos.example.com")
    }

    func test_parse_bareURLDefaultsToHttps() {
        let url = QRServerConfigParser.parse("photos.example.com")
        XCTAssertEqual(url?.absoluteString, "https://photos.example.com")
    }

    func test_parse_fullURLKeepsScheme() {
        let url = QRServerConfigParser.parse("http://192.168.1.10:2283")
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.10:2283")
    }

    func test_parse_trailingSlashStripped() {
        let url = QRServerConfigParser.parse("https://photos.example.com/")
        XCTAssertEqual(url?.absoluteString, "https://photos.example.com")
    }

    func test_parse_jsonWithoutServerUrl_isNil() {
        XCTAssertNil(QRServerConfigParser.parse(#"{"foo": "bar"}"#))
    }

    func test_parse_empty_isNil() {
        XCTAssertNil(QRServerConfigParser.parse(""))
        XCTAssertNil(QRServerConfigParser.parse("   "))
    }

    func test_parse_garbage_isNil() {
        XCTAssertNil(QRServerConfigParser.parse("not a url at all"))
    }

    func test_parse_whitespaceAroundPayload() {
        let url = QRServerConfigParser.parse("  photos.example.com  ")
        XCTAssertEqual(url?.absoluteString, "https://photos.example.com")
    }
}
