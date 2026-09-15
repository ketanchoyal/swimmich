import XCTest
@testable import ImmichSwiftUI

/// The attribution screen's one real failure mode: a `Resources/Acknowledgements`
/// entry that `project.yml` does not copy. XcodeGen enumerates resources one by
/// one, and a missing file leaves an empty screen that nothing else reports —
/// so this resolves every declared licence out of the app bundle.
final class ThirdPartyLicenseTests: XCTestCase {

    func test_everyDeclaredLicense_resolvesToANonEmptyBundledFile() throws {
        XCTAssertFalse(ThirdPartyLicense.all.isEmpty)
        for license in ThirdPartyLicense.all {
            let text = try ThirdPartyLicense.licenseText(for: license)
            XCTAssertFalse(
                text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(license.id) resolved to an empty file"
            )
        }
    }

    /// The file that resolves is the *right* file for its dependency: a copy
    /// pasted under the wrong name would still be non-empty.
    func test_socketIO_isDeclared() throws {
        let socket = try XCTUnwrap(ThirdPartyLicense.all.first { $0.id == "socket.io-client-swift" })
        XCTAssertEqual(socket.resourceName, "socket.io-client-swift")
        XCTAssertTrue(try ThirdPartyLicense.licenseText(for: socket).contains("MIT License"))
    }
}
