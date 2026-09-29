import SwiftUI

/// Screen for naming and coloring the first job created during onboarding.
struct JobBasicsOnboardingScreen: View {
  @Bindable var data: OnboardingData
  let onContinue: () -> Void
  var onBack: (() -> Void)?  // swiftlint:disable:this explicit_acl

  @FocusState private var isJobNameFocused: Bool

  private var trimmedJobName: String {
    data.jobName.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private var canContinue: Bool {
    !trimmedJobName.isEmpty
  }

  private var headerTopSpacing: CGFloat {
    onBack != nil ? Spacing.huge : Spacing.huge + Spacing.huge + Spacing.sm
  }

  var body: some View {
    ZStack {
      Color.tidexBackground
        .ignoresSafeArea()

      VStack(spacing: 0) {
        scrollArea
        continueBar
      }
    }
    .onAppear {
      if data.jobColor == nil {
        data.jobColor = OnboardingData.defaultJobColor
      }
    }
  }

  private var scrollArea: some View {
    GeometryReader { geometry in
      ScrollView {
        VStack(spacing: 0) {
          if let onBack {
            backButton(onBack)
          }

          Spacer()
            .frame(height: headerTopSpacing)

          header

          Spacer(minLength: Spacing.xl)

          form

          Spacer()
            .frame(height: Spacing.md)
        }
        .frame(minHeight: geometry.size.height, alignment: .top)
      }
      .scrollDismissesKeyboard(.interactively)
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: Spacing.sm) {
      Text(.onboardingJobBasicsTitle)
        .font(.tidexScreenTitle)
        .foregroundColor(.tidexTextPrimary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)

      Text(.onboardingJobBasicsSubtitle)
        .font(.tidexBody)
        .foregroundColor(.tidexTextSecondary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, Spacing.xl)
    .adaptiveContentWidth()
  }

  private var form: some View {
    VStack(alignment: .leading, spacing: Spacing.lg) {
      jobNameField

      VStack(alignment: .leading, spacing: Spacing.xs) {
        Text(.settingsPayAddJobColorLabel)
          .font(.tidexLabel)
          .foregroundColor(.tidexTextSecondary)

        WorkplaceColorCarousel(
          selectedHex: data.jobColor ?? OnboardingData.defaultJobColor
        ) { hex in
          data.jobColor = hex
        }
      }
    }
    .padding(.horizontal, Spacing.lg)
    .adaptiveContentWidth()
  }

  private var continueBar: some View {
    VStack(spacing: 0) {
      LinearGradient(
        colors: [Color.tidexBackground.opacity(0), Color.tidexBackground],
        startPoint: .top,
        endPoint: .bottom
      )
      .frame(height: 24)

      OnboardingButton(
        title: String(localized: .commonContinue),
        isEnabled: canContinue,
        action: {
          continueIfReady()
        }
      )
      .padding(.horizontal, Spacing.lg)
      .adaptiveContentWidth()

      Spacer()
        .frame(height: Spacing.xl)
    }
    .background(Color.tidexBackground)
  }

  private func backButton(_ onBack: @escaping () -> Void) -> some View {
    HStack {
      Button(action: {
        Haptics.play(.light)
        onBack()
      }) {
        HStack(spacing: Spacing.xxs) {
          Image(systemName: "chevron.left")
            .font(.tidexButton)
          Text(.commonBack)
            .font(.tidexBody)
        }
        .foregroundColor(.tidexBlue)
      }
      .buttonStyle(.plain)

      Spacer()
    }
    .padding(.horizontal, Spacing.lg)
    .padding(.top, Spacing.md)
    .adaptiveContentWidth()
  }

  private var jobNameField: some View {
    VStack(alignment: .leading, spacing: Spacing.xs) {
      Text(.settingsPayAddJobName)
        .font(.tidexLabel)
        .foregroundColor(.tidexTextSecondary)

      TextField(
        "",
        text: $data.jobName,
        prompt: Text(
          String(localized: .onboardingJobBasicsNamePlaceholder)
        )
        .foregroundColor(.tidexTextMuted.opacity(0.62))
      )
      .font(.tidexBody)
      .foregroundColor(.tidexTextPrimary)
      .textInputAutocapitalization(.words)
      .submitLabel(.done)
      .focused($isJobNameFocused)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .overlay(
        RoundedRectangle(cornerRadius: CornerRadius.md)
          .stroke(Color.tidexBorder, lineWidth: 1)
      )
      .cornerRadius(CornerRadius.md)
      .contentShape(Rectangle())
      .onSubmit {
        isJobNameFocused = false
      }
    }
  }

  private func continueIfReady() {
    guard canContinue else { return }
    data.jobName = trimmedJobName
    Haptics.play(.success)
    onContinue()
  }
}

#Preview {
  JobBasicsOnboardingScreen(
    data: OnboardingData(),
    onContinue: {}
  )
}
