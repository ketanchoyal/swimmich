import Foundation

/// The one place a video duration becomes display text.
///
/// Two entries and no more, because the app holds durations from two clocks
/// that do NOT share a unit:
///
/// - Immich's DTOs (`TimeBucketAssetResponseDto`, `AssetResponseDto`) carry
///   `duration` in **milliseconds** — the grid badges, the viewer filmstrip and
///   the offline tiles all read that cell;
/// - AVFoundation's player clock (`AVPlayer.currentTime()`,
///   `asset.load(.duration)`) is in **seconds** — the transport labels and the
///   progress bar read that one.
///
/// Reading a millisecond cell as seconds is exactly the defect this type closes
/// (7173 ms rendered as "119:33"): each entry point names its unit, so no call
/// site has to decide, and the two surfaces of one video cannot diverge.
enum VideoDurationFormatter {
    /// "m:ss" from an Immich duration, in milliseconds. 7173 → "0:07".
    static func string(milliseconds: Int) -> String {
        // The ONLY milliseconds→seconds conversion in the module.
        render(seconds: (Double(milliseconds) / 1000).rounded())
    }

    /// "m:ss" from the player clock, in seconds. 7.173 → "0:07".
    static func string(seconds: Double) -> String {
        // NaN/±infinity: an indefinite media hands the player no duration, and
        // `Int(rounded())` traps on those.
        guard seconds.isFinite, seconds > 0 else { return "0:00" }
        // A finite Double can still sit past Int.max (a corrupt value) where the
        // conversion traps too; clamp so rendering can never crash playback.
        return render(seconds: min(seconds, Double(Int.max / 2)).rounded())
    }

    /// The single rendering rule, inherited from the grid badge ("V11"):
    /// `m:ss`, minutes unbounded, seconds two digits, no hour component.
    private static func render(seconds: Double) -> String {
        let whole = Int(seconds)
        guard whole > 0 else { return "0:00" }
        // Interpolated minutes, format only the seconds: `%d` with a Swift `Int`
        // reads 32 bits of the 64-bit vararg, which wraps the minutes column
        // once a duration passes Int32.minutes (~4085 years of video, but the
        // entry takes any Double).
        return "\(whole / 60):\(String(format: "%02d", whole % 60))"
    }
}
