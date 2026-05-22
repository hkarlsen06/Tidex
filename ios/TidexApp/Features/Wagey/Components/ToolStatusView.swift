import SwiftUI

/// Displays the status of a tool call execution
/// Shows tool name with spinner (in progress), checkmark (success), or X (failure)
/// Shows timeout error if tool doesn't complete within the timeout period
/// Tapping expands to show the tool call details (arguments and result)
struct ToolStatusView: View {
  let toolCall: ToolCall

  /// Timeout in seconds before showing error state
  private let timeoutSeconds: Double = 30

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

  /// Display name for the tool, using action-specific names when available.
  /// Strips trailing ellipsis once the tool call has completed.
  private var toolDisplayName: String {
    WageyToolLabelResolver.displayName(for: toolCall, isExecuting: isExecuting)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      // Compact pill header
      HStack(spacing: Spacing.xxxs) {
        statusIcon
          .frame(width: 14, height: 14)

        Text(toolDisplayName)
          .font(.tidexFootnoteMedium)
          .foregroundColor(.tidexTextSecondary)

        if !isExecuting {
          Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
            .font(.tidexMicro.weight(.semibold))
            .foregroundColor(.tidexTextMuted)
        }
      }
      .padding(.horizontal, Spacing.sm)
      .padding(.vertical, 7)

      // Expanded details
      if isExpanded {
        VStack(alignment: .leading, spacing: Spacing.xs) {
          Divider()
            .background(Color.tidexBorder)

          detailRow(label: String(localized: .wageyToolName), value: toolDisplayName)

          if let arguments = toolCall.arguments, !arguments.isEmpty {
            detailSection(
              label: String(localized: .wageyToolRequest), content: formatJSON(arguments))
          }

          if let result = toolCall.result {
            detailSection(label: String(localized: .wageyToolResponse), content: formatJSON(result))
          } else if isTimedOut {
            detailSection(
              label: String(localized: .wageyToolResponse),
              content: String(localized: .wageyToolTimedOut))
          }
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.bottom, Spacing.xsm)
        .padding(.top, Spacing.xxs)
      }
    }
    .background(Color.tidexSurfaceSecondary.opacity(0.6))
    .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 14 : 100, style: .continuous))
    .contentShape(RoundedRectangle(cornerRadius: isExpanded ? 14 : 100, style: .continuous))
    .onTapGesture {
      guard !isExecuting else { return }
      Haptics.play(.light)
      withAnimation(.easeOut(duration: 0.18)) {
        isExpanded.toggle()
      }
    }
    .contextMenu {
      Button {
        var text = toolDisplayName
        if let args = toolCall.arguments, !args.isEmpty {
          text += "\n\n\(String(localized: .wageyToolRequest)):\n\(formatJSON(args))"
        }
        if let result = toolCall.result {
          text += "\n\n\(String(localized: .wageyToolResponse)):\n\(formatJSON(result))"
        }
        UIPasteboard.general.string = text
      } label: {
        Label(String(localized: .commonCopy), systemImage: "doc.on.doc")
      }
    }
    .onAppear {
      appearedAt = Date()
    }
    .onReceive(timer) { _ in
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
    HStack(alignment: .top, spacing: Spacing.xs) {
      Text(label)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)
        .frame(width: 60, alignment: .leading)

      Text(value)
        .font(.tidexMonoCaptionRegular)
        .foregroundColor(.tidexTextPrimary)
    }
  }

  private func detailSection(label: String, content: String) -> some View {
    VStack(alignment: .leading, spacing: Spacing.xxs) {
      Text(label)
        .font(.tidexCaptionRegular)
        .foregroundColor(.tidexTextMuted)

      ScrollView(.horizontal, showsIndicators: false) {
        Text(content)
          .font(.tidexMonoCaptionRegular)
          .foregroundColor(.tidexTextPrimary)
          .padding(Spacing.xs)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Color.tidexSurfacePrimary)
      .clipShape(RoundedRectangle(cornerRadius: CornerRadius.xs, style: .continuous))
    }
  }

  /// Format a JSON string for display (pretty-print if valid JSON)
  private func formatJSON(_ string: String) -> String {
    WageyToolJSONFormatter.format(string)
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
        .font(.tidexSubheadline)
        .foregroundColor(.tidexSuccess)
    } else {
      // X mark on failure (explicit failure or timeout)
      Image(systemName: "xmark.circle.fill")
        .font(.tidexSubheadline)
        .foregroundColor(.tidexError)
    }
  }
}

// MARK: - Previews

#Preview("Executing") {
  VStack(spacing: Spacing.sm) {
    // Shows "Creating shift..." (action-specific)
    ToolStatusView(
      toolCall: ToolCall(
        id: "1",
        name: "manage_shift",
        arguments:
          "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\"}",
        result: nil,
        success: nil
      ))

    // Shows "Finding shifts..." (fallback)
    ToolStatusView(
      toolCall: ToolCall(
        id: "2",
        name: "query_shifts",
        arguments: "{\"start_date\":\"2025-01-01\",\"end_date\":\"2025-01-31\"}",
        result: nil,
        success: nil
      ))

    // Shows "Deleting shift..." (action-specific)
    ToolStatusView(
      toolCall: ToolCall(
        id: "3",
        name: "manage_shift",
        arguments: "{\"action\":\"delete\",\"shift_id\":\"abc123\"}",
        result: nil,
        success: nil
      ))
  }
  .padding()
  .background(Color.tidexBackground)
}

#Preview("Completed - Success") {
  ScrollView {
    VStack(spacing: Spacing.sm) {
      ToolStatusView(
        toolCall: ToolCall(
          id: "1",
          name: "manage_shift",
          arguments:
            "{\"action\":\"create\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\"}",
          result:
            "{\"success\":true,\"shift\":{\"id\":\"abc123\",\"date\":\"2025-01-28\",\"start_time\":\"09:00\",\"end_time\":\"17:00\",\"hours\":8.0}}",
          success: true
        ))

      ToolStatusView(
        toolCall: ToolCall(
          id: "2",
          name: "query_shifts",
          arguments: "{\"start_date\":\"2025-01-01\",\"end_date\":\"2025-01-31\"}",
          result:
            "{\"success\":true,\"shifts\":[{\"id\":\"1\",\"date\":\"2025-01-15\"},{\"id\":\"2\",\"date\":\"2025-01-20\"}],\"count\":2}",
          success: true
        ))
    }
    .padding()
  }
  .background(Color.tidexBackground)
}

#Preview("Completed - Failed") {
  ScrollView {
    VStack(spacing: Spacing.sm) {
      ToolStatusView(
        toolCall: ToolCall(
          id: "1",
          name: "manage_shift",
          arguments: "{\"action\":\"create\",\"date\":\"2025-01-28\"}",
          result: "{\"success\":false,\"message\":\"Missing required field: start_time\"}",
          success: false
        ))

      ToolStatusView(
        toolCall: ToolCall(
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
}
