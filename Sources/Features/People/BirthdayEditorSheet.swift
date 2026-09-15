import SwiftUI

/// Edit sheet for one person's birthday (gap G15).
///
/// Presentation only: it knows neither `PersonResponseDto` nor the wire format.
/// It hands back a `Date` (or `nil` for the erase) and the call site does the
/// conversion — which keeps the "nothing is written without Save" rule intact:
/// Cancel and the dismiss gesture drop the draft without touching the view model.
struct BirthdayEditorSheet: View {
    @Binding var draft: Date
    /// A person with no birthday has nothing to erase, so the destructive
    /// button is not drawn at all.
    let hasExistingBirthday: Bool
    let onSave: (Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Day-level comparison: an instant comparison would refuse "today"
    /// because the picker's date carries the current time. The server's field
    /// is `format: date` and refuses a future day with a 422, so the refusal
    /// happens here, before the request.
    private var isFuture: Bool {
        Calendar.current.startOfDay(for: draft) > Calendar.current.startOfDay(for: Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: PVSpacing.s16) {
                DatePicker("Birthday", selection: $draft, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("birthdayPicker")

                if isFuture {
                    Text("Birthday can't be in the future")
                        .font(.pvCaption)
                        .foregroundStyle(Color.textSecondaryPV)
                }

                if hasExistingBirthday {
                    Button("Clear Birthday", role: .destructive) {
                        onSave(nil)
                        dismiss()
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("birthdayClear")
                }
            }
            .padding(PVSpacing.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.bgPrimary)
            .navigationTitle("Birthday")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(isFuture)
                    .accessibilityIdentifier("birthdaySave")
                }
            }
        }
    }
}
