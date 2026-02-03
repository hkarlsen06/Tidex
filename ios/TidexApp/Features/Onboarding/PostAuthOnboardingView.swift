import SwiftUI
import Supabase
import AuthenticationServices
import CoreImage.CIFilterBuiltins

/// Post-auth onboarding flow container
/// Collects wage, supplements, settings, and optionally MFA setup
/// Creates a baseline wage snapshot before transitioning to the app
struct PostAuthOnboardingView: View {
    let onComplete: () -> Void
    let userId: String

        @State private var currentScreen: PostAuthScreen = .loading
    @State private var onboardingData = OnboardingData()
    @StateObject private var saveManager = OnboardingSaveManager()
    @State private var showingMFAEnrollment = false
    @State private var isNavigatingBack = false
    @State private var hasCheckedUserName = false
    @Environment(\.scenePhase) private var scenePhase

    enum PostAuthScreen: String {
        case loading
        case profileSetup
        case wage
        case supplements
        case settingsAccordion
        case mfaSetup
        case success
    }

    var body: some View {
        ZStack {
            // Background
            Color.tidexBackground
                .ignoresSafeArea()

            // Current screen with transition
            Group {
                switch currentScreen {
                case .loading:
                    // Brief loading state while checking user name
                    Color.tidexBackground
                        .ignoresSafeArea()

                case .profileSetup:
                    ProfileSetupScreen(
                        data: onboardingData,
                        onContinue: {
                            navigateTo(.wage)
                        }
                    )
                    .transition(screenTransition)

                case .wage:
                    WageScreen(
                        data: onboardingData,
                        onContinue: {
                            navigateFromWage()
                        },
                        onBack: onboardingData.initiallyHadName ? nil : {
                            navigateBack(to: .profileSetup)
                        }
                    )
                    .transition(screenTransition)

                case .supplements:
                    SupplementsScreen(
                        data: onboardingData,
                        onContinue: {
                            navigateTo(.settingsAccordion)
                        },
                        onSkip: {
                            navigateTo(.settingsAccordion)
                        },
                        onBack: {
                            navigateBack(to: .wage)
                        }
                    )
                    .transition(screenTransition)

                case .settingsAccordion:
                    SettingsAccordionScreen(
                        data: onboardingData,
                        onContinue: {
                            navigateTo(.mfaSetup)
                        },
                        onBack: {
                            navigateBackFromSettings()
                        }
                    )
                    .transition(screenTransition)

                case .mfaSetup:
                    MFASetupScreen(
                        onSetupMFA: {
                            showingMFAEnrollment = true
                        },
                        onSkip: {
                            startSaveAndNavigateToSuccess()
                        },
                        onBack: {
                            navigateBack(to: .settingsAccordion)
                        }
                    )
                    .transition(screenTransition)

                case .success:
                    SuccessScreen(
                        saveStatus: saveManager.status,
                        errorMessage: saveManager.errorMessage,
                        onComplete: {
                            // Clear saved onboarding draft data on successful completion
                            OnboardingData.clearSavedData()
                            onComplete()
                        },
                        onRetry: {
                            Task {
                                await saveManager.retry(userId: userId, data: onboardingData)
                            }
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: currentScreen)
        .sheet(isPresented: $showingMFAEnrollment) {
            MFAEnrollmentSheet(
                onComplete: {
                    showingMFAEnrollment = false
                    startSaveAndNavigateToSuccess()
                },
                onCancel: {
                    showingMFAEnrollment = false
                }
            )
        }
        .task {
            await initializeOnboarding()
        }
        .onChange(of: currentScreen) { _, newScreen in
            // Save progress when screen changes (except success and loading screens)
            if newScreen != .success && newScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Save when app goes to background
            if newPhase == .inactive || newPhase == .background {
                if currentScreen != .success && currentScreen != .loading {
                    saveProgress()
                }
            }
        }
        // Save when key data changes within screens
        .onChange(of: onboardingData.supplementRules.count) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.wageType) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.customHourlyWage) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.selectedTariffLevel) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.breakEnabled) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.taxEnabled) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.taxPercentage) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.payrollDay) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.currency) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
        .onChange(of: onboardingData.displayName) { _, _ in
            if currentScreen != .success && currentScreen != .loading {
                saveProgress()
            }
        }
    }

    // MARK: - Initialization

    /// Initialize onboarding by checking if user has a name and restoring progress
    private func initializeOnboarding() async {
        guard !hasCheckedUserName else { return }
        hasCheckedUserName = true

        // First, try to restore saved progress
        if let savedScreenName = onboardingData.restore(),
           let savedScreen = PostAuthScreen(rawValue: savedScreenName),
           savedScreen != .success && savedScreen != .loading {
            // Restore to the saved screen
            currentScreen = savedScreen
            return
        }

        // No saved progress - check if user has a name
        do {
            let user = try await supabase.auth.user()
            let fullName = user.userMetadata["full_name"]?.value as? String
            let name = user.userMetadata["name"]?.value as? String

            let hasName = !(fullName ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          !(name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            onboardingData.initiallyHadName = hasName

            if hasName {
                // User has a name, skip profile setup
                onboardingData.displayName = fullName ?? name ?? ""
                currentScreen = .wage
            } else {
                // User doesn't have a name, show profile setup
                currentScreen = .profileSetup
            }
        } catch {
            // On error, skip profile setup and go to wage
            onboardingData.initiallyHadName = true
            currentScreen = .wage
        }
    }

    // MARK: - Persistence

    private func saveProgress() {
        onboardingData.save(currentScreen: currentScreen.rawValue)
    }

    // MARK: - Navigation

    private var screenTransition: AnyTransition {
        if isNavigatingBack {
            // Back: new screen slides in from left, old screen slides out to right
            return .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        } else {
            // Forward: new screen slides in from right, old screen slides out to left
            return .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        }
    }

    private func navigateFromWage() {
        // Only show supplements screen for custom wage users
        switch onboardingData.wageType {
        case .tariff:
            navigateTo(.settingsAccordion)
        case .custom:
            navigateTo(.supplements)
        }
    }

    private func navigateTo(_ screen: PostAuthScreen) {
        isNavigatingBack = false
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentScreen = screen
        }
    }

    private func navigateBack(to screen: PostAuthScreen) {
        isNavigatingBack = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            currentScreen = screen
        }
    }

    private func navigateBackFromSettings() {
        // Go back to supplements for custom wage, otherwise to wage
        switch onboardingData.wageType {
        case .custom:
            navigateBack(to: .supplements)
        case .tariff:
            navigateBack(to: .wage)
        }
    }

    private func startSaveAndNavigateToSuccess() {
        // Navigate to success screen first
        navigateTo(.success)

        // Start saving in the background
        Task {
            await saveManager.saveOnboardingData(userId: userId, data: onboardingData)
        }
    }
}

// MARK: - MFA Enrollment Sheet

/// Sheet for MFA enrollment using Supabase MFA APIs
private struct MFAEnrollmentSheet: View {
    let onComplete: () -> Void
    let onCancel: () -> Void

        @State private var isEnrolling = false
    @State private var totpUri: String?
    @State private var secret: String?
    @State private var factorId: String?
    @State private var verificationCode = ""
    @State private var errorMessage: String?
    @State private var showingAddToPasswordsSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.tidexBackground
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    if isEnrolling {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(.onboardingMfaEnrolling)
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextSecondary)
                    } else if totpUri != nil {
                        // Show QR code and verification input
                        mfaVerificationView()
                    } else {
                        // Waiting state before auto-start
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text(.onboardingMfaEnrolling)
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextSecondary)
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundColor(.tidexError)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
            .navigationTitle(String(localized: .onboardingMfaSetupTitle))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: .commonCancel)) {
                        onCancel()
                    }
                }
            }
            .onAppear {
                // Auto-start enrollment when sheet opens
                if !isEnrolling && totpUri == nil {
                    startEnrollment()
                }
            }
        }
    }

    @ViewBuilder
    private func mfaVerificationView() -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Text(.onboardingMfaScanQR)
                    .font(.system(size: 17))
                    .foregroundColor(.tidexTextPrimary)
                    .multilineTextAlignment(.center)

                // QR Code - Generated natively from otpauth:// URI
                if let totpUri = totpUri, let qrImage = generateQRCode(from: totpUri) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 200, height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white)
                        )
                } else {
                    Rectangle()
                        .fill(Color.tidexSurfaceSecondary)
                        .frame(width: 200, height: 200)
                        .overlay(
                            Text(.onboardingMfaQrCodeUnavailable)
                                .font(.system(size: 14))
                                .foregroundColor(.tidexTextMuted)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                // Add to Passwords button
                if let totpUri = totpUri, let secret = secret {
                    Button(action: {
                        addToiCloudKeychain(uri: totpUri, secret: secret)
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 16))
                            Text(.onboardingMfaAddToPasswords)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.tidexBlue)
                        .padding(.horizontal, 16)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.tidexBlue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }

                if let secret = secret {
                    VStack(spacing: 4) {
                        Text(.onboardingMfaManualEntry)
                            .font(.system(size: 13))
                            .foregroundColor(.tidexTextMuted)

                        HStack(spacing: 8) {
                            Text(secret)
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                                .foregroundColor(.tidexTextSecondary)

                            Button(action: {
                                UIPasteboard.general.string = secret
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 14))
                                    .foregroundColor(.tidexBlue)
                            }
                        }
                        .padding(8)
                        .background(Color.tidexSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }

                VStack(spacing: 8) {
                    Text(.onboardingMfaEnterCode)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.tidexTextSecondary)

                    TextField("000000", text: $verificationCode)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .frame(width: 160)
                        .padding(12)
                        .background(Color.tidexSurfaceSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                Button(action: verifyCode) {
                    Text(.onboardingMfaVerify)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(verificationCode.count == 6 ? Color.tidexBrandPrimary : Color.tidexBrandPrimary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(verificationCode.count != 6)
                .padding(.horizontal, 24)
            }
            .padding(24)
        }
    }

    /// Generate QR code from a string using CoreImage
    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        guard let data = string.data(using: .utf8) else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel") // High error correction

        guard let ciImage = filter.outputImage else { return nil }

        // Scale up the QR code for better quality
        let scale = 10.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
        let scaledImage = ciImage.transformed(by: transform)

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Add TOTP to iCloud Keychain / iOS Password Manager
    private func addToiCloudKeychain(uri: String, secret: String) {
        // Open the otpauth:// URI which will trigger iOS to offer adding it to Passwords
        // This works on iOS 15+ and uses the native password manager integration
        if let url = URL(string: uri) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
    }

    private func startEnrollment() {
        isEnrolling = true
        errorMessage = nil

        Task {
            do {
                let response = try await supabase.auth.mfa.enroll(
                    params: .totp(issuer: "Tidex", friendlyName: "Tidex 2FA")
                )
                factorId = response.id
                totpUri = response.totp?.uri  // Use URI for native QR generation
                secret = response.totp?.secret
                isEnrolling = false
            } catch {
                errorMessage = error.localizedDescription
                isEnrolling = false
            }
        }
    }

    private func verifyCode() {
        guard let factorId = factorId else { return }

        isEnrolling = true
        errorMessage = nil

        Task {
            do {
                // Challenge and verify in one step
                try await supabase.auth.mfa.challengeAndVerify(
                    params: MFAChallengeAndVerifyParams(
                        factorId: factorId,
                        code: verificationCode
                    )
                )

                isEnrolling = false
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
                isEnrolling = false
            }
        }
    }
}

#Preview {
    PostAuthOnboardingView(
        onComplete: {},
        userId: "test-user-id"
    )
}
