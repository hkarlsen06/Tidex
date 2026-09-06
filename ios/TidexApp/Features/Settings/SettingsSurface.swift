import SwiftUI

struct TidexSettingsSection<Footer: View, Content: View>: View {
  let title: String?
  var titleColor: Color = .tidexTextSecondary
  var contentPadding: CGFloat = Spacing.md
  let footer: Footer
  let content: Content

  init(
    title: String? = nil,
    titleColor: Color = .tidexTextSecondary,
    contentPadding: CGFloat = Spacing.md,
    @ViewBuilder footer: () -> Footer,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.titleColor = titleColor
    self.contentPadding = contentPadding
    self.footer = footer()
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      if let title {
        Text(title)
          .font(.tidexLabel)
          .foregroundColor(titleColor)
          .textCase(nil)
          .padding(.horizontal, Spacing.sm)
      }

      VStack(spacing: 0) {
        content
      }
      .padding(contentPadding)
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xxl, style: .continuous))

      footer
        .font(.tidexFootnote)
        .foregroundColor(.tidexTextSecondary)
        .padding(.horizontal, Spacing.sm)
    }
  }
}

extension TidexSettingsSection where Footer == EmptyView {
  init(
    title: String? = nil,
    titleColor: Color = .tidexTextSecondary,
    contentPadding: CGFloat = Spacing.md,
    @ViewBuilder content: () -> Content
  ) {
    self.init(
      title: title,
      titleColor: titleColor,
      contentPadding: contentPadding,
      footer: { EmptyView() },
      content: content
    )
  }
}

struct TidexSettingsDivider: View {
  var leadingPadding: CGFloat = 0

  var body: some View {
    Divider()
      .background(Color.tidexSeparator)
      .padding(.leading, leadingPadding)
      .padding(.vertical, Spacing.sm)
  }
}

struct TidexSettingsIcon: View {
  static let defaultSize: CGFloat = 40

  let systemName: String
  var foregroundColor: Color = .tidexTextSecondary
  var backgroundColor: Color?  // swiftlint:disable:this explicit_acl
  var size: CGFloat = TidexSettingsIcon.defaultSize
  private var glyphBoxSize: CGFloat { size * 0.48 }

  var body: some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .foregroundColor(foregroundColor)
      .frame(width: glyphBoxSize, height: glyphBoxSize)
      .frame(width: size, height: size)
      .background(
        RoundedRectangle(cornerRadius: CornerRadius.md, style: .continuous)
          .fill(backgroundColor ?? Color.tidexSurfaceSecondary)
      )
      .accessibilityHidden(true)
  }
}
