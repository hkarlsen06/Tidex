import SwiftUI

struct ChatComposerField<LeadingAccessory: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let composerControlHeight: CGFloat = 56

  @Binding private var text: String
  private let placeholder: String
  private let disabled: Bool
  private let isSending: Bool
  private let canSend: Bool
  private let sendAccessibilityLabel: String
  private let submitLabel: SubmitLabel
  private let focusTrigger: Int
  private let onFocusChanged: ((Bool) -> Void)?
  private let horizontalPadding: CGFloat
  private let focusedHorizontalPadding: CGFloat?
  private let topPadding: CGFloat
  private let bottomPadding: CGFloat
  private let onSend: () -> Void
  private let leadingAccessory: LeadingAccessory
  private let composerCornerRadius: CGFloat = 24

  @FocusState private var isFocused: Bool

  init(
    text: Binding<String>,
    placeholder: String,
    disabled: Bool,
    isSending: Bool = false,
    canSend: Bool,
    sendAccessibilityLabel: String,
    submitLabel: SubmitLabel = .send,
    focusTrigger: Int = 0,
    onFocusChanged: ((Bool) -> Void)? = nil,
    horizontalPadding: CGFloat = Spacing.md,
    focusedHorizontalPadding: CGFloat? = nil,
    topPadding: CGFloat = Spacing.xs,
    bottomPadding: CGFloat = Spacing.md,
    onSend: @escaping () -> Void,
    @ViewBuilder leadingAccessory: () -> LeadingAccessory
  ) {
    _text = text
    self.placeholder = placeholder
    self.disabled = disabled
    self.isSending = isSending
    self.canSend = canSend
    self.sendAccessibilityLabel = sendAccessibilityLabel
    self.submitLabel = submitLabel
    self.focusTrigger = focusTrigger
    self.onFocusChanged = onFocusChanged
    self.horizontalPadding = horizontalPadding
    self.focusedHorizontalPadding = focusedHorizontalPadding
    self.topPadding = topPadding
    self.bottomPadding = bottomPadding
    self.onSend = onSend
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
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canSend)
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
      .submitLabel(submitLabel)
      .onSubmit {
        guard canSend else { return }
        onSend()
      }
      .padding(.vertical, Spacing.xs)

      sendButton
    }
    .padding(.horizontal, Spacing.msm)
    .padding(.vertical, Spacing.sm)
    .frame(minHeight: composerControlHeight)
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
    Button(action: onSend) {
      Group {
        if isSending {
          ProgressView()
            .progressViewStyle(.circular)
            .tint(.tidexTextOnBrand)
        } else {
          Image(systemName: "arrow.up")
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(canSend ? .tidexTextOnBrand : .tidexTextMuted)
        }
      }
      .frame(width: 38, height: 38)
      .background(
        Circle()
          .fill(canSend ? Color.tidexBrandPrimary : Color.tidexSurfaceSecondary)
      )
      .contentShape(Circle())
    }
    .disabled(!canSend)
    .accessibilityLabel(Text(sendAccessibilityLabel))
    .opacity(disabled ? 0.6 : 1)
  }

  private var composerTint: Color {
    isFocused ? Color.tidexBlue.opacity(0.24) : Color.tidexBlue.opacity(0.14)
  }

  private var composerBorder: some View {
    RoundedRectangle(cornerRadius: composerCornerRadius, style: .continuous)
      .stroke(
        isFocused ? Color.tidexBlue.opacity(0.4) : Color.tidexBorder.opacity(0.38),
        lineWidth: 1
      )
  }
}

extension ChatComposerField where LeadingAccessory == EmptyView {
  init(
    text: Binding<String>,
    placeholder: String,
    disabled: Bool,
    isSending: Bool = false,
    canSend: Bool,
    sendAccessibilityLabel: String,
    submitLabel: SubmitLabel = .send,
    focusTrigger: Int = 0,
    onFocusChanged: ((Bool) -> Void)? = nil,
    horizontalPadding: CGFloat = Spacing.md,
    focusedHorizontalPadding: CGFloat? = nil,
    topPadding: CGFloat = Spacing.xs,
    bottomPadding: CGFloat = Spacing.md,
    onSend: @escaping () -> Void
  ) {
    self.init(
      text: text,
      placeholder: placeholder,
      disabled: disabled,
      isSending: isSending,
      canSend: canSend,
      sendAccessibilityLabel: sendAccessibilityLabel,
      submitLabel: submitLabel,
      focusTrigger: focusTrigger,
      onFocusChanged: onFocusChanged,
      horizontalPadding: horizontalPadding,
      focusedHorizontalPadding: focusedHorizontalPadding,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      onSend: onSend
    ) {
      EmptyView()
    }
  }
}
