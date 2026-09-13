import SwiftUI

/// Expiration control for a shared link — the nine offsets the Flutter client
/// offers (Never, 30 min, 1 h, 6 h, 1 d, 7 d, 30 d, 90 d, 1 year), plus a custom
/// date & time.
///
/// One control shared by the create and edit sheets, so the two surfaces can't
/// drift. `date == nil` means "never expires", which is exactly what the server
/// stores for a null `expiresAt`.
///
/// Selecting a preset writes `now + duration` into the binding; the custom entry
/// shows a `DatePicker` that edits the binding directly. The date picker is the
/// only editor in custom mode — no preset/time round-trip, so the two can never
/// disagree about which value is authoritative.
struct SharedLinkExpiryPicker: View {
    /// `nil` = never expires.
    @Binding var date: Date?
    /// Selection is local: a link loaded with an expiry shows its exact date in
    /// custom mode rather than guessing which preset produced it.
    @State private var selection: Selection

    /// The picker's rows. `duration` is nil for the two modes that are not a
    /// fixed offset.
    enum Selection: Hashable, CaseIterable {
        case never
        case thirtyMinutes
        case oneHour
        case sixHours
        case oneDay
        case sevenDays
        case thirtyDays
        case ninetyDays
        case oneYear
        case custom

        var duration: TimeInterval? {
            switch self {
            case .never, .custom: nil
            case .thirtyMinutes: 30 * 60
            case .oneHour: 60 * 60
            case .sixHours: 6 * 60 * 60
            case .oneDay: 24 * 60 * 60
            case .sevenDays: 7 * 24 * 60 * 60
            case .thirtyDays: 30 * 24 * 60 * 60
            case .ninetyDays: 90 * 24 * 60 * 60
            case .oneYear: 365 * 24 * 60 * 60
            }
        }

        /// The row's title. A `@ViewBuilder` switch of `Text` literals rather
        /// than a computed `LocalizedStringKey`: a key produced by a switch
        /// expression (or a ternary) is invisible to Xcode's string extractor,
        /// so those keys get pruned from the catalog and never reach
        /// translators. Each literal sits in a `Text(...)` call the extractor
        /// can see.
        @ViewBuilder
        var label: some View {
            switch self {
            case .never: Text("Never")
            case .thirtyMinutes: Text("30 minutes")
            case .oneHour: Text("1 hour")
            case .sixHours: Text("6 hours")
            case .oneDay: Text("1 day")
            case .sevenDays: Text("7 days")
            case .thirtyDays: Text("30 days")
            case .ninetyDays: Text("90 days")
            case .oneYear: Text("1 year")
            case .custom: Text("Custom…")
            }
        }
    }

    init(date: Binding<Date?>) {
        _date = date
        _selection = State(initialValue: date.wrappedValue == nil ? .never : .custom)
    }

    var body: some View {
        Picker("Expiration", selection: $selection) {
            ForEach(Selection.allCases, id: \.self) { option in
                option.label.tag(option)
            }
        }
        .accessibilityIdentifier("sharedLinkExpiryPicker")
        .onChange(of: selection) { _, newValue in
            switch newValue {
            case .never:
                date = nil
            case .custom:
                // Keep whatever is there (or start a week out, like Flutter);
                // the DatePicker below is the editor from here on.
                if date == nil { date = Date().addingTimeInterval(7 * 24 * 60 * 60) }
            default:
                if let seconds = newValue.duration {
                    date = Date().addingTimeInterval(seconds)
                }
            }
        }

        if selection == .custom, let current = date {
            DatePicker(
                "Expiry date",
                selection: Binding(get: { current }, set: { date = $0 }),
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
        } else if let current = date {
            // A preset was chosen: state the resulting moment, so the choice is
            // verifiable rather than implied.
            Text("Expires \(current.formatted(date: .abbreviated, time: .shortened))")
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
        }
    }
}
