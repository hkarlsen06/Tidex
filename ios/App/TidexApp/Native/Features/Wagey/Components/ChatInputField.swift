import SwiftUI

/// Chat input field with send button
/// Supports multi-line input and disabled states
struct ChatInputField: View {
    /// Callback when user sends a message
    let onSend: (String) -> Void

    /// Whether the input should be disabled
    let disabled: Bool

    @Environment(\.localization) private var localization

    /// Current input text
    @State private var inputText: String = ""

    /// Whether the text field is focused
    @FocusState private var isFocused: Bool

    /// Whether the send button can be tapped
    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !disabled
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top border
            Divider()
                .background(Color.tidexBorder)

            // Input area
            HStack(alignment: .center, spacing: 12) {
                // Text input
                TextField(
                    localization.string("wagey.placeholder"),
                    text: $inputText,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundColor(.tidexTextPrimary)
                .lineLimit(1...5)
                .focused($isFocused)
                .disabled(disabled)
                .submitLabel(.send)
                .onSubmit {
                    sendMessage()
                }

                // Send button
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(canSend ? .tidexBlue : .tidexTextMuted)
                }
                .disabled(!canSend)
                .animation(.easeInOut(duration: 0.15), value: canSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.tidexBackground)
        .safeAreaPadding(.bottom)
    }

    // MARK: - Actions

    private func sendMessage() {
        guard canSend else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Provide haptic feedback
        Haptics.play(.medium)

        // Dismiss keyboard
        isFocused = false

        // Clear input
        inputText = ""

        // Send message
        onSend(message)
    }
}

// MARK: - Previews

#Preview("Default") {
    VStack {
        Spacer()
        ChatInputField(
            onSend: { message in
                print("Sent: \(message)")
            },
            disabled: false
        )
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("With Text") {
    VStack {
        Spacer()
        ChatInputField(
            onSend: { message in
                print("Sent: \(message)")
            },
            disabled: false
        )
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Disabled") {
    VStack {
        Spacer()
        ChatInputField(
            onSend: { message in
                print("Sent: \(message)")
            },
            disabled: true
        )
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
