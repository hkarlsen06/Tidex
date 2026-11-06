#if DEBUG
  import SwiftUI

  struct DesignReviewTariffCatalogue: View {
    @State private var data = OnboardingData()
    @State private var saved = false

    var body: some View {
      if saved {
        Text(
          verbatim:
            "\(data.selectedTariffTypeId)|\(data.selectedTariffLevel)|\(data.resolvedHourlyWage)"
        )
        .accessibilityIdentifier("tariff.saved-result")
      } else {
        WageScreen(data: data, onContinue: { saved = true })
          .onAppear {
            data.currency = "kr"
            data.wageType = .tariff
            data.selectedTariffTypeId =
              ProcessInfo.processInfo.environment["TIDEX_TEST_TARIFF_TYPE"] ?? "riksavtalen_hotel"
          }
      }
    }
  }
  struct DesignReviewTariffOvertime: View {
    @State private var snapshot: WageSnapshot?
    @State private var saved: String?

    var body: some View {
      Group {
        if let saved {
          Text(verbatim: saved).accessibilityIdentifier("tariff.overtime-saved-result")
        } else if let snapshot {
          WageSnapshotEditorSheet(
            mode: .edit, snapshot: snapshot, snapshots: [snapshot], initialSection: .overtime,
            onSave: { input in
              let dated = input.overtime.rules.filter { $0.dates != nil }
              saved = "\(input.hourlyWage)|\(dated.count)|\(dated.map(\.percent).max() ?? 0)"
              return true
            }, onDelete: { _ in }, onCancel: {})
        } else {
          ProgressView()
        }
      }
      .task {
        guard snapshot == nil,
          let version = try? TariffCatalogueFixture.load().versions.first(where: {
            $0.tariff_type_id == "ks_ch4_375"
          })
        else { return }
        snapshot = WageSnapshot(
          id: "tariff-overtime", user_id: "design-preview", from_date: "2026-11-06",
          hourly_wage: version.rates["1"] ?? 0, wage_level: 1,
          tariff_type_id: version.tariff_type_id, supplements: version.supplements,
          overtime: version.effectiveOvertime, tax_enabled: false, tax_percentage: nil,
          break_enabled: false, break_method: "none", break_threshold_hours: 5.5,
          break_deduction_minutes: 0, created_at: nil)
      }
    }
  }
#endif
