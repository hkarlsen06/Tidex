import SwiftUI

/// Displays the status of a tool call execution
/// Shows tool name with spinner (in progress), checkmark (success), or X (failure)
/// Shows timeout error if tool doesn't complete within the timeout period
/// Tapping expands to show the tool call details (arguments and result)
struct ToolStatusView: View {
    let toolCall: ToolCall

    /// Timeout in seconds before showing error state
    private let timeoutSeconds: Double = 30

    @Environment(\.localization) private var localization

    /// Track when the view appeared (for timeout calculation)
    @State private var appearedAt: Date = Date()

    /// Timer to check for timeout
    @State private var isTimedOut: Bool = false

    /// Whether the details view is expanded
    @State private var isExpanded: Bool = false

    /// Timer for periodic timeout checks
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Whether the tool is still executing (no result yet and not timed out)
    private var isExecuting: Bool {
        toolCall.result == nil && !isTimedOut
    }

    /// Whether the tool succeeded
    private var succeeded: Bool {
        toolCall.success == true
    }

    /// Whether the tool failed (explicit failure OR timeout)
    private var failed: Bool {
        toolCall.success == false || isTimedOut
    }

    /// Display name for the tool
    private var toolDisplayName: String {
        toolNameMapping[toolCall.name] ?? toolCall.name
    }

    /// Map tool names to user-friendly display strings
    /// Tool names match those defined in lib/chat/tools.ts
    private var toolNameMapping: [String: String] {
        [
            // Shift management
            "manage_shift": localization.string("wagey.tool.manageShift"),
            "query_shifts": localization.string("wagey.tool.queryShifts"),
            "calculate_wages": localization.string("wagey.tool.calculateWages"),

            // Recurring shifts
            "draft_recurring_shift": localization.string("wagey.tool.draftRecurring"),
            "confirm_recurring_shift": localization.string("wagey.tool.confirmRecurring"),
            "manage_recurring_shift": localization.string("wagey.tool.manageRecurring"),
            "manage_recurring_exclusion": localization.string("wagey.tool.manageExclusion"),

            // Statistics and settings
            "get_statistics": localization.string("wagey.tool.getStatistics"),
            "manage_settings": localization.string("wagey.tool.manageSettings"),
            "get_wage_info": localization.string("wagey.tool.getWageInfo"),
            "calculate_earnings": localization.string("wagey.tool.calculateEarnings"),

            // Wage snapshots
            "manage_wage_snapshots": localization.string("wagey.tool.manageWageSnapshots")
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            HStack(spacing: 8) {
                // Status icon
                statusIcon
                    .frame(width: 16, height: 16)

                // Tool name
                Text(toolDisplayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.tidexTextSecondary)

                Spacer()

                // Chevron indicator (only show when not executing)
                if !isExecuting {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.tidexTextMuted)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Expanded details (within the same container)
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                        .background(Color.tidexBorder)

                    // Tool name (raw API name)
                    detailRow(label: "Tool", value: toolCall.name)

                    // Arguments (if present)
                    if let arguments = toolCall.arguments, !arguments.isEmpty {
                        detailSection(label: localization.string("wagey.tool.request"), content: formatJSON(arguments))
                    }

                    // Result (if present)
                    if let result = toolCall.result {
                        detailSection(label: localization.string("wagey.tool.response"), content: formatJSON(result))
                    } else if isTimedOut {
                        detailSection(label: localization.string("wagey.tool.response"), content: localization.string("wagey.tool.timedOut"))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, 4)
            }
        }
        .background(Color.tidexSurfaceSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            // Only allow expansion when not executing
            guard !isExecuting else { return }
            Haptics.play(.light)
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isExpanded.toggle()
            }
        }
        .onAppear {
            appearedAt = Date()
        }
        .onReceive(timer) { _ in
            // Check for timeout only if still executing
            if toolCall.result == nil && !isTimedOut {
                let elapsed = Date().timeIntervalSince(appearedAt)
                if elapsed >= timeoutSeconds {
                    isTimedOut = true
                }
            }
        }
    }

    // MARK: - Detail Components

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.tidexTextMuted)
                .frame(width: 60, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.tidexTextPrimary)
        }
    }

    private func detailSection(label: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.tidexTextMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(content)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.tidexTextPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.tidexSurfacePrimary)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    /// Format a JSON string for display (pretty-print if valid JSON)
    private func formatJSON(_ string: String) -> String {
        guard let data = string.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return string
        }
        return prettyString
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
            // X mark on failure (explicit failure or timeout)
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
            arguments: "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\"}",
            result: nil,
            success: nil
        ))

        ToolStatusView(toolCall: ToolCall(
            id: "2",
            name: "query_shifts",
            arguments: "{\"start_date\":\"2025-01-01\",\"end_date\":\"2025-01-31\"}",
            result: nil,
            success: nil
        ))
    }
    .padding()
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Completed - Success") {
    ScrollView {
        VStack(spacing: 12) {
            ToolStatusView(toolCall: ToolCall(
                id: "1",
                name: "manage_shift",
                arguments: "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\"}",
                result: "{\"success\":true,\"shift\":{\"id\":\"abc123\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\",\"hours\":8.0}}",
                success: true
            ))

            ToolStatusView(toolCall: ToolCall(
                id: "2",
                name: "query_shifts",
                arguments: "{\"start_date\":\"2025-01-01\",\"end_date\":\"2025-01-31\"}",
                result: "{\"success\":true,\"shifts\":[{\"id\":\"1\",\"date\":\"2025-01-15\"},{\"id\":\"2\",\"date\":\"2025-01-20\"}],\"count\":2}",
                success: true
            ))
        }
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}

#Preview("Completed - Failed") {
    ScrollView {
        VStack(spacing: 12) {
            ToolStatusView(toolCall: ToolCall(
                id: "1",
                name: "manage_shift",
                arguments: "{\"action\":\"create\",\"date\":\"2025-01-28\"}",
                result: "{\"success\":false,\"message\":\"Missing required field: start_time\"}",
                success: false
            ))

            ToolStatusView(toolCall: ToolCall(
                id: "2",
                name: "get_statistics",
                arguments: nil,
                result: "Error: Network timeout",
                success: false
            ))
        }
        .padding()
    }
    .background(Color.tidexBackground)
    .environment(\.localization, LocalizationManager.shared)
}
