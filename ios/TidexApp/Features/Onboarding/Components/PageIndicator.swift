import SwiftUI

/// Dot indicators for onboarding page progress
struct PageIndicator: View {
    let totalPages: Int
    let currentPage: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalPages, id: \.self) { index in
                Circle()
                    .fill(index == currentPage ? Color.tidexBlue : Color.tidexTextMuted.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .scaleEffect(index == currentPage ? 1.2 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentPage)
            }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        PageIndicator(totalPages: 4, currentPage: 0)
        PageIndicator(totalPages: 4, currentPage: 1)
        PageIndicator(totalPages: 4, currentPage: 2)
        PageIndicator(totalPages: 4, currentPage: 3)
    }
    .padding()
    .background(Color.tidexBackground)
}
