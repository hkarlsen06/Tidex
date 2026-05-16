import Foundation

enum WageyToolLabelResolver {
  static func displayName(for toolCall: ToolCall, isExecuting: Bool) -> String {
    var name = actionSpecificName(for: toolCall) ?? fallbackName(for: toolCall.name)

    if !isExecuting {
      name = name.replacingOccurrences(of: "...", with: "")
        .replacingOccurrences(of: "…", with: "")
        .trimmingCharacters(in: .whitespaces)
    }

    return name
  }

  private static func actionSpecificName(for toolCall: ToolCall) -> String? {
    guard
      let arguments = toolCall.arguments,
      let data = arguments.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let action = json["action"] as? String
    else {
      return nil
    }

    var key = "\(toolCall.name).\(action)"
    if toolCall.name == "manage_workplace",
      action == "reorder",
      let direction = json["direction"] as? String
    {
      key = "\(key).\(direction)"
    }

    return actionNameMapping[key] ?? actionNameMapping["\(toolCall.name).\(action)"]
  }

  private static func fallbackName(for toolName: String) -> String {
    toolNameMapping[toolName] ?? toolName
  }

  private static var actionNameMapping: [String: String] {
    [
      "manage_shift.create": String(localized: .wageyToolShiftCreating),
      "manage_shift.update": String(localized: .wageyToolShiftUpdating),
      "manage_shift.delete": String(localized: .wageyToolShiftDeleting),

      "manage_event.create": String(localized: .wageyToolEventCreating),
      "manage_event.update": String(localized: .wageyToolEventUpdating),
      "manage_event.delete": String(localized: .wageyToolEventDeleting),

      "plan_schedule.agenda": String(localized: .wageyToolScheduleAgenda),
      "plan_schedule.conflicts": String(localized: .wageyToolScheduleConflicts),
      "plan_schedule.free_slots": String(localized: .wageyToolScheduleFreeSlots),

      "manage_recurring_shift.create": String(localized: .wageyToolRecurringCreating),
      "manage_recurring_shift.draft_create": String(localized: .wageyToolDraftRecurring),
      "manage_recurring_shift.confirm_create": String(localized: .wageyToolConfirmRecurring),
      "manage_recurring_shift.update": String(localized: .wageyToolRecurringUpdating),
      "manage_recurring_shift.delete": String(localized: .wageyToolRecurringDeleting),
      "manage_recurring_shift.add_exclusion": String(localized: .wageyToolExclusionAdding),
      "manage_recurring_shift.remove_exclusion": String(localized: .wageyToolExclusionRemoving),

      "manage_recurring_exclusion.create": String(localized: .wageyToolExclusionAdding),
      "manage_recurring_exclusion.delete": String(localized: .wageyToolExclusionRemoving),

      "manage_wage_snapshots.create": String(localized: .wageyToolWageSnapshotAdding),
      "manage_wage_snapshots.update": String(localized: .wageyToolWageSnapshotUpdating),
      "manage_wage_snapshots.delete": String(localized: .wageyToolWageSnapshotDeleting),

      "manage_payroll_adjustment.list": String(localized: .wageyToolPayrollAdjustmentListing),
      "manage_payroll_adjustment.create": String(
        localized: .wageyToolPayrollAdjustmentCreating),
      "manage_payroll_adjustment.update": String(
        localized: .wageyToolPayrollAdjustmentUpdating),
      "manage_payroll_adjustment.delete": String(
        localized: .wageyToolPayrollAdjustmentDeleting),

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
      "manage_shift_advanced.update_custom_pause_windows": String(
        localized: .settingsPayEditorBreakTitle),
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

      "manage_account.view_settings": String(localized: .wageyToolManageSettings),
      "manage_account.update_settings": String(localized: .wageyToolManageSettings),
      "manage_account.view_profile": String(localized: .wageyToolProfileView),
      "manage_account.update_name": String(localized: .wageyToolProfileUpdateName),
      "manage_account.submit_feedback": String(localized: .wageyToolFeedbackSubmit),
      "manage_account.list_feedback": String(localized: .wageyToolFeedbackList),
    ]
  }

  private static var toolNameMapping: [String: String] {
    [
      "manage_shift": String(localized: .wageyToolManageShift),
      "query_shifts": String(localized: .wageyToolQueryShifts),
      "query_events": String(localized: .wageyToolQueryEvents),
      "manage_event": String(localized: .wageyToolManageEvent),
      "plan_schedule": String(localized: .wageyToolPlanSchedule),
      "calculate_wages": String(localized: .wageyToolCalculateWages),

      "draft_recurring_shift": String(localized: .wageyToolDraftRecurring),
      "confirm_recurring_shift": String(localized: .wageyToolConfirmRecurring),
      "manage_recurring_shift": String(localized: .wageyToolManageRecurring),
      "manage_recurring_exclusion": String(localized: .wageyToolManageExclusion),

      "get_statistics": String(localized: .wageyToolGetStatistics),
      "manage_account": String(localized: .wageyToolManageSettings),
      "manage_settings": String(localized: .wageyToolManageSettings),
      "get_wage_info": String(localized: .wageyToolGetWageInfo),
      "calculate_earnings": String(localized: .wageyToolCalculateEarnings),

      "manage_wage_snapshots": String(localized: .wageyToolManageWageSnapshots),
      "manage_payroll_adjustment": String(localized: .wageyToolManagePayrollAdjustment),

      "list_workplaces": String(localized: .wageyToolListWorkplaces),
      "manage_workplace": String(localized: .wageyToolManageWorkplace),

      "list_friends": String(localized: .wageyToolListFriends),
      "manage_friend_sharing": String(localized: .wageyToolManageFriendSharing),
      "query_friend_shifts": String(localized: .wageyToolQueryFriendShifts),
      "query_friend_featured_shift": String(localized: .wageyToolQueryFriendFeaturedShift),

      "manage_shift_advanced": String(localized: .wageyToolManageShiftAdvanced),

      "manage_feedback": String(localized: .wageyToolManageFeedback),
      "manage_profile": String(localized: .wageyToolManageProfile),

      "web_search": String(localized: .wageyToolWebSearch),
      "web_fetch": String(localized: .wageyToolWebFetch),
      "code_interpreter": String(localized: .wageyToolCodeInterpreter),
    ]
  }
}
