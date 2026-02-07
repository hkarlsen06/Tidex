import SwiftUI

// MARK: - Add Friend Form

/// Expandable form for adding a new friend by email or phone
struct AddFriendForm: View {
  @Binding var isExpanded: Bool
  @Binding var identifier: String
  @Binding var showEarnings: Bool
  @Binding var error: String?

  let isLoading: Bool
  let canAdd: Bool
  let capacityDisplay: String
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
            HStack(spacing: Spacing.xxs) {
              Text(capacityDisplay)
                .font(.tidexFootnoteMedium)
                .foregroundColor(canAdd ? .tidexTextMuted : .orange)

              if !canAdd {
                Image(systemName: "exclamationmark.circle.fill")
                  .font(.tidexCaptionRegular)
                  .foregroundColor(.orange)
              }
            }

            if canAdd {
              Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                  isExpanded = true
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
              }
              .buttonStyle(PlainButtonStyle())
            }
          }
        }
      }

      // Expanded form
      if isExpanded {
        VStack(spacing: Spacing.sm) {
          // Input field
          VStack(alignment: .leading, spacing: 6) {
            TextField(
              String(localized: .sharingEmailOrPhone),
              text: $identifier
            )
            .textFieldStyle(TidexTextFieldStyle())
            .textContentType(.emailAddress)
            .keyboardType(.emailAddress)
            .autocapitalization(.none)
            .autocorrectionDisabled()
            .focused($isFocused)
            .disabled(isLoading)

            // Error message
            if let error = error {
              Text(error)
                .font(.tidexCaptionRegular)
                .foregroundColor(.red)
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
              .toggleStyle(SwitchToggleStyle(tint: .green))
          }
          .padding(.horizontal, Spacing.xxs)
          .disabled(isLoading)

          // Action buttons
          HStack(spacing: Spacing.sm) {
            Spacer()

            Button(action: onCancel) {
              Text(.commonCancel)
                .font(.tidexLabel)
                .foregroundColor(.tidexTextMuted)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isLoading)

            Button(action: onAdd) {
              HStack(spacing: 6) {
                if isLoading {
                  ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
                }
                Text(.sharingAdd)
                  .font(.tidexLabelStrong)
              }
              .foregroundColor(.white)
              .padding(.horizontal, Spacing.md)
              .padding(.vertical, Spacing.sm)
              .background(
                identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                  ? Color.tidexBlue.opacity(0.5)
                  : Color.tidexBlue
              )
              .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(
              identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
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
      .cornerRadius(10)
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
      capacityDisplay: "2/5 delinger",
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
      capacityDisplay: "2/5 delinger",
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
      capacityDisplay: "2/5 delinger",
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
      capacityDisplay: "5/5 delinger",
      onAdd: {},
      onCancel: {}
    )
  }
  .padding()
  .background(Color.tidexBackground)
}
