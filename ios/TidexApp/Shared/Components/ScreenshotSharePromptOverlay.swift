// swiftlint:disable:next blanket_disable_command
// swiftlint:disable line_length superfluous_disable_command
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable accessibility_label_for_image accessibility_trait_for_button closure_body_length explicit_acl
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable explicit_top_level_acl explicit_type_interface file_types_order no_empty_block
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable no_magic_numbers
import SwiftUI

/// Overlay that prompts users to use the native share button instead of screenshots
/// Slides up from the bottom when a screenshot is detected in the shifts tab
struct ScreenshotSharePromptOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  let onDismiss: () -> Void
  let onUseShareButton: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var showContent = false
  @Namespace private var glassNamespace

  var body: some View {
    GeometryReader { geometry in
      let safeBottom = geometry.safeAreaInsets.bottom

      ZStack(alignment: .bottom) {
        // Dimmed background
        Color.black
          .opacity(showContent ? 0.35 : 0)
          .ignoresSafeArea()
          .onTapGesture {
            dismiss()
          }
          .accessibilityHidden(true)

        // Overlay card
        VStack(spacing: 0) {
          // Drag indicator
          Capsule()
            .fill(Color.tidexTextMuted.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, Spacing.xsm)
            .padding(.bottom, Spacing.md)

          // Toolbar buttons preview - showing where share button is
          toolbarPreview
            .padding(.bottom, Spacing.md)
            .accessibilityHidden(true)

          // Title
          Text(.screenshotShareTitle)
            .font(.tidexTitle2)
            .foregroundColor(.tidexTextPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Spacing.mlg)
            .padding(.bottom, Spacing.xs)

          // Description
          Text(.screenshotShareDescription)
            .font(.tidexBody)
            .foregroundColor(.tidexTextSecondary)
            .multilineTextAlignment(.center)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.mlg)

          // Side-by-side buttons
          buttonLayout {
            // Dismiss button - secondary action
            Button {
              dismiss()
            } label: {
              Text(.screenshotShareDismiss)
                .font(.tidexBodyMedium)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.tidexSurfacePrimary)
                .foregroundColor(.tidexTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
            }
            .buttonStyle(PromptButtonStyle())

            // Use share button - primary action
            Button {
              Haptics.play(.medium)
              dismiss()
              // Small delay to let the overlay dismiss first
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onUseShareButton()
              }
            } label: {
              Text(.screenshotShareUseButton)
                .font(.tidexHeadline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(Color.tidexBrandPrimary)
                .foregroundColor(.tidexTextOnBrand)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xl, style: .continuous))
            }
            .buttonStyle(PromptButtonStyle())
          }
          .padding(.horizontal, Spacing.md)
          .padding(.bottom, safeBottom + Spacing.md)
        }
        .frame(maxWidth: .infinity)
        .background(
          Color.tidexBackground
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
            .shadow(color: .black.opacity(0.15), radius: 20, y: -5)
        )
        .offset(y: showContent ? dragOffset : geometry.size.height + 100)
        .gesture(
          DragGesture()
            .onChanged { value in
              if value.translation.height > 0 {
                dragOffset = value.translation.height
              }
            }
            .onEnded { value in
              if value.translation.height > 80 || value.predictedEndTranslation.height > 200 {
                dismiss()
              } else {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.8)) {
                  dragOffset = 0
                }
              }
            }
        )
      }
      .ignoresSafeArea(edges: .bottom)
    }
    // The prompt covers the screen, so VoiceOver stays inside it and can dismiss it with the escape gesture.
    .accessibilityAddTraits(.isModal)
    .accessibilityAction(.escape) { dismiss() }
    .animation(
      reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: showContent
    )
    .animation(
      reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.85), value: dragOffset
    )
    .onAppear {
      showContent = true
      Haptics.play(.warning)
    }
  }

  /// The two buttons stack at accessibility text sizes so each label keeps the full width.
  private var buttonLayout: AnyLayout {
    dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: Spacing.sm))
      : AnyLayout(HStackLayout(spacing: Spacing.sm))
  }

  // MARK: - Toolbar Preview

  /// Shows the toolbar buttons with emphasis on the share button
  @ViewBuilder
  private var toolbarPreview: some View {
    GlassEffectContainer(spacing: Spacing.md) {
      HStack(spacing: Spacing.md) {
        // Share button - emphasized with liquid glass
        VStack(spacing: Spacing.xxxs) {
          Image(systemName: "square.and.arrow.up")
            .font(.tidexBodyLarge)
            .foregroundColor(.tidexBlueText)
            .frame(width: 48, height: 48)
            .glassEffectID("screenshotPrompt.shareButton", in: glassNamespace)
            .tidexGlass(shape: .circle, interactive: true)

          // Pointer arrow
          Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 10))
            .foregroundColor(.tidexBlueText)
        }

        // Selection button - dimmed with liquid glass
        Image(systemName: "checkmark.circle")
          .font(.tidexHeadline)
          .foregroundColor(.tidexTextMuted)
          .frame(width: 40, height: 40)
          .glassEffectID("screenshotPrompt.selectionButton", in: glassNamespace)
          .tidexGlass(shape: .circle)
          .opacity(0.5)
      }
    }
  }

  private func dismiss() {
    showContent = false
    dragOffset = 0
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      onDismiss()
    }
  }
}

// MARK: - Button Style

private struct PromptButtonStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1.0)
      .opacity(configuration.isPressed ? 0.9 : 1.0)
      .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
  }
}

// MARK: - Preview

#Preview {
  ZStack {
    Color.tidexBackground.ignoresSafeArea()

    ScreenshotSharePromptOverlay(
      onDismiss: {},
      onUseShareButton: {}
    )
  }
}
