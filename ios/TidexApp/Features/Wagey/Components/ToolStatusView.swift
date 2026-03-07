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
    var name: String
    if let actionName = actionSpecificName {
      name = actionName
    } else {
      name = toolNameMapping[toolCall.name] ?? toolCall.name
    }

    if !isExecuting {
      name = name.replacingOccurrences(of: "...", with: "")
        .replacingOccurrences(of: "…", with: "")
        .trimmingCharacters(in: .whitespaces)
    }

    return name
  }

  /// Try to extract the "action" field from tool arguments and return
  /// an action-specific display name (e.g., "Creating shift..." instead of "Managing shift...")
  private var actionSpecificName: String? {
    guard let args = toolCall.arguments,
      let data = args.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let action = json["action"] as? String
    else { return nil }

    var key = "\(toolCall.name).\(action)"
    if toolCall.name == "manage_workplace",
      action == "reorder",
      let direction = json["direction"] as? String
    {
      key = "\(key).\(direction)"
    }
    return actionNameMapping[key] ?? actionNameMapping["\(toolCall.name).\(action)"]
  }

  /// Map (tool_name.action) pairs to specific display names
  private var actionNameMapping: [String: String] {
    [
      "manage_shift.create": String(localized: .wageyToolShiftCreating),
      "manage_shift.update": String(localized: .wageyToolShiftUpdating),
      "manage_shift.delete": String(localized: .wageyToolShiftDeleting),

      "manage_recurring_shift.create": String(localized: .wageyToolRecurringCreating),
      "manage_recurring_shift.update": String(localized: .wageyToolRecurringUpdating),
      "manage_recurring_shift.delete": String(localized: .wageyToolRecurringDeleting),

      "manage_recurring_exclusion.create": String(localized: .wageyToolExclusionAdding),
      "manage_recurring_exclusion.delete": String(localized: .wageyToolExclusionRemoving),

      "manage_wage_snapshots.create": String(localized: .wageyToolWageSnapshotAdding),
      "manage_wage_snapshots.update": String(localized: .wageyToolWageSnapshotUpdating),
      "manage_wage_snapshots.delete": String(localized: .wageyToolWageSnapshotDeleting),

      "manage_workplace.create": String(localized: .wageyToolWorkplaceCreating),
      "manage_workplace.update": String(localized: .wageyToolWorkplaceUpdating),
      "manage_workplace.archive": String(localized: .wageyToolWorkplaceArchiving),
      "manage_workplace.unarchive": String(localized: .wageyToolWorkplaceUnarchiving),
      "manage_workplace.set_default": String(localized: .wageyToolWorkplaceSettingDefault),
      "manage_workplace.reorder.up": String(localized: .wageyToolWorkplaceReorderingUp),
      "manage_workplace.reorder.down": String(localized: .wageyToolWorkplaceReorderingDown),
      "manage_workplace.delete": String(localized: .wageyToolWorkplaceDeleting),

      "manage_friend_sharing.share_by_identifier": String(
        localized: .wageyToolFriendSharingShareByIdentifier),
      "manage_friend_sharing.share_back": String(localized: .wageyToolFriendSharingShareBack),
      "manage_friend_sharing.remove_recipient": String(
        localized: .wageyToolFriendSharingRemoveRecipient),
      "manage_friend_sharing.toggle_recipient_earnings": String(
        localized: .wageyToolFriendSharingToggleRecipientEarnings),
      "manage_friend_sharing.block_sharer": String(localized: .wageyToolFriendSharingBlockSharer),
      "manage_friend_sharing.unblock_sharer": String(
        localized: .wageyToolFriendSharingUnblockSharer),
      "manage_friend_sharing.set_sharer_muted": String(
        localized: .wageyToolFriendSharingSetSharerMuted),
      "manage_friend_sharing.remove_sharer": String(localized: .wageyToolFriendSharingRemoveSharer),

      "manage_shift_advanced.copy_shifts": String(localized: .wageyToolShiftAdvancedCopyShifts),
      "manage_shift_advanced.update_custom_supplements": String(
        localized: .wageyToolShiftAdvancedUpdateCustomSupplements),
      "manage_shift_advanced.convert_recurring_to_standalone": String(
        localized: .wageyToolShiftAdvancedConvertRecurringToStandalone),
      "manage_shift_advanced.move_recurring_occurrence": String(
        localized: .wageyToolShiftAdvancedMoveRecurringOccurrence),
      "manage_shift_advanced.clear_shift_snapshots": String(
        localized: .wageyToolShiftAdvancedClearShiftSnapshots),

      "manage_feedback.submit": String(localized: .wageyToolFeedbackSubmit),
      "manage_feedback.list": String(localized: .wageyToolFeedbackList),

      "manage_profile.view": String(localized: .wageyToolProfileView),
      "manage_profile.update_name": String(localized: .wageyToolProfileUpdateName),
    ]
  }

  /// Fallback map for tools without action-specific names
  /// Tool names match those defined in lib/chat/tools.ts
  private var toolNameMapping: [String: String] {
    [
      // Shift management
      "manage_shift": String(localized: .wageyToolManageShift),
      "query_shifts": String(localized: .wageyToolQueryShifts),
      "calculate_wages": String(localized: .wageyToolCalculateWages),

      // Recurring shifts
      "draft_recurring_shift": String(localized: .wageyToolDraftRecurring),
      "confirm_recurring_shift": String(localized: .wageyToolConfirmRecurring),
      "manage_recurring_shift": String(localized: .wageyToolManageRecurring),
      "manage_recurring_exclusion": String(localized: .wageyToolManageExclusion),

      // Statistics and settings
      "get_statistics": String(localized: .wageyToolGetStatistics),
      "manage_settings": String(localized: .wageyToolManageSettings),
      "get_wage_info": String(localized: .wageyToolGetWageInfo),
      "calculate_earnings": String(localized: .wageyToolCalculateEarnings),

      // Wage snapshots
      "manage_wage_snapshots": String(localized: .wageyToolManageWageSnapshots),

      // Workplaces
      "list_workplaces": String(localized: .wageyToolListWorkplaces),
      "manage_workplace": String(localized: .wageyToolManageWorkplace),

      // Friends and sharing
      "list_friends": String(localized: .wageyToolListFriends),
      "manage_friend_sharing": String(localized: .wageyToolManageFriendSharing),
      "query_friend_shifts": String(localized: .wageyToolQueryFriendShifts),
      "query_friend_featured_shift": String(localized: .wageyToolQueryFriendFeaturedShift),

      // Advanced shifts
      "manage_shift_advanced": String(localized: .wageyToolManageShiftAdvanced),

      // Feedback and profile
      "manage_feedback": String(localized: .wageyToolManageFeedback),
      "manage_profile": String(localized: .wageyToolManageProfile),

      // OpenAI built-in tools
      "web_search": String(localized: .wageyToolWebSearch),
      "code_interpreter": String(localized: .wageyToolCodeInterpreter),
    ]
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

          detailRow(label: "Tool", value: toolCall.name)

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
      withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
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
    guard let data = string.data(using: .utf8),
      let jsonObject = try? JSONSerialization.jsonObject(with: data),
      let prettyData = try? JSONSerialization.data(
        withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
      let prettyString = String(data: prettyData, encoding: .utf8)
    else {
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
