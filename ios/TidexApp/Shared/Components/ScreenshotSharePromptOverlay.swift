import SwiftUI

/// Overlay that prompts users to use the native share button instead of screenshots
/// Slides up from the bottom when a screenshot is detected in the shifts tab
struct ScreenshotSharePromptOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let onDismiss: () -> Void
  let onUseShareButton: () -> Void

  @State private var dragOffset: CGFloat = 0
  @State private var showContent = false

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

        // Overlay card
        VStack(spacing: 0) {
          // Drag indicator
          Capsule()
            .fill(Color.tidexTextMuted.opacity(0.4))
            .frame(width: 36, height: 5)
            .padding(.top, 10)
            .padding(.bottom, Spacing.md)

          // Toolbar buttons preview - showing where share button is
          toolbarPreview
            .padding(.bottom, Spacing.md)

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
          HStack(spacing: Spacing.sm) {
            // Dismiss button - secondary action
            Button {
              dismiss()
            } label: {
              Text(.screenshotShareDismiss)
                .font(.tidexBodyMedium)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tidexSurfacePrimary)
                .foregroundColor(.tidexTextPrimary)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PromptButtonStyle())

            // Use share button - primary action
            Button {
              UIImpactFeedbackGenerator(style: .medium).impactOccurred()
              dismiss()
              // Small delay to let the overlay dismiss first
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                onUseShareButton()
              }
            } label: {
              Text(.screenshotShareUseButton)
                .font(.tidexHeadline)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.tidexBrandPrimary)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(PromptButtonStyle())
          }
          .padding(.horizontal, Spacing.md)
          .padding(.bottom, safeBottom + 16)
        }
        .frame(maxWidth: .infinity)
        .background(
          Color.tidexBackground
            .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
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
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                  dragOffset = 0
                }
              }
            }
        )
      }
      .ignoresSafeArea(edges: .bottom)
    }
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

  // MARK: - Toolbar Preview

  /// Shows the toolbar buttons with emphasis on the share button
  @ViewBuilder
  private var toolbarPreview: some View {
    HStack(spacing: Spacing.md) {
      // Share button - emphasized with liquid glass
      VStack(spacing: 6) {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 20, weight: .medium))
          .foregroundColor(.tidexBlue)
          .frame(width: 48, height: 48)
          .tidexGlass(shape: .circle, interactive: true)

        // Pointer arrow
        Image(systemName: "arrowtriangle.up.fill")
          .font(.system(size: 10))
          .foregroundColor(.tidexBlue)
      }

      // Selection button - dimmed with liquid glass
      Image(systemName: "checkmark.circle")
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.tidexTextMuted)
        .frame(width: 40, height: 40)
        .tidexGlass(shape: .circle)
        .opacity(0.5)
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
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
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
