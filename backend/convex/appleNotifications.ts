import { v } from "convex/values";
import { internalMutation, type MutationCtx } from "./_generated/server";
import { nextRevision } from "./lib/revision";

// The database half of the apple-server-notifications Edge Function. appleVerify.ts
// checks Apple's signature first. This records each notification once by its UUID and
// keeps the user's subscription row in step with Apple.

const PRODUCTS: Record<string, string> = {
  "no.tidex.pro": "pro_monthly",
  "no.tidex.pro.year": "pro_yearly",
  "no.tidex.max": "max_monthly",
  "no.tidex.max.year": "max_yearly",
};

type Transaction = {
  transactionId: string;
  originalTransactionId: string;
  productId: string;
  purchaseDate?: number;
  expiresDate?: number;
  revocationDate?: number;
  environment: string;
  appAccountToken?: string;
  offerType?: number;
  type: string;
};
type Renewal = { autoRenewStatus?: number };

/** determineStatusFromNotification */
export function subscriptionStatus(type: string, subtype: string | null, tx: Transaction | null, renewal: Renewal | null) {
  const active = (cancelAtPeriodEnd = false) => ({
    status: tx?.offerType === 1 && tx.expiresDate !== undefined && tx.expiresDate > Date.now() ? "trialing" : "active",
    cancelAtPeriodEnd,
  });
  switch (type) {
    case "SUBSCRIBED":
    case "DID_RENEW":
    case "REFUND_REVERSED":
    case "RENEWAL_EXTENDED":
    case "RENEWAL_EXTENSION":
    case "OFFER_REDEEMED":
      return active(false);
    case "DID_FAIL_TO_RENEW":
      return { status: subtype === "GRACE_PERIOD" ? "grace" : "past_due", cancelAtPeriodEnd: false };
    case "DID_CHANGE_RENEWAL_STATUS":
      if (subtype === "AUTO_RENEW_DISABLED") return active(true);
      if (subtype === "AUTO_RENEW_ENABLED") return active(false);
      return active(renewal?.autoRenewStatus === 0);
    case "EXPIRED":
      if (subtype === "VOLUNTARY") return { status: "canceled", cancelAtPeriodEnd: true };
      if (subtype === "BILLING_RETRY" || subtype === "PRICE_INCREASE") return { status: "expired", cancelAtPeriodEnd: false };
      return { status: "expired", cancelAtPeriodEnd: true };
    case "GRACE_PERIOD_EXPIRED":
      return { status: "expired", cancelAtPeriodEnd: false };
    case "REFUND":
    case "REVOKE":
      return { status: "refunded", cancelAtPeriodEnd: false };
    case "DID_CHANGE_RENEWAL_PREF":
      return active(renewal?.autoRenewStatus === 0);
    case "TEST":
      return { status: "active", cancelAtPeriodEnd: false };
    default:
      if (tx?.revocationDate !== undefined) return { status: "refunded", cancelAtPeriodEnd: false };
      if (tx?.expiresDate !== undefined && tx.expiresDate < Date.now()) return { status: "expired", cancelAtPeriodEnd: true };
      return active(renewal?.autoRenewStatus === 0);
  }
}

const reply = (status: number, body: Record<string, unknown>) => ({ status, body });

async function notificationRow(ctx: MutationCtx, id: string) {
  return await ctx.db
    .query("apple_notifications")
    .withIndex("by_uuid", (q) => q.eq("id", id))
    .unique();
}

/** Applies a verified notification. Returns the HTTP status and body for Apple. */
export const apply = internalMutation({
  args: { notification: v.any(), transactionInfo: v.any(), renewalInfo: v.any() },
  handler: async (ctx, args) => {
    const n = args.notification as {
      notificationType: string;
      subtype?: string;
      notificationUUID: string;
      data?: { environment?: string };
    };
    const tx = args.transactionInfo as Transaction | null;
    const renewal = args.renewalInfo as Renewal | null;
    const subtype = n.subtype ?? null;
    const now = new Date().toISOString();

    // Seen before: skip only if an earlier delivery finished. Otherwise Apple is retrying.
    let row = await notificationRow(ctx, n.notificationUUID);
    if (row?.processed_at !== undefined) return reply(200, { received: true, duplicate: true });
    if (row === null) {
      await ctx.db.insert("apple_notifications", {
        id: n.notificationUUID,
        notification_type: n.notificationType,
        subtype: subtype ?? undefined,
        original_transaction_id: tx?.originalTransactionId,
        transaction_id: tx?.transactionId,
        received_at: now,
        attempts: 0,
        raw_payload: { notification: n, signedPayload: "[redacted]" },
      });
      row = (await notificationRow(ctx, n.notificationUUID))!;
    }
    const processed = async () => await ctx.db.patch(row!._id, { processed_at: new Date().toISOString() });
    const failed = async (error: string) => await ctx.db.patch(row!._id, { last_error: error, attempts: row!.attempts + 1 });

    if (n.notificationType === "TEST") {
      await processed();
      return reply(200, { received: true });
    }
    if (tx === null) {
      await failed("No transaction info");
      return reply(200, { received: true, warning: "No transaction info" });
    }
    // Sandbox and TestFlight purchases must not write production rows.
    if (n.data?.environment !== "Production" || tx.environment !== "Production") {
      await processed();
      return reply(200, { received: true, ignored: "non-production" });
    }
    if (tx.type !== "Auto-Renewable Subscription") {
      await processed();
      return reply(200, { received: true, ignored: "not a subscription" });
    }

    const { status, cancelAtPeriodEnd } = subscriptionStatus(n.notificationType, subtype, tx, renewal);
    const existing = await ctx.db
      .query("subscriptions")
      .withIndex("by_apple_original_transaction_id", (q) => q.eq("apple_original_transaction_id", tx.originalTransactionId))
      .first();
    const tokenUser =
      tx.appAccountToken === undefined
        ? undefined
        : (
            await ctx.db
              .query("app_account_tokens")
              .withIndex("by_token", (q) => q.eq("token", tx.appAccountToken!))
              .unique()
          )?.user_id;
    if (existing !== null && tokenUser !== undefined && tokenUser !== existing.user_id) {
      await failed("Apple transaction belongs to a different user");
      return reply(500, { received: true, processed: false });
    }
    const userId = existing?.user_id ?? tokenUser;
    if (userId === undefined) {
      await ctx.db.insert("apple_orphan_notifications", {
        id: `${tx.transactionId}_${Date.now()}`,
        notification_type: n.notificationType,
        subtype: subtype ?? undefined,
        original_transaction_id: tx.originalTransactionId,
        app_account_token: tx.appAccountToken,
        received_at: now,
        raw_payload: { transactionInfo: tx, renewalInfo: renewal, receivedAt: now },
      });
      await processed();
      return reply(200, { received: true, processed: true });
    }

    const fields = {
      user_id: userId,
      provider: "apple" as const,
      provider_subscription_id: tx.originalTransactionId,
      status: status as "active",
      product_id: PRODUCTS[tx.productId] ?? tx.productId,
      current_period_start: tx.purchaseDate === undefined ? undefined : new Date(tx.purchaseDate).toISOString(),
      current_period_end: tx.expiresDate === undefined ? undefined : new Date(tx.expiresDate).toISOString(),
      apple_original_transaction_id: tx.originalTransactionId,
      apple_last_transaction_id: tx.transactionId,
      apple_environment: tx.environment as "Production",
      app_account_token: tx.appAccountToken,
      cancel_at_period_end: cancelAtPeriodEnd,
      canceled_at: cancelAtPeriodEnd ? now : undefined,
      raw_provider_payload: { lastNotification: n.notificationType, lastSubtype: subtype, transactionInfo: tx, renewalInfo: renewal, processedAt: now },
      updated_at: now,
      revision: await nextRevision(ctx),
    };
    const target =
      existing ??
      (
        await ctx.db
          .query("subscriptions")
          .withIndex("by_user", (q) => q.eq("user_id", userId))
          .collect()
      )[0] ??
      null;
    if (target === null) {
      await ctx.db.insert("subscriptions", { id: crypto.randomUUID(), created_at: now, ...fields });
    } else if (target.provider === "apple") {
      await ctx.db.patch(target._id, fields);
    }
    // A Stripe or admin-granted row stays untouched, and Apple is told not to retry.
    await processed();
    return reply(200, { received: true, processed: true });
  },
});
