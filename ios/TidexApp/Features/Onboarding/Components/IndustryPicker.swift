import SwiftUI
import UIKit

/// Industry selector for sample paycheck screen
/// Displays different sample data based on selection
enum SampleIndustry: String, CaseIterable, Identifiable {
  case retail
  case restaurant
  case healthcare

  var id: String { rawValue }

  var sampleData: SamplePaycheckData {
    switch self {
    case .retail:
      return SamplePaycheckData(
        gross: 24_650,  // swiftlint:disable:this no_magic_numbers
        basePay: 21_000,  // swiftlint:disable:this no_magic_numbers
        eveningSupplements: 2_400,  // swiftlint:disable:this no_magic_numbers
        weekendBonus: 1_250,  // swiftlint:disable:this no_magic_numbers
        taxDeducted: 4_920,  // swiftlint:disable:this no_magic_numbers
        netPay: 19_730  // swiftlint:disable:this no_magic_numbers
      )

    case .restaurant:
      return SamplePaycheckData(
        gross: 27_800,  // swiftlint:disable:this no_magic_numbers
        basePay: 23_500,  // swiftlint:disable:this no_magic_numbers
        eveningSupplements: 3_100,  // swiftlint:disable:this no_magic_numbers
        weekendBonus: 1_200,  // swiftlint:disable:this no_magic_numbers
        taxDeducted: 5_560,  // swiftlint:disable:this no_magic_numbers
        netPay: 22_240  // swiftlint:disable:this no_magic_numbers
      )

    case .healthcare:
      return SamplePaycheckData(
        gross: 31_200,  // swiftlint:disable:this no_magic_numbers
        basePay: 26_000,  // swiftlint:disable:this no_magic_numbers
        eveningSupplements: 3_800,  // swiftlint:disable:this no_magic_numbers
        weekendBonus: 1_400,  // swiftlint:disable:this no_magic_numbers
        taxDeducted: 6_240,  // swiftlint:disable:this no_magic_numbers
        netPay: 24_960  // swiftlint:disable:this no_magic_numbers
      )
    }
  }

  @MainActor
  func localizedName() -> String {
    let key = "onboarding.paycheck.industry.\(rawValue)"
    return String(localized: String.LocalizationValue(key), table: "Localizable")
  }
}

/// Sample paycheck data for onboarding demo
struct SamplePaycheckData {
  let gross: Double
  let basePay: Double
  let eveningSupplements: Double
  let weekendBonus: Double
  let taxDeducted: Double
  let netPay: Double
}

/// Segmented control for industry selection
struct IndustryPicker: View {
  @Binding var selection: SampleIndustry

  var body: some View {
    HStack(spacing: 0) {
      ForEach(SampleIndustry.allCases) { industry in
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selection = industry
          }
        } label: {
          Text(industry.localizedName())
            .font(selection == industry ? .tidexLabelStrong : .tidexLabel)
            .foregroundColor(selection == industry ? .tidexTextPrimary : .tidexTextMuted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.sm)
            .background(
              selection == industry
                ? Color.tidexSurfacePrimary
                : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(Spacing.xxs)
    .background(Color.tidexSurfaceSecondary)
    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
  }
}

#Preview {
  VStack(spacing: Spacing.lg) {
    IndustryPicker(selection: .constant(.retail))
    IndustryPicker(selection: .constant(.restaurant))
    IndustryPicker(selection: .constant(.healthcare))
  }
  .padding()
  .background(Color.tidexBackground)
}
