import SwiftUI
import UIKit

// MARK: - Adaptive Layout Constants

/// Standard max widths for different content types
/// These ensure content doesn't stretch too wide on iPad landscape
enum AdaptiveMaxWidth {
    /// Max width for form content (login, signup, etc.)
    static let form: CGFloat = 480

    /// Max width for onboarding content screens
    static let content: CGFloat = 560

    /// Max width for full-width onboarding containers
    static let onboarding: CGFloat = 600

    /// Max width for card-based layouts
    static let card: CGFloat = 520
}

// MARK: - View Modifier for Adaptive Max Width

/// Constrains content to a max width and centers it horizontally
/// Ideal for iPad landscape where full-width forms look stretched
struct AdaptiveMaxWidthModifier: ViewModifier {
    let maxWidth: CGFloat
    let alignment: Alignment

    func body(content: Content) -> some View {
        GeometryReader { geometry in
            let effectiveMaxWidth = min(maxWidth, geometry.size.width)
            content
                .frame(maxWidth: effectiveMaxWidth)
                .frame(maxWidth: .infinity, alignment: alignment)
        }
    }
}

/// Constrains content width with proper centering (non-GeometryReader version)
/// Simpler approach that works well for most cases
struct SimpleAdaptiveModifier: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}

// MARK: - View Extensions

extension View {
    /// Constrains the view to a max width, centering it on larger screens
    /// Use for auth forms, onboarding content, etc.
    ///
    /// - Parameters:
    ///   - maxWidth: Maximum width for the content (default: form width)
    ///   - alignment: Horizontal alignment when constrained (default: center)
    func adaptiveMaxWidth(
        _ maxWidth: CGFloat = AdaptiveMaxWidth.form,
        alignment: Alignment = .center
    ) -> some View {
        modifier(SimpleAdaptiveModifier(maxWidth: maxWidth))
    }

    /// Constrains the view to form-appropriate width for iPad
    /// Best for login, signup, password reset forms
    func adaptiveFormWidth() -> some View {
        adaptiveMaxWidth(AdaptiveMaxWidth.form)
    }

    /// Constrains the view to content-appropriate width for iPad
    /// Best for onboarding screens with mixed content
    func adaptiveContentWidth() -> some View {
        adaptiveMaxWidth(AdaptiveMaxWidth.content)
    }

    /// Constrains the view to card-appropriate width for iPad
    /// Best for card-based layouts in auth flows
    func adaptiveCardWidth() -> some View {
        adaptiveMaxWidth(AdaptiveMaxWidth.card)
    }
}

// MARK: - Horizontal Size Class Helper

/// View modifier that provides size class information
struct SizeClassReader: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let action: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onAppear {
                action(horizontalSizeClass == .regular)
            }
            .onChange(of: horizontalSizeClass) { _, newValue in
                action(newValue == .regular)
            }
    }
}

extension View {
    /// Executes a closure with the current regular width state
    /// Use this instead of the deprecated UIScreen.main approach
    func onSizeClass(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(SizeClassReader(action: action))
    }
}

// MARK: - Preview

#Preview("Adaptive Width Demo") {
    VStack(spacing: 20) {
        Text("Form Width (480pt)")
            .padding()
            .background(Color.blue.opacity(0.2))
            .adaptiveFormWidth()

        Text("Content Width (560pt)")
            .padding()
            .background(Color.green.opacity(0.2))
            .adaptiveContentWidth()

        Text("Card Width (520pt)")
            .padding()
            .background(Color.orange.opacity(0.2))
            .adaptiveCardWidth()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.gray.opacity(0.1))
}
