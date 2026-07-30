import XCTest
@testable import ImmichSwiftUI

final class ExifFormatterTests: XCTestCase {

    /// AC-201: happy-path strings for every formatter.
    func test_AC_201_formatters() {
        let exif = ExifResponseDto(
            make: "Canon",
            model: "EOS R",
            exifImageWidth: 4032,
            exifImageHeight: 3024,
            fileSizeInByte: 4_200_000,
            orientation: "1",
            dateTimeOriginal: "2024-07-30T14:32:00.000Z",
            modifyDate: nil,
            timeZone: "UTC",
            lensModel: "RF 50mm f/1.8",
            fNumber: 1.8,
            focalLength: 50.0,
            iso: 400,
            exposureTime: "1/250",
            latitude: 48.8566,
            longitude: 2.3522,
            city: "Paris",
            state: "Île-de-France",
            country: "France",
            description: "Sunset",
            projectionType: nil,
            rating: 5
        )

        XCTAssertEqual(exif.focalLengthFormatted, "50 mm")
        XCTAssertEqual(exif.dimensionsFormatted, "4032 × 3024")
        XCTAssertNotNil(exif.fileSizeFormatted, "fileSize must be non-nil")
        XCTAssertTrue(exif.fileSizeFormatted?.contains("MB") == true, "expected MB-scale output, got \(exif.fileSizeFormatted ?? "nil")")
        XCTAssertEqual(exif.apertureFormatted, "f/1.8")
        XCTAssertEqual(exif.isoFormatted, "ISO 400")
        XCTAssertEqual(exif.exposureFormatted, "1/250s")
        XCTAssertEqual(exif.cameraFormatted, "Canon EOS R")
        XCTAssertNotNil(exif.dateFormatted, "date must parse ISO8601")
    }

    /// AC-201b: empty DTO → every formatter returns nil (FM-2 coverage).
    func test_AC_201b_nil_cases() {
        let empty = ExifResponseDto()

        XCTAssertNil(empty.focalLengthFormatted)
        XCTAssertNil(empty.dimensionsFormatted)
        XCTAssertNil(empty.fileSizeFormatted)
        XCTAssertNil(empty.apertureFormatted)
        XCTAssertNil(empty.isoFormatted)
        XCTAssertNil(empty.exposureFormatted)
        XCTAssertNil(empty.cameraFormatted)
        XCTAssertNil(empty.dateFormatted)
    }
}
