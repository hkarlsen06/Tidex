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

    @Environment(\.localization) private var localization
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Header with expand button
            HStack {
                Text(localization.string("sharing.addFriend"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.tidexTextMuted)
                    .textCase(.uppercase)

                Spacer()

                if !isExpanded {
                    // Capacity count to the left of the plus button
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text(capacityDisplay)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(canAdd ? .tidexTextMuted : .orange)

                            if !canAdd {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }

                        if canAdd {
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpanded = true
                                }
                                // Focus the input after a short delay
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
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
                VStack(spacing: 12) {
                    // Input field
                    VStack(alignment: .leading, spacing: 6) {
                        TextField(
                            localization.string("sharing.emailOrPhone"),
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
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                        }
                    }

                    // Show earnings toggle
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .font(.system(size: 16))
                            .foregroundColor(.tidexTextMuted)

                        Toggle(localization.string("sharing.showEarnings"), isOn: $showEarnings)
                            .font(.system(size: 15))
                            .foregroundColor(.tidexTextPrimary)
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                    }
                    .padding(.horizontal, 4)
                    .disabled(isLoading)

                    // Action buttons
                    HStack(spacing: 12) {
                        Spacer()

                        Button(action: onCancel) {
                            Text(localization.string("common.cancel"))
                                .font(.system(size: 15, weight: .medium))
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
                                Text(localization.string("sharing.add"))
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading
                                    ? Color.tidexBlue.opacity(0.5)
                                    : Color.tidexBlue
                            )
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.tidexSurfacePrimary)
        )
    }
}

// MARK: - Tidex Text Field Style

/// Custom text field style matching the app's design
struct TidexTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.tidexSurfaceSecondary)
            .cornerRadius(10)
            .font(.system(size: 16))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
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
    .environment(\.localization, LocalizationManager.shared)
}
