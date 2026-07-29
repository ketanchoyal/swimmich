import Foundation

/// Type-erased Encodable for optional body parameters.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: some Encodable) {
        self._encode = { encoder in try value.encode(to: encoder) }
    }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}
