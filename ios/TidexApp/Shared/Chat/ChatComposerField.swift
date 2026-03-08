import SwiftUI

struct ChatComposerField<LeadingAccessory: View>: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private let composerControlHeight: CGFloat = 50

  @Binding private var text: String
  private let placeholder: String
  private let disabled: Bool
  private let isSending: Bool
  private let canSend: Bool
  private let sendAccessibilityLabel: String
  private let horizontalPadding: CGFloat
  private let topPadding: CGFloat
  private let bottomPadding: CGFloat
  private let onSend: () -> Void
  private let leadingAccessory: LeadingAccessory

  @FocusState private var isFocused: Bool

  init(
    text: Binding<String>,
    placeholder: String,
    disabled: Bool,
    isSending: Bool = false,
    canSend: Bool,
    sendAccessibilityLabel: String,
    horizontalPadding: CGFloat = Spacing.md,
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
    self.horizontalPadding = horizontalPadding
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
    .padding(.horizontal, horizontalPadding)
    .padding(.top, topPadding)
    .padding(.bottom, bottomPadding)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: canSend)
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: isFocused)
  }

  private var composerField: some View {
    HStack(alignment: .center, spacing: Spacing.xs) {
      TextField(
        placeholder,
        text: $text,
        axis: .vertical
      )
      .textFieldStyle(.plain)
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .lineLimit(1...5)
      .focused($isFocused)
      .disabled(disabled)
      .submitLabel(.return)
      .onSubmit {
        onSend()
      }
      .padding(.vertical, Spacing.xxs)

      sendButton
    }
    .padding(.horizontal, Spacing.msm)
    .padding(.vertical, Spacing.xs)
    .frame(minHeight: composerControlHeight)
    .tidexGlass(
      shape: .rect(cornerRadius: 24),
      tint: composerTint,
      interactive: isFocused,
      disabled: disabled,
      fallbackOpacity: 0.9
    )
    .overlay(composerBorder)
    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    RoundedRectangle(cornerRadius: 24, style: .continuous)
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
    horizontalPadding: CGFloat = Spacing.md,
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
      horizontalPadding: horizontalPadding,
      topPadding: topPadding,
      bottomPadding: bottomPadding,
      onSend: onSend
    ) {
      EmptyView()
    }
  }
}
