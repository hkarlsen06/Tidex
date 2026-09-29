import SwiftUI

/// One block on the pay settings screen: a small heading, rows on a card, and an optional note.
struct PaySettingsSection<Content: View>: View {
  let title: LocalizedStringResource
  var footer: Text?
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(title)
        .font(.tidexLabel)
        .foregroundStyle(Color.tidexTextSecondary)
        .padding(.horizontal, Spacing.md)
        .accessibilityAddTraits(.isHeader)

      VStack(alignment: .leading, spacing: 0) {
        content
      }
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))

      if let footer {
        footer
          .font(.tidexFootnote)
          .foregroundStyle(Color.tidexTextSecondary)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, Spacing.md)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// A row with the setting's name on the left and its value or control on the right.
/// The value never wraps. When the two don't fit on one line, the value moves to its own line,
/// still trailing, so it lines up with the values in the other rows.
struct PaySettingsRow<Value: View>: View {
  let title: LocalizedStringResource
  @ViewBuilder let value: Value

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: Spacing.sm) {
        titleText
        Spacer(minLength: Spacing.xs)
        value
          .fixedSize()
      }
      .padding(.vertical, Spacing.xxs)

      VStack(alignment: .leading, spacing: Spacing.xxs) {
        titleText
        value
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .padding(.vertical, Spacing.sm)
    }
    .padding(.horizontal, Spacing.md)
    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
    .contentShape(Rectangle())
  }

  private var titleText: some View {
    Text(title)
      .font(.tidexBody)
      .foregroundStyle(Color.tidexTextPrimary)
  }
}

/// A row whose value is a menu of options.
struct PaySettingsPickerRow<Selection: Hashable, Options: View>: View {
  let title: LocalizedStringResource
  @Binding var selection: Selection
  @ViewBuilder let options: Options

  var body: some View {
    PaySettingsRow(title: title) {
      Picker(String(localized: title), selection: $selection) { options }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(.tidexTextSecondary)
    }
  }
}

/// The line between two rows, inset to where the row text starts.
struct PaySettingsRowDivider: View {
  var body: some View {
    Divider()
      .padding(.leading, Spacing.md)
  }
}
