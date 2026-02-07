import SwiftUI

/// Banner displayed when an admin is impersonating another user
///
/// Shows the target user's name, session expiration, and a stop button.
/// Should be displayed at the top of the app when impersonation is active.
struct ImpersonationBanner: View {
  let targetName: String
  let expiresAt: Date?
  let onStop: () -> Void

  @State private var isLoading = false

  var body: some View {
    HStack(spacing: Spacing.sm) {
      // Warning icon
      Image(systemName: "person.crop.circle.badge.exclamationmark")
        .font(.system(size: 24))
        .foregroundStyle(Color.tidexWarning)

      // Info text
      VStack(alignment: .leading, spacing: Spacing.micro) {
        Text("Impersonating: \(targetName)")
          .font(.tidexLabelStrong)
          .foregroundStyle(Color.tidexTextPrimary)

        if let expiresAt {
          ExpirationText(expiresAt: expiresAt)
        }
      }

      Spacer()

      // Stop button
      Button {
        isLoading = true
        onStop()
      } label: {
        if isLoading {
          ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: .white))
            .frame(width: 16, height: 16)
        } else {
          Text("Stop")
            .font(.tidexLabelStrong)
        }
      }
      .disabled(isLoading)
      .padding(.horizontal, Spacing.md)
      .padding(.vertical, Spacing.xs)
      .background(Color.tidexError)
      .foregroundStyle(.white)
      .cornerRadius(CornerRadius.sm)
    }
    .padding(Spacing.sm)
    .background(Color.tidexWarning.opacity(0.15))
    .overlay(
      Rectangle()
        .frame(height: 2)
        .foregroundStyle(Color.tidexWarning),
      alignment: .bottom
    )
  }
}

// MARK: - Expiration Text

private struct ExpirationText: View {
  let expiresAt: Date

  @State private var timeRemaining: String = ""

  var body: some View {
    Text(timeRemaining)
      .font(.tidexCaptionRegular)
      .foregroundStyle(isExpiringSoon ? Color.tidexError : Color.tidexTextSecondary)
      .onAppear { updateTimeRemaining() }
      .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
        updateTimeRemaining()
      }
  }

  private var isExpiringSoon: Bool {
    expiresAt.timeIntervalSinceNow < 300  // Less than 5 minutes
  }

  private func updateTimeRemaining() {
    let remaining = expiresAt.timeIntervalSinceNow

    if remaining <= 0 {
      timeRemaining = "Session expired"
      return
    }

    let hours = Int(remaining) / 3600
    let minutes = (Int(remaining) % 3600) / 60
    let seconds = Int(remaining) % 60

    if hours > 0 {
      timeRemaining = "Expires in \(hours)h \(minutes)m"
    } else if minutes > 0 {
      timeRemaining = "Expires in \(minutes)m \(seconds)s"
    } else {
      timeRemaining = "Expires in \(seconds)s"
    }
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    ImpersonationBanner(
      targetName: "John Doe",
      expiresAt: Date().addingTimeInterval(3600),
      onStop: {}
    )

    ImpersonationBanner(
      targetName: "test@example.com",
      expiresAt: Date().addingTimeInterval(120),
      onStop: {}
    )

    ImpersonationBanner(
      targetName: "Long Username Here That Might Wrap",
      expiresAt: nil,
      onStop: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
