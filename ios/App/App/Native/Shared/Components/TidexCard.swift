import SwiftUI

/// Card container with Tidex styling
/// Used to wrap form content and sections
struct TidexCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .background(Color.tidexSurfacePrimary)
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.tidexBorderSubtle, lineWidth: 1)
            )
    }
}

#Preview {
    TidexCard {
        VStack(spacing: 16) {
            Text("Card Title")
                .font(.headline)
                .foregroundColor(.tidexTextPrimary)

            Text("Card content goes here")
                .foregroundColor(.tidexTextSecondary)
        }
        .padding(24)
    }
    .padding()
    .background(Color.tidexDarkBackground)
}
