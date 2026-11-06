import SwiftUI

struct TariffSourceDetails: View {
  let version: TariffVersion

  var body: some View {
    DisclosureGroup {
      VStack(alignment: .leading, spacing: Spacing.sm) {
        if let note = version.coverageNote, !note.isEmpty {
          Text(verbatim: note)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
        }
        if let date = Date.fromISODateString(version.legalEffectiveDate ?? version.effective_date) {
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
      .padding(.top, Spacing.xs)
    } label: {
      Text(.tariffAboutAgreement)
        .font(.tidexFootnote)
    }
    .tint(.tidexBlueText)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct TariffCalculationCoverage: View {
  let overtime: OvertimeConfig

  var body: some View {
    Text(
      overtime.runtimeEnabledConfig == nil
        ? LocalizedStringResource.tariffOvertimeManual : .tariffOvertimeWeekly
    )
    .font(.tidexFootnote)
    .foregroundColor(.tidexTextSecondary)
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityIdentifier("tariff.calculation-coverage")
  }
}
