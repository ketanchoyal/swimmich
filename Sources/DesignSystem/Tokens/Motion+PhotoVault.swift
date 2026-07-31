import SwiftUI

// MARK: - PhotoVault Motion Tokens
//
// Three named springs cover the app's motion language. `adaptive(reduceMotion:)`
// honors Reduce Motion: when the user enabled it, ANY requested animation is
// replaced with `.linear(duration: 0.3)` — deliberately NOT a spring, so motion
// stays minimal yet present (AC-019). The reduceMotion flag is passed in by the
// caller from `@Environment(\.accessibilityReduceMotion)`.
//
// `PVDuration` mirrors the Immich `ImmichDuration` scale (ms) for any caller
// that needs a raw TimeInterval (custom transitions, debounce haptics, etc.).

enum PVMotion {
    static let standard: Animation = .spring(response: 0.35, dampingFraction: 0.86)
    static let snappy: Animation = .spring(response: 0.25, dampingFraction: 0.75)
    static let gentle: Animation = .easeInOut(duration: 0.5)

    /// When `reduceMotion` is true, returns a non-spring fallback animation
    /// (`.linear(duration: 0.3)`) per the Reduce Motion accessibility contract.
    static func adaptive(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.3) : animation
    }
}

/// Immich `ImmichDuration` scale bridged to `TimeInterval` (seconds).
enum PVDuration {
    static let extraFast: TimeInterval = 0.10
    static let fast: TimeInterval = 0.15
    static let normal: TimeInterval = 0.20
    static let moderate: TimeInterval = 0.30
    static let slow: TimeInterval = 0.50
    static let extraSlow: TimeInterval = 0.70
}
