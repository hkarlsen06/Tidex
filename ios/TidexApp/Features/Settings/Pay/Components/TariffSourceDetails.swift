import SwiftUI

struct TariffSourceDetails: View {
  let version: TariffVersion

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let note = version.coverageNote, !note.isEmpty {
        Text(verbatim: note)
          .font(.tidexFootnote)
          .foregroundColor(.tidexTextSecondary)
      }
      if let legalDate = version.legalEffectiveDate, legalDate != version.effective_date,
        let date = Date.fromISODateString(legalDate)
      {
        let formattedDate = date.formatted(.dateTime.day().month().year().locale(.appLocale))
        Text(
          "\(String(localized: .tariffPublishedDate)) \(formattedDate)"
        )
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
      }
      if let source = version.sourceURL {
        Link(destination: source) {
          Label(.tariffSource, systemImage: "arrow.up.right")
            .font(.tidexFootnote)
        }
        .foregroundColor(.tidexBlueText)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
