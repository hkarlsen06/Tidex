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

    var backgroundColor: Color {
      switch self {
      case .primary:
        return .tidexBlue
      case .secondary:
        return .tidexSurfacePrimary
      case .destructive:
        return .tidexError
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
        }

        Text(title)
          .font(.tidexLabelStrong)
      }
      .foregroundColor(style.foregroundColor)
      .frame(maxWidth: .infinity)
      .padding(.vertical, Spacing.sm)
      .background(style.backgroundColor)
      .cornerRadius(CornerRadius.lg)
    }
    .buttonStyle(.plain)
  }
}
