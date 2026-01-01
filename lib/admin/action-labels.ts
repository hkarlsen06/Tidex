/**
 * Admin action type definitions and label mapping
 * Used for consistent UI rendering in the audit log
 */

export const ADMIN_ACTIONS = [
  "user_lookup",
  "user_ban",
  "user_unban",
  "grant_grandfathered",
  "revoke_grandfathered",
  "create_trial_subscription",
  "revoke_trial_subscription",
  "broadcast_sent",
  "user_list_viewed",
  "admin_action_failed",
  "sql_executed",
  "shift_share_created",
  "shift_share_updated",
  "shift_share_deleted",
] as const;

export type AdminAction = (typeof ADMIN_ACTIONS)[number];

export type ActionSeverity = "info" | "warning" | "destructive";

export interface ActionConfig {
  label: string;
  severity: ActionSeverity;
}

export const ADMIN_ACTION_CONFIG: Record<AdminAction, ActionConfig> = {
  user_ban: { label: "Banned user", severity: "destructive" },
  user_unban: { label: "Removed ban", severity: "info" },
  grant_grandfathered: { label: "Granted lifetime access", severity: "info" },
  revoke_grandfathered: {
    label: "Revoked lifetime access",
    severity: "warning",
  },
  create_trial_subscription: {
    label: "Created trial",
    severity: "info",
  },
  revoke_trial_subscription: {
    label: "Ended trial",
    severity: "warning",
  },
  broadcast_sent: { label: "Sent notification", severity: "info" },
  user_list_viewed: { label: "Viewed user list", severity: "info" },
  user_lookup: { label: "Looked up user", severity: "info" },
  admin_action_failed: { label: "Action failed", severity: "destructive" },
  sql_executed: { label: "Executed SQL", severity: "warning" },
  shift_share_created: { label: "Created shift share", severity: "info" },
  shift_share_updated: { label: "Updated shift share", severity: "info" },
  shift_share_deleted: { label: "Deleted shift share", severity: "warning" },
} as const;

/**
 * Get display label for an admin action
 */
export function getActionLabel(action: AdminAction): string {
  return ADMIN_ACTION_CONFIG[action]?.label ?? action;
}

/**
 * Get severity for an admin action
 */
export function getActionSeverity(action: AdminAction): ActionSeverity {
  return ADMIN_ACTION_CONFIG[action]?.severity ?? "info";
}
