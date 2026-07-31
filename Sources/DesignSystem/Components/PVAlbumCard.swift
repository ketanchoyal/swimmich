import SwiftUI

// MARK: - PVAlbumCard
//
// Album list/grid card: square cover + title + asset count. Lifted off the
// background with `pvFloatingShadow()` and clipped to the large radius.

struct PVAlbumCard: View {
    var cover: AnyView
    var title: String
    var count: String

    var body: some View {
        VStack(alignment: .leading, spacing: PVSpacing.s8) {
            cover
                .aspectRatio(1, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: PVRadius.lg))

            Text(title)
                .font(.pvHeadline)
                .foregroundStyle(Color.textPrimaryPV)

            Text(count)
                .font(.pvCaption)
                .foregroundStyle(Color.textSecondaryPV)
        }
        .accessibilityElement(children: .combine)
        .pvFloatingShadow()
    }
}
