import SwiftUI

/// Main signup screen view with native iOS styling
/// Supports email/password, Google, and Apple sign-up
struct SignupView: View {
  @ObservedObject var viewModel: SignupViewModel
  var onNavigateToLogin: (() -> Void)?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hasPlayedEntrance = false

  private enum ScrollTarget {
    case bottom
  }

  init(
    viewModel: SignupViewModel,
    onNavigateToLogin: (() -> Void)? = nil
  ) {
    self.viewModel = viewModel
    self.onNavigateToLogin = onNavigateToLogin
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        Color.tidexBackground
          .ignoresSafeArea()

        ScrollViewReader { scrollProxy in
          ScrollView {
            VStack(spacing: 0) {
              Spacer(minLength: Spacing.xxl)

              VStack(spacing: Spacing.xl) {
                AuthHeroVisual(
                  logoSize: 132,
                  onLogoTap: restartOnboarding
                )
                .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.00)

                messageStack
                  .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.035)

                inputStepContent(scrollProxy: scrollProxy)
                  .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.07)

                footerView
                  .signupEntranceStep(isVisible: hasPlayedEntrance, delay: 0.105)
              }
              .frame(maxWidth: 420)
              .padding(.horizontal, Spacing.xl)
              .padding(.bottom, max(geometry.safeAreaInsets.bottom + Spacing.sm, Spacing.xxl))
              .frame(maxWidth: .infinity)

              Color.clear
                .frame(height: 0)
                .id(ScrollTarget.bottom)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: geometry.size.height)
          }
          .scrollBounceBehavior(.basedOnSize)
          .scrollDisabled(!viewModel.showEmailForm)
        }
      }
    }
    .loading(viewModel.isLoading)
    .onTapGesture {
      UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    .onAppear {
      viewModel.onNavigateToLogin = onNavigateToLogin
      runEntranceAnimationIfNeeded()
    }
  }

  // MARK: - Header Section

  private var restartOnboarding: () -> Void {
    {
      NotificationCenter.default.post(name: .restartPreAuthOnboarding, object: nil)
    }
  }

  private func runEntranceAnimationIfNeeded() {
    guard !hasPlayedEntrance else { return }
    guard !reduceMotion else {
      hasPlayedEntrance = true
      return
    }

    DispatchQueue.main.async {
      hasPlayedEntrance = true
    }
  }

  @ViewBuilder
  private var messageStack: some View {
    VStack(spacing: Spacing.sm) {
      if let error = viewModel.errorMessage {
        ErrorBanner(
          message: error,
          onDismiss: { viewModel.errorMessage = nil }
        )
      }
    }
  }

  // MARK: - Input Step Content

  @ViewBuilder
  private func inputStepContent(scrollProxy: ScrollViewProxy) -> some View {
    VStack(spacing: Spacing.md) {
      OAuthButtonsView(
        onGoogleTap: { Task { await viewModel.signUpWithGoogle() } },
        onAppleTap: { Task { await viewModel.signUpWithApple() } },
        isLoading: viewModel.isLoading
      )

      dividerView
        .padding(.vertical, Spacing.xs)

      if viewModel.showEmailForm {
        SignupForm(viewModel: viewModel)
      } else {
        revealEmailButton(scrollProxy: scrollProxy)
      }
    }
  }

  // MARK: - Reveal Email Button

  private func revealEmailButton(scrollProxy: ScrollViewProxy) -> some View {
    Button {
      withAnimation(.easeInOut(duration: 0.2)) {
        viewModel.showEmailForm = true
      }
      DispatchQueue.main.async {
        withAnimation(.easeInOut(duration: 0.2)) {
          scrollProxy.scrollTo(ScrollTarget.bottom, anchor: .bottom)
        }
      }
    } label: {
      HStack(spacing: Spacing.xs) {
        Image(systemName: "envelope")
          .font(.tidexBody)
        Text(.signupEmailReveal)
          .font(.tidexBodyMedium)
      }
      .foregroundColor(.tidexTextSecondary)
      .frame(maxWidth: .infinity)
      .frame(height: 50)
      .background(Color.tidexSurfaceSecondary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
    }
    .buttonStyle(SnappyButtonStyle())
  }

  // MARK: - Divider

  private var dividerView: some View {
    HStack(spacing: Spacing.md) {
      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.9))
        .frame(height: 1)

      Text(.loginSeparator)
        .font(.tidexSubheadline)
        .foregroundColor(.tidexTextMuted)

      Rectangle()
        .fill(Color.tidexBorderSubtle.opacity(0.9))
        .frame(height: 1)
    }
  }

  // MARK: - Footer

  private var footerView: some View {
    Button(action: {
      onNavigateToLogin?()
    }) {
      Text(.signupLogin)
        .font(.tidexLabelStrong)
        .foregroundColor(.tidexBlue)
        .lineLimit(1)
        .minimumScaleFactor(0.86)
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

private struct SignupEntranceStepModifier: ViewModifier {
  let isVisible: Bool
  let delay: TimeInterval

  func body(content: Content) -> some View {
    content
      .opacity(isVisible ? 1 : 0)
      .offset(y: isVisible ? 0 : 22)
      .animation(
        .spring(response: 0.30, dampingFraction: 0.86).delay(delay),
        value: isVisible
      )
  }
}

extension View {
  fileprivate func signupEntranceStep(isVisible: Bool, delay: TimeInterval) -> some View {
    modifier(SignupEntranceStepModifier(isVisible: isVisible, delay: delay))
  }
}

// MARK: - Signup Form

/// Email, password, and name form for signup with native iOS styling
struct SignupForm: View {
  @ObservedObject var viewModel: SignupViewModel

  var body: some View {
    VStack(spacing: Spacing.md) {
      HStack(spacing: Spacing.sm) {
        VStack(spacing: 0) {
          TextField(String(localized: .signupFirstNamePlaceholder), text: $viewModel.firstName)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.msm)
        }
        .background(Color.tidexSurfacePrimary)
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

        VStack(spacing: 0) {
          TextField(String(localized: .signupLastNamePlaceholder), text: $viewModel.lastName)
            .font(.tidexBody)
            .foregroundColor(.tidexTextPrimary)
            .textContentType(.familyName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.msm)
        }
        .background(Color.tidexSurfacePrimary)
        .overlay(
          RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
            .stroke(Color.tidexBorderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
      }

      if let firstNameError = viewModel.fieldErrors.firstName {
        Text(firstNameError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      if let lastNameError = viewModel.fieldErrors.lastName {
        Text(lastNameError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      VStack(spacing: 0) {
        NativeTextField(
          placeholder: String(localized: .signupEmailPlaceholder),
          text: $viewModel.emailOrPhone,
          keyboardType: .emailAddress,
          textContentType: .emailAddress
        )

        Divider()
          .background(Color.tidexBorderSubtle)

        NativeSecureField(
          placeholder: String(localized: .signupPasswordPlaceholder),
          text: $viewModel.password,
          onSubmit: {
            Task { await viewModel.signUp() }
          }
        )
      }
      .background(Color.tidexSurfacePrimary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous)
          .stroke(Color.tidexBorderSubtle, lineWidth: 1)
      )
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))

      if let emailError = viewModel.fieldErrors.emailOrPhone {
        Text(emailError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      if let passwordError = viewModel.fieldErrors.password {
        Text(passwordError)
          .font(.tidexFootnote)
          .foregroundColor(.tidexError)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Spacing.xxs)
      }

      PrimaryButton(
        title: String(localized: .signupSubmitButton),
        action: {
          Task { await viewModel.signUp() }
        },
        isLoading: viewModel.isLoading
      )
    }
  }
}

#Preview {
  SignupView(viewModel: SignupViewModel())
}
