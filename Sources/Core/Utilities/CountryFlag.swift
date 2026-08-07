import Foundation

/// Maps a free-text country name (as returned by Immich's reverse geocoder,
/// e.g. "France", "United States") to its flag emoji. The server's
/// `ExifResponseDto.country` carries no flag field, so we derive it locally.
///
/// Thread-safe: the lookup table is built once from `Locale.isoRegionCodes`
/// and stored in a static `let`.
enum CountryFlag {

    /// Country-name → ISO region code, built lazily once. Keys are lowercased
    /// for case-insensitive matching against the geocoder's free-text output.
    private static let nameToCode: [String: String] = {
        var map: [String: String] = [:]
        for code in Locale.isoRegionCodes {
            // Use the current locale to read each region's display name so
            // both English ("France") and localized ("Francia") inputs resolve.
            let nameEN = Locale(identifier: "en").localizedString(forRegionCode: code)?.lowercased()
            let nameCurrent = Locale.current.localizedString(forRegionCode: code)?.lowercased()
            if let nameEN { map[nameEN] = code }
            if let nameCurrent { map[nameCurrent] = code }
        }
        return map
    }()

    /// Returns the flag emoji for `name` (e.g. "France" → "🇫🇷"), or nil when
    /// the country cannot be resolved. Safe to pass nil/empty input.
    static func emoji(forCountryName name: String?) -> String? {
        guard let name, !name.isEmpty else { return nil }
        guard let code = nameToCode[name.lowercased()] else { return nil }
        return flagEmoji(forRegionCode: code)
    }

    /// Converts an ISO region code ("FR") into its flag emoji via the
    /// regional-indicator-symbol Unicode trick. Returns nil for non-letter
    /// or wrong-length input.
    static func flagEmoji(forRegionCode code: String) -> String? {
        let upper = code.uppercased()
        guard upper.count == 2,
              upper.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        let base: UInt32 = 0x1F1E6 // regional indicator A (🇦)
        let scalars = upper.unicodeScalars.compactMap { scalar -> Unicode.Scalar? in
            // A-Z (0x41-0x5A) → offset 0-25 → regional indicator.
            guard (0x41...0x5A).contains(scalar.value) else { return nil }
            return Unicode.Scalar(base + (scalar.value - 0x41))
        }
        guard scalars.count == 2 else { return nil }
        return String(String.UnicodeScalarView(scalars))
    }
}
