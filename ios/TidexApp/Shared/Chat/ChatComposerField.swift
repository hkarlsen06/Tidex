import SwiftUI

struct ChatComposerField<LeadingAccessory: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme

  private let composerControlHeight: CGFloat = 56

  @Binding private var text: String
  private let placeholder: String
  private let disabled: Bool
  private let isSending: Bool
  private let canPerformAction: Bool
  private let actionAccessibilityLabel: String
  private let actionSystemImage: String
  private let actionForegroundColor: Color
  private let actionBackgroundColor: Color
  private let textFieldAccessibilityIdentifier: String?
  private let actionButtonAccessibilityIdentifier: String?
  private let submitLabel: SubmitLabel
  private let triggersSubmit: Bool
  private let focusTrigger: Int
  private let onFocusChanged: ((Bool) -> Void)?
  private let horizontalPadding: CGFloat
  private let focusedHorizontalPadding: CGFloat?
  private let topPadding: CGFloat
  private let bottomPadding: CGFloat
  private let onAction: () -> Void
  private let leadingAccessory: LeadingAccessory
  private let composerCornerRadius: CGFloat = 24

  @FocusState private var isFocused: Bool

  init(
    text: Binding<String>,
    placeholder: String,
    disabled: Bool,
    isSending: Bool = false,
    canPerformAction: Bool,
    actionAccessibilityLabel: String,
    actionSystemImage: String = "arrow.up",
    actionForegroundColor: Color = .tidexTextOnBrand,
    actionBackgroundColor: Color = .tidexBrandPrimary,
    textFieldAccessibilityIdentifier: String? = nil,
    actionButtonAccessibilityIdentifier: String? = nil,
    submitLabel: SubmitLabel = .send,
    triggersSubmit: Bool = true,
    focusTrigger: Int = 0,
    onFocusChanged: ((Bool) -> Void)? = nil,
    horizontalPadding: CGFloat = Spacing.md,
    focusedHorizontalPadding: CGFloat? = nil,
    topPadding: CGFloat = Spacing.xs,
    bottomPadding: CGFloat = Spacing.md,
    onAction: @escaping () -> Void,
    @ViewBuilder leadingAccessory: () -> LeadingAccessory
  ) {
    _text = text
    self.placeholder = placeholder
    self.disabled = disabled
    self.isSending = isSending
    self.canPerformAction = canPerformAction
    self.actionAccessibilityLabel = actionAccessibilityLabel
    self.actionSystemImage = actionSystemImage
    self.actionForegroundColor = actionForegroundColor
    self.actionBackgroundColor = actionBackgroundColor
    self.textFieldAccessibilityIdentifier = textFieldAccessibilityIdentifier
    self.actionButtonAccessibilityIdentifier = actionButtonAccessibilityIdentifier
    self.submitLabel = submitLabel
    self.triggersSubmit = triggersSubmit
    self.focusTrigger = focusTrigger
    self.onFocusChanged = onFocusChanged
    self.horizontalPadding = horizontalPadding
    self.focusedHorizontalPadding = focusedHorizontalPadding
    self.topPadding = topPadding
    self.bottomPadding = bottomPadding
    self.onAction = onAction
    self.leadingAccessory = leadingAccessory()
  }

  var body: some View {
    HStack(alignment: .center, spacing: Spacing.xsm) {
      leadingAccessory
      composerField
    }
    .padding(.horizontal, effectiveHorizontalPadding)
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canPerformAction)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isFocused)
    .onChange(of: focusTrigger) { _, _ in
      guard !disabled else { return }
      isFocused = true
    }
    .onChange(of: isFocused) { _, newValue in
      onFocusChanged?(newValue)
    }
  }

  private var effectiveHorizontalPadding: CGFloat {
    guard isFocused, let focusedHorizontalPadding else { return horizontalPadding }
    return focusedHorizontalPadding
  }

  private var composerField: some View {
    HStack(alignment: .bottom, spacing: Spacing.xs) {
      TextField(
        placeholder,
        text: $text,
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1...7)
      .focused($isFocused)
      .disabled(disabled)
      .chatComposerAccessibilityIdentifier(textFieldAccessibilityIdentifier)
      .submitLabel(submitLabel)
      .onSubmit {
        guard triggersSubmit, canPerformAction else { return }
        onAction()
      }
      .padding(.vertical, Spacing.xs)

      sendButton
    }
    .padding(.horizontal, Spacing.msm)
    .padding(.vertical, Spacing.sm)
    .frame(minHeight: composerControlHeight)
    .background(composerSurfaceFill)
    .tidexGlass(
      shape: .rect(cornerRadius: composerCornerRadius),
      tint: composerTint,
      interactive: isFocused,
      disabled: disabled,
      fallbackOpacity: 0.9
    )
    .overlay(composerBorder)
    .clipShape(RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous))
    .onTapGesture {
      guard !disabled else { return }
      isFocused = true
    }
    .shadow(color: Color.tidexBlue.opacity(isFocused ? 0.12 : 0.05), radius: 18, y: 6)
  }

  private var sendButton: some View {
    Button(action: onAction) {
      Group {
        if isSending {
          ProgressView()
            .progressViewStyle(.circular)
            .tint(.tidexTextOnBrand)
        } else {
          Image(systemName: actionSystemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(canPerformAction ? actionForegroundColor : .tidexTextMuted)
        }
      }
      .frame(width: 38, height: 38)
      .background(
        Circle()
          .fill(canPerformAction ? actionBackgroundColor : Color.tidexSurfaceSecondary)
      )
      .contentShape(Circle())
    }
    .disabled(!canPerformAction)
    .accessibilityLabel(Text(actionAccessibilityLabel))
    .chatComposerAccessibilityIdentifier(actionButtonAccessibilityIdentifier)
    .opacity((disabled && !canPerformAction) ? 0.6 : 1)
  }

  private var composerTint: Color {
    if colorScheme == .light {
      return isFocused
        ? Color.tidexSurfacePrimary.opacity(0.96)
        : Color.tidexSurfacePrimary.opacity(0.9)
    }

    if isFocused {
      return Color.tidexBlue.opacity(0.24)
    }

    return Color.tidexBlue.opacity(0.14)
  }

  private var composerSurfaceFill: some View {
    RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous)
      .fill(composerSurfaceColor)
  }

  private var composerSurfaceColor: Color {
    if colorScheme == .light {
      if isFocused {
        return Color.tidexSurfacePrimary.opacity(0.88)
      }

      return Color.tidexSurfacePrimary.opacity(0.8)
    }

    return Color.tidexSurfacePrimary.opacity(0.08)
  }

  private var composerBorder: some View {
    RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous)
      .stroke(
        composerBorderColor,
        lineWidth: 1
      )
  }

  private var composerBorderColor: Color {
    if isFocused {
      if colorScheme == .light {
        return Color.tidexBlue.opacity(0.52)
      }

      return Color.tidexBlue.opacity(0.4)
    }

    if colorScheme == .light {
      return Color.tidexBorder.opacity(0.72)
    }

    return Color.tidexBorder.opacity(0.38)
  }
}

extension View {
  @ViewBuilder
  fileprivate func chatComposerAccessibilityIdentifier(_ identifier: String?) -> some View {
    if let identifier {
      accessibilityIdentifier(identifier)
    } else {
      self
    }
  }
}

extension ChatComposerField where LeadingAccessory == EmptyView {
  init(
    text: Binding<String>,
    placeholder: String,
    disabled: Bool,
    isSending: Bool = false,
    canPerformAction: Bool,
    actionAccessibilityLabel: String,
    actionSystemImage: String = "arrow.up",
    actionForegroundColor: Color = .tidexTextOnBrand,
    actionBackgroundColor: Color = .tidexBrandPrimary,
    textFieldAccessibilityIdentifier: String? = nil,
    actionButtonAccessibilityIdentifier: String? = nil,
    submitLabel: SubmitLabel = .send,
    triggersSubmit: Bool = true,
    focusTrigger: Int = 0,
    onFocusChanged: ((Bool) -> Void)? = nil,
    horizontalPadding: CGFloat = Spacing.md,
    focusedHorizontalPadding: CGFloat? = nil,
    topPadding: CGFloat = Spacing.xs,
    bottomPadding: CGFloat = Spacing.md,
    onAction: @escaping () -> Void
  ) {
    self.init(
      text: text,
      placeholder: placeholder,
      disabled: disabled,
      isSending: isSending,
      canPerformAction: canPerformAction,
      actionAccessibilityLabel: actionAccessibilityLabel,
      actionSystemImage: actionSystemImage,
      actionForegroundColor: actionForegroundColor,
      actionBackgroundColor: actionBackgroundColor,
      textFieldAccessibilityIdentifier: textFieldAccessibilityIdentifier,
      actionButtonAccessibilityIdentifier: actionButtonAccessibilityIdentifier,
      submitLabel: submitLabel,
      triggersSubmit: triggersSubmit,
      focusTrigger: focusTrigger,
      onFocusChanged: onFocusChanged,
      horizontalPadding: horizontalPadding,
      focusedHorizontalPadding: focusedHorizontalPadding,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      onAction: onAction
    ) {
      EmptyView()
    }
  }
}
