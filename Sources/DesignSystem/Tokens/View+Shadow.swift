import SwiftUI

// MARK: - PhotoVault Shadow Modifier
//
// Single floating-card shadow used by cards / sheets to lift them off the
// background. Kept as a View modifier so shadow params are never duplicated.

extension View {
    /// Standard floating shadow: black 18% alpha, radius 12, y-offset 4.
    func pvFloatingShadow() -> some View {
        shadow(color: .black.opacity(0.18), radius: 12, x: 0, y: 4)
    }
}
