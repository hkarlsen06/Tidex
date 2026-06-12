import SwiftUI

struct DetailSheetActionButton: View {
  enum Style {
    case primary
    case secondary
    case destructive

    var role: ButtonRole? {
      switch self {
      case .destructive:
        return .destructive

      case .primary, .secondary:
        return nil
      }
    }

    var foregroundColor: Color {
      switch self {
      case .primary:
        return .tidexTextOnBrand

      case .secondary:
        return .tidexBlue

      case .destructive:
        return .tidexTextOnDanger
      }
    }

    internal var iconForegroundColor: Color {
      switch self {
      case .secondary:
        return .tidexTextPrimary

      case .primary, .destructive:
        return foregroundColor
      }
    }

    var backgroundColor: Color {
      switch self {
      case .primary:
        return .tidexBlue

      case .secondary:
        return .tidexBlue.opacity(0.08)

      case .destructive:
        return .tidexError
      }
    }

    var borderColor: Color {
      switch self {
      case .secondary:
        return .tidexBlue.opacity(0.14)

      case .primary, .destructive:
        return .clear
      }
    }
  }

  let title: String
  let systemImage: String?
  let style: Style
  let action: () -> Void

  init(
    title: String,
    systemImage: String? = nil,
    style: Style,
    action: @escaping () -> Void
  ) {
    self.title = title
    self.systemImage = systemImage
    self.style = style
    self.action = action
  }

  var body: some View {
    Button(role: style.role, action: action) {
      HStack(spacing: Spacing.xs) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(.tidexLabel)
            .foregroundColor(style.iconForegroundColor)
        }

        Text(title)
          .font(.tidexLabelStrong)
          .foregroundColor(style.foregroundColor)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
          .minimumScaleFactor(0.86)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(style.backgroundColor)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg)
          .stroke(style.borderColor, lineWidth: 1)
      )
      .cornerRadius(CornerRadius.lg)
    }
    .buttonStyle(.plain)
  }
}
