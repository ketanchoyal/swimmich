import SwiftUI

/// Full-width month-year separator banner for the timeline grid.
///
/// Appears once per month change (driven by `TimelineSectionBuilder`). Uses a
/// bold large-title-rank type face to anchor each month visually, with
/// generous top padding so successive months get clear breathing room (the
/// previous month's last day group + this banner read as a deliberate section
/// break rather than a mid-scroll interruption).
///
/// `display` is pre-formatted by `TimelineSectionBuilder` (e.g. "July 2024")
/// so this view holds zero date logic — it's pure presentation.
struct MonthYearBanner: View {
    let display: String

    var body: some View {
        Text(display)
            .font(.title.weight(.bold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 32)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}
