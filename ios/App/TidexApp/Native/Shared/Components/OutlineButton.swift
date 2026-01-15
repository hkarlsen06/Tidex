import SwiftUI
import UIKit

/// Secondary/outline button with Tidex styling
/// Used for secondary actions and expandable options
struct OutlineButton: View {
    let title: String
    let action: () -> Void
    var icon: String? = nil
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextSecondary))
                        .scaleEffect(0.8)
                } else if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .foregroundColor(.tidexTextSecondary)
            .background(Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.tidexBorder, lineWidth: 1)
            )
        }
        .buttonStyle(SnappyOutlineButtonStyle())
        .disabled(isDisabled || isLoading)
        .opacity(isDisabled ? 0.5 : 1)
    }
}

/// Snappy button style for outline buttons
private struct SnappyOutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

#Preview {
    VStack(spacing: 16) {
        OutlineButton(title: "Log in with email or phone", action: {})

        OutlineButton(title: "With Icon", action: {}, icon: "envelope")

        OutlineButton(title: "Loading", action: {}, isLoading: true)
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
