import SwiftUI

/// Header shared by every Stats chart card: a small title, the one number the chart is about,
/// and an optional caption. Empty states pass no value and put their message in the caption.
struct StatsChartHeader<Accessory: View>: View {  // swiftlint:disable:this explicit_acl explicit_top_level_acl
  let title: String  // swiftlint:disable:this explicit_acl
  var value: String?  // swiftlint:disable:this explicit_acl
  var caption: String?  // swiftlint:disable:this explicit_acl
  var valueColor: Color = .tidexTextPrimary  // swiftlint:disable:this explicit_acl explicit_type_interface
  @ViewBuilder var accessory: () -> Accessory  // swiftlint:disable:this explicit_acl

  @Environment(\.dynamicTypeSize) private var dynamicTypeSize  // swiftlint:disable:this explicit_type_interface

  var body: some View {  // swiftlint:disable:this explicit_acl
    HStack(alignment: .top, spacing: Spacing.sm) {
      VStack(alignment: .leading, spacing: Spacing.xxs) {
        Text(title)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextSecondary)

        if let value {
          Text(value)
            .font(.tidexLargeTitle)
            .monospacedDigit()
            .foregroundColor(valueColor)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(dynamicTypeSize.isAccessibilitySize ? 1 : 0.7)  // swiftlint:disable:this line_length no_magic_numbers
        }

        if let caption {
          Text(caption)
            .font(.tidexFootnote)
            .foregroundColor(.tidexTextSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityAddTraits(.isHeader)

      Spacer(minLength: 0)

      accessory()
    }
  }
}

extension StatsChartHeader where Accessory == EmptyView {
  init(title: String, value: String? = nil, caption: String? = nil) {  // swiftlint:disable:this explicit_acl
    self.init(title: title, value: value, caption: caption) { EmptyView() }
  }
}
