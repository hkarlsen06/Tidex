import SwiftUI

/// Displays the status of a tool call execution
/// Shows tool name with spinner (in progress), checkmark (success), or X (failure)
struct ToolStatusView: View {
    let toolCall: ToolCall

    @Environment(\.localization) private var localization

    /// Whether the tool is still executing (no result yet)
    private var isExecuting: Bool {
        toolCall.result == nil
    }

    /// Whether the tool succeeded
    private var succeeded: Bool {
        toolCall.success == true
    }

    /// Display name for the tool
    private var toolDisplayName: String {
        toolNameMapping[toolCall.name] ?? toolCall.name
    }

    /// Map tool names to user-friendly display strings
    private var toolNameMapping: [String: String] {
        [
            "manage_shift": localization.string("wagey.tool.manageShift"),
            "get_shifts": localization.string("wagey.tool.getShifts"),
            "get_settings": localization.string("wagey.tool.getSettings"),
            "update_settings": localization.string("wagey.tool.updateSettings"),
            "get_stats": localization.string("wagey.tool.getStats")
        ]
    }

    var body: some View {
        HStack(spacing: 8) {
            // Status icon
            statusIcon
                .frame(width: 16, height: 16)

            // Tool name
            Text(toolDisplayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.tidexTextSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isExecuting {
            // Spinner while executing
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .tidexBlue))
                .scaleEffect(0.7)
        } else if succeeded {
            // Checkmark on success
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.tidexSuccess)
        } else {
            // X mark on failure
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(.tidexError)
        }
    }
}

// MARK: - Previews

#Preview("Executing") {
    VStack(spacing: 12) {
        ToolStatusView(toolCall: ToolCall(
            id: "1",
            name: "manage_shift",
            arguments: nil,
            result: nil,
            success: nil
        ))

        ToolStatusView(toolCall: ToolCall(
            id: "2",
            name: "get_shifts",
            arguments: nil,
            result: nil,
            success: nil
        ))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Completed") {
    VStack(spacing: 12) {
        ToolStatusView(toolCall: ToolCall(
            id: "1",
            name: "manage_shift",
            arguments: nil,
            result: "{\"success\": true}",
            success: true
        ))

        ToolStatusView(toolCall: ToolCall(
            id: "2",
            name: "get_shifts",
            arguments: nil,
            result: "Error fetching shifts",
            success: false
        ))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
