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
] as const;

export type AdminAction = (typeof ADMIN_ACTIONS)[number];

export type ActionSeverity = "info" | "warning" | "destructive";

export interface ActionConfig {
  label: string;
  severity: ActionSeverity;
}

export const ADMIN_ACTION_CONFIG: Record<AdminAction, ActionConfig> = {
  user_ban: { label: "Utestengt bruker", severity: "destructive" },
  user_unban: { label: "Fjernet utestengelse", severity: "info" },
  grant_grandfathered: { label: "Ga livstidstilgang", severity: "info" },
  revoke_grandfathered: {
    label: "Fjernet livstidstilgang",
    severity: "warning",
  },
  create_trial_subscription: {
    label: "Opprettet prøveperiode",
    severity: "info",
  },
  revoke_trial_subscription: {
    label: "Avsluttet prøveperiode",
    severity: "warning",
  },
  broadcast_sent: { label: "Sendte varsel", severity: "info" },
  user_list_viewed: { label: "Viste brukerliste", severity: "info" },
  user_lookup: { label: "Søkte opp bruker", severity: "info" },
  admin_action_failed: { label: "Handling feilet", severity: "destructive" },
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
