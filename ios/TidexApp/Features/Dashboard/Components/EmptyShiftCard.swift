import SwiftUI

/// Placeholder card displayed when there are no shifts for a month
/// Shows skeleton placeholders matching the FeaturedShiftCard layout
struct EmptyShiftCard: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  /// When true, shows shimmer animation (for loading)
  var isLoading: Bool = false  // swiftlint:disable:this explicit_acl
  /// Optional action for a small footer CTA
  var onAddShift: (() -> Void)?  // swiftlint:disable:this explicit_acl
  var isElevated: Bool = true  // swiftlint:disable:this explicit_acl

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

  private var usesFixedCardHeight: Bool {
    !dynamicTypeSize.isAccessibilitySize
  }

  private var showsAddShiftButton: Bool {
    !isLoading && onAddShift != nil
  }

  // MARK: - Body

  var body: some View {  // swiftlint:disable:this explicit_acl
    VStack(spacing: Spacing.sm) {  // swiftlint:disable:this closure_body_length
      // Main card content
      ShiftCardContentLayout(rowSpacing: 4, centerTrailing: true) {  // swiftlint:disable:this no_magic_numbers
        // Placeholder day name and date
        ZStack(alignment: .leading) {
          Text(verbatim: "Monday · 31 Dec")
            .font(.tidexBodyMedium)
            .opacity(0)

          RoundedRectangle(cornerRadius: 5)  // swiftlint:disable:this no_magic_numbers
            .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 140, height: 20)  // swiftlint:disable:this no_magic_numbers
        }
      } leadingBottom: {
        // Placeholder time range
        ZStack(alignment: .leading) {
          HStack(spacing: Spacing.xxs) {
            Image(systemName: "clock")  // swiftlint:disable:this accessibility_label_for_image
              .font(.tidexSubheadline)
              .opacity(0)
            Text(verbatim: "00:00 - 00:00")
              .font(.tidexSubheadline)
              .opacity(0)
          }

          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.2))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 100, height: 17)  // swiftlint:disable:this no_magic_numbers
        }
      } trailingTop: {
        ZStack {
          Text(verbatim: "00 000")
            .font(.tidexTitle)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xs)
            .fill(Color.tidexTextMuted.opacity(0.3))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 96, height: 24)  // swiftlint:disable:this no_magic_numbers
        }
      } trailingBottom: {
        ZStack(alignment: .trailing) {
          Text(verbatim: "00 000 − 00 000")
            .font(.tidexSubheadline)
            .opacity(0)

          RoundedRectangle(cornerRadius: CornerRadius.xxs)
            .fill(Color.tidexTextMuted.opacity(0.2))  // swiftlint:disable:this no_magic_numbers
            .frame(width: 100, height: 17)  // swiftlint:disable:this no_magic_numbers
        }
      }
      .opacity(showsAddShiftButton ? 0.35 : 1)  // swiftlint:disable:this no_magic_numbers
      .accessibilityHidden(showsAddShiftButton)
      .padding(.horizontal, isElevated ? Spacing.mlg : 0)
      .padding(.vertical, ShiftCardMetrics.verticalPadding)
      .frame(minHeight: usesFixedCardHeight ? ShiftCardMetrics.regularCardMinHeight : nil)
      .mask {
        // Cut the placeholder bars around the button so their ends follow the capsule.
        Rectangle()
          .overlay {
            if showsAddShiftButton {
              addShiftLabel
                .padding(Spacing.xs)
                .background(Capsule())
                .blendMode(.destinationOut)
            }
          }
          .compositingGroup()
      }
      .tidexRowSurface(
        cornerRadius: CornerRadius.card,
        fillColor: isElevated ? .tidexSurfacePrimary : .clear
      )
      .shimmer(isActive: isLoading)
      .overlay {
        if let onAddShift, showsAddShiftButton {
          addShiftButton(action: onAddShift)
        }
      }

      // Empty footer space below the card, matching the FeaturedShiftCard footer height
      Color.clear
        .frame(height: 20)  // swiftlint:disable:this no_magic_numbers
    }
  }

  private var addShiftLabel: some View {
    Label {
      Text(.dashboardAddShiftButton)
        .font(.tidexLabelStrong)
        .lineLimit(usesFixedCardHeight ? 1 : nil)
        .minimumScaleFactor(usesFixedCardHeight ? 0.85 : 1)  // swiftlint:disable:this no_magic_numbers
    } icon: {
      Image(systemName: "plus")
        .font(.tidexLabelStrong)
    }
    .foregroundColor(.tidexTextOnBrand)
    .padding(.horizontal, Spacing.lg)
    .frame(minHeight: 44)  // swiftlint:disable:this no_magic_numbers
    .background(Color.tidexBlue, in: Capsule())
  }

  /// Fills the whole card so any tap on the placeholder adds a shift.
  private func addShiftButton(action: @escaping () -> Void) -> some View {
    Button {
      Haptics.play(.light)
      action()
    } label: {
      addShiftLabel
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  VStack(spacing: Spacing.md) {
    EmptyShiftCard(onAddShift: {})  // swiftlint:disable:this no_empty_block
    EmptyShiftCard(isLoading: true)
  }
  .padding(.horizontal, Spacing.lg)
  .background(Color.tidexBackground)
}
