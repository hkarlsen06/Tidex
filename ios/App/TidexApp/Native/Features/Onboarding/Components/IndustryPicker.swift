import SwiftUI
import UIKit

/// Industry selector for sample paycheck screen
/// Displays different sample data based on selection
enum SampleIndustry: String, CaseIterable, Identifiable {
    case retail = "retail"
    case restaurant = "restaurant"
    case healthcare = "healthcare"

    var id: String { rawValue }

    var sampleData: SamplePaycheckData {
        switch self {
        case .retail:
            return SamplePaycheckData(
                gross: 24650,
                basePay: 21000,
                eveningSupplements: 2400,
                weekendBonus: 1250,
                taxDeducted: 4920,
                netPay: 19730
            )
        case .restaurant:
            return SamplePaycheckData(
                gross: 27800,
                basePay: 23500,
                eveningSupplements: 3100,
                weekendBonus: 1200,
                taxDeducted: 5560,
                netPay: 22240
            )
        case .healthcare:
            return SamplePaycheckData(
                gross: 31200,
                basePay: 26000,
                eveningSupplements: 3800,
                weekendBonus: 1400,
                taxDeducted: 6240,
                netPay: 24960
            )
        }
    }

    @MainActor
    func localizedName(_ localization: LocalizationManager) -> String {
        localization.string("onboarding.paycheck.industry.\(rawValue)")
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
    @Environment(\.localization) private var localization

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SampleIndustry.allCases) { industry in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = industry
                    }
                } label: {
                    Text(industry.localizedName(localization))
                        .font(.system(size: 14, weight: selection == industry ? .semibold : .medium))
                        .foregroundColor(selection == industry ? .tidexTextPrimary : .tidexTextMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            selection == industry
                                ? Color.tidexSurfacePrimary
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

#Preview {
    VStack(spacing: 24) {
        IndustryPicker(selection: .constant(.retail))
        IndustryPicker(selection: .constant(.restaurant))
        IndustryPicker(selection: .constant(.healthcare))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
