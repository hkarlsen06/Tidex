import SwiftUI

// MARK: - Add Friend Form

/// Expandable form for adding a new friend by email, phone, or username
struct AddFriendForm: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @Binding var isExpanded: Bool
  @Binding var identifier: String
  @Binding var showEarnings: Bool
  @Binding var error: String?

  let isLoading: Bool
  let canAdd: Bool
  let isOfflineUnavailable: Bool
  let capacityDisplay: String
  let shouldShowCapacity: Bool
  let onAdd: () -> Void
  let onCancel: () -> Void

  @FocusState private var isFocused: Bool

  var body: some View {
    VStack(spacing: Spacing.md) {
      // Header with expand button
      HStack {
        Text(.sharingAddFriend)
          .font(.tidexLabelStrong)
          .foregroundColor(.tidexTextMuted)
          .textCase(.uppercase)

        Spacer()

        if !isExpanded {
          // Capacity count to the left of the plus button
          HStack(spacing: Spacing.xs) {
            if shouldShowCapacity {
              HStack(spacing: Spacing.xxs) {
                Text(capacityDisplay)
                  .font(.tidexFootnoteMedium)
                  .foregroundColor(canAdd ? .tidexTextMuted : .tidexWarning)

                if !canAdd {
                  Image(systemName: "exclamationmark.circle.fill")
                    .font(.tidexCaptionRegular)
                    .foregroundColor(.tidexWarning)
                }
              }
            }

            if canAdd, !isOfflineUnavailable {
              Button(action: {
                if reduceMotion {
                  isExpanded = true
                } else {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                  }
                }
                // Focus the input after minimal delay (just enough for animation)
                Task { @MainActor in
                  try? await Task.sleep(for: .milliseconds(150))
                  isFocused = true
                }
              }) {
                Image(systemName: "plus.circle.fill")
                  .font(.system(size: 24))
                  .foregroundColor(.tidexBlue)
                  .frame(minWidth: 44, minHeight: 44)
                  .contentShape(Rectangle())
              }
              .buttonStyle(PlainButtonStyle())
              .accessibilityLabel(Text(.sharingAddFriend))
            }
          }
        }
      }

      if isOfflineUnavailable {
        Text(.sharingOfflineAddFriendUnavailable)
          .font(.tidexCaptionRegular)
          .foregroundColor(.tidexTextMuted)
          .frame(maxWidth: .infinity, alignment: .leading)
      }

      // Expanded form
      if isExpanded {
        VStack(spacing: Spacing.sm) {
          // Input field
          VStack(alignment: .leading, spacing: Spacing.xxxs) {
            TextField(
              String(localized: .sharingEmailOrPhoneOrUsername),
              text: $identifier
            )
            .textFieldStyle(TidexTextFieldStyle())
            .keyboardType(.default)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .focused($isFocused)
            .disabled(isLoading || isOfflineUnavailable)

            // Error message
            if let error {
              Text(error)
                .font(.tidexCaptionRegular)
                .foregroundColor(.tidexError)
            }
          }

          // Show earnings toggle
          HStack {
            Image(systemName: "dollarsign.circle")
              .font(.tidexBody)
              .foregroundColor(.tidexTextMuted)

            Toggle(String(localized: .sharingShowEarnings), isOn: $showEarnings)
              .font(.tidexSubheadline)
              .foregroundColor(.tidexTextPrimary)
              .toggleStyle(SwitchToggleStyle(tint: .tidexSuccess))
          }
          .padding(.horizontal, Spacing.xxs)
          .disabled(isLoading || isOfflineUnavailable)

          // Action buttons
          HStack(spacing: Spacing.sm) {
            Spacer()

            Button(action: onCancel) {
              Text(.commonCancel)
                .font(.tidexLabel)
                .foregroundColor(.tidexTextMuted)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLoading)

            Button(action: onAdd) {
              HStack(spacing: Spacing.xxxs) {
                if isLoading {
                  ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .tidexTextOnBrand))
                    .scaleEffect(0.8)
                }
                Text(.sharingAdd)
                  .font(.tidexLabelStrong)
              }
              .foregroundColor(.tidexTextOnBrand)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.sm)
              .frame(minHeight: 44)
              .background(
                identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                  || isOfflineUnavailable
                  ? Color.tidexBlue.opacity(0.5)
                  : Color.tidexBlue
              )
              .cornerRadius(CornerRadius.sm)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(
              identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                || isOfflineUnavailable)
          }
        }
        .padding(.top, Spacing.xxs)
      }
    }
    .padding(Spacing.md)
    .onChange(of: isExpanded) { _, expanded in
      if expanded {
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(150))
          isFocused = true
        }
      }
    }
  }
}

// MARK: - Tidex Text Field Style

/// Custom text field style matching the app's design
struct TidexTextFieldStyle: TextFieldStyle {
  func _body(configuration: TextField<Self._Label>) -> some View {
    configuration
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, Spacing.sm)
      .background(Color.tidexSurfaceSecondary)
      .cornerRadius(CornerRadius.md)
      .font(.tidexBody)
  }
}

// MARK: - Preview

#Preview {
  VStack(spacing: Spacing.mlg) {
    // Collapsed state
    AddFriendForm(
      isExpanded: .constant(false),
      identifier: .constant(""),
      showEarnings: .constant(false),
      error: .constant(nil),
      isLoading: false,
      canAdd: true,
      isOfflineUnavailable: false,
      capacityDisplay: "2/5 delinger",
      shouldShowCapacity: false,
      onAdd: {},
      onCancel: {}
    )

    // Expanded state
    AddFriendForm(
      isExpanded: .constant(true),
      identifier: .constant("test@example.com"),
      showEarnings: .constant(true),
      error: .constant(nil),
      isLoading: false,
      canAdd: true,
      isOfflineUnavailable: false,
      capacityDisplay: "2/5 delinger",
      shouldShowCapacity: false,
      onAdd: {},
      onCancel: {}
    )

    // With error
    AddFriendForm(
      isExpanded: .constant(true),
      identifier: .constant("invalid"),
      showEarnings: .constant(false),
      error: .constant("Fant ingen bruker med denne e-posten"),
      isLoading: false,
      canAdd: true,
      isOfflineUnavailable: false,
      capacityDisplay: "2/5 delinger",
      shouldShowCapacity: false,
      onAdd: {},
      onCancel: {}
    )

    // Limit reached
    AddFriendForm(
      isExpanded: .constant(false),
      identifier: .constant(""),
      showEarnings: .constant(false),
      error: .constant(nil),
      isLoading: false,
      canAdd: false,
      isOfflineUnavailable: false,
      capacityDisplay: "5/5 delinger",
      shouldShowCapacity: true,
      onAdd: {},
      onCancel: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
