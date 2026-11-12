import SwiftUI

/// Month or year for Stats, as its own glass control in the row of the floating month picker.
/// Both choices stay visible, and the selected one is filled. Each segment is as wide as its
/// word, so the pill beside it keeps the most room.
struct StatsPeriodPicker: View {
  @Binding var period: StatsPeriod

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var selectionNamespace

  var body: some View {
    HStack(spacing: 0) {
      segment(.month, title: .commonMonth)
      segment(.year, title: .commonYear)
    }
    .padding(Spacing.xxs)
    .frame(height: MonthPickerLayout.height)
    // Like the tab bar, the control stops growing at the largest standard text size and shows
    // its words in the large content viewer instead.
    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    .tidexGlass(
      shape: .rect(cornerRadius: MonthPickerLayout.cornerRadius),
      interactive: true
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(.statsPeriodLabel))
    .accessibilityIdentifier("stats.period")
  }

  private func segment(_ value: StatsPeriod, title: LocalizedStringResource) -> some View {
    let isSelected: Bool = period == value
    return Button {
      withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.8)) {
        period = value
      }
    } label: {
      Text(title)
        .font(.tidexSubheadline.weight(.semibold))
        .foregroundStyle(isSelected ? Color.tidexBlueText : Color.tidexTextSecondary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)  // swiftlint:disable:this no_magic_numbers
        .padding(.horizontal, Spacing.sm)
        .frame(maxHeight: .infinity)
        .background {
          if isSelected {
            Capsule()
              .fill(Color.tidexBlue.opacity(0.12))  // swiftlint:disable:this no_magic_numbers
              .matchedGeometryEffect(id: "selection", in: selectionNamespace)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityShowsLargeContentViewer {
      Text(title)
    }
  }
}
