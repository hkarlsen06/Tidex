// Supabase Edge Function: Stripe Webhook (hardened, typed-lite, fixed period_end)
// - Verifies signature on raw body
// - Idempotency with stripe_events (processed_at, attempts, last_error)
// - Live/Test auto-guard via STRIPE_SECRET_KEY prefix
// - Fetches fresh subscription on sub.* events (ensures current_period_end present)
// - Fallback to item.current_period_end when top-level is missing
// - Broader event coverage incl. paused/resumed/expired
// - Trusts metadata.supabase_uid first, falls back to customer lookup
// - Upserts a single row per user in `subscriptions`
// - Captures cancellation fields: cancel_at_period_end, canceled_at, cancel_at
// - Stores cancellation details: reason, feedback, comment
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import Stripe from "npm:stripe@16.6.0";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
// ---------- Env ----------
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// Auto-detect live/test from the key prefix
const STRIPE_LIVE = STRIPE_SECRET_KEY.startsWith("sk_live_");
// ---------- Clients ----------
const stripe = STRIPE_SECRET_KEY ? new Stripe(STRIPE_SECRET_KEY, {
  apiVersion: "2024-06-20"
}) : null;
const supabase = SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY ? createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: {
    persistSession: false
  }
}) : null;
// ---------- Server ----------
serve(async (req)=>{
  try {
    if (req.method !== "POST") return res("Method Not Allowed", 405);
    if (!STRIPE_WEBHOOK_SECRET) return res("Webhook not configured", 503);
    if (!stripe || !supabase) return res("Dependencies not configured", 503);
    const sig = req.headers.get("stripe-signature");
    if (!sig) return res("Missing Stripe signature", 400);
    const raw = await req.text();
    let event;
    try {
      event = await stripe.webhooks.constructEventAsync(raw, sig, STRIPE_WEBHOOK_SECRET);
    } catch (err) {
      return res(`Webhook Error: ${err instanceof Error ? err.message : String(err)}`, 400);
    }
    // Live/Test guard
    if (typeof event.livemode === "boolean" && event.livemode !== STRIPE_LIVE) {
      return json({
        ignored: true,
        reason: "wrong mode",
        id: event.id,
        type: event.type
      });
    }
    // Idempotency: mark seen
    const marked = await markEventSeen(event.id, event.type);
    if (!marked.ok) {
      if (marked.code === "23505") {
        // Event already exists
        return json({
          received: false,
          id: event.id,
          error: "duplicate_event"
        }, 409); // HTTP 409 Conflict
      }
      console.warn("[stripe-webhook] markEventSeen failed, proceeding:", marked.error);
    }
    try {
      await handleEvent(event);
      await markEventDone(event.id);
      return json({
        received: true,
        id: event.id,
        type: event.type
      });
    } catch (err) {
      await markEventError(event.id, err instanceof Error ? err.message : String(err));
      // Return 200 to avoid infinite retries from Stripe unless you prefer retries (then use 500).
      return json({
        received: false,
        id: event.id,
        error: "handler_failed"
      }, 200);
    }
  } catch (e) {
    console.error("[stripe-webhook] exception:", e instanceof Error ? e.message : e);
    return res("Internal Error", 500);
  }
});
// ---------- Idempotency helpers ----------
async function markEventSeen(id, type) {
  try {
    const { error } = await supabase.from("stripe_events").insert({
      id,
      type
    });
    if (error) return {
      ok: false,
      code: error.code ?? null,
      error
    };
    return {
      ok: true
    };
  } catch (e) {
    return {
      ok: false,
      code: null,
      error: e
    };
  }
}
async function markEventDone(id) {
  try {
    await supabase.from("stripe_events").update({
      processed_at: new Date().toISOString(),
      last_error: null
    }).eq("id", id);
  } catch (e) {
    console.warn("[stripe-webhook] markEventDone failed:", e instanceof Error ? e.message : e);
  }
}
async function markEventError(id, msg) {
  try {
    // Read attempts, then increment (simple; can be replaced by RPC for atomicity)
    const { data, error } = await supabase.from("stripe_events").select("attempts").eq("id", id).single();
    const attempts = typeof data?.attempts === "number" ? data.attempts + 1 : 1;
    const { error: updErr } = await supabase.from("stripe_events").update({
      last_error: msg,
      attempts
    }).eq("id", id);
    if (error) console.warn("[stripe-webhook] markEventError select failed:", error.message);
    if (updErr) console.warn("[stripe-webhook] markEventError update failed:", updErr.message);
  } catch (e) {
    console.warn("[stripe-webhook] markEventError failed:", e instanceof Error ? e.message : e);
  }
}
// ---------- Event handler ----------
async function handleEvent(event) {
  const type = event.type;
  switch(type){
    case "checkout.session.expired":
      return;
    case "checkout.session.completed":
    case "checkout.session.async_payment_succeeded":
    case "checkout.session.async_payment_failed":
      {
        const session = event.data.object;
        const uid = session?.metadata?.supabase_uid ?? null;
        const customerId = asId(session.customer);
        const subscriptionId = asId(session.subscription);
        const resolvedUid = uid ?? (customerId ? await uidFromCustomer(customerId) : null);
        if (!resolvedUid) {
          console.warn(`[webhook] ${type} missing uid; customer=${customerId ?? "null"}`);
          return;
        }
        if (customerId) await upsertCustomerMapping(resolvedUid, customerId);
        if (subscriptionId) {
          const sub = await safeRetrieveSubscription(subscriptionId);
          if (sub) await upsertSubscription(resolvedUid, asId(sub.customer), sub);
        }
        return;
      }
    case "customer.subscription.created":
    case "customer.subscription.updated":
    case "customer.subscription.deleted":
    case "customer.subscription.paused":
    case "customer.subscription.resumed":
      {
        // Get the raw subscription from the webhook event
        const rawSub = event.data.object;
        
        // Hent alltid fersk subscription for å sikre current_period_end er korrekt
        const sub = await safeRetrieveSubscription(rawSub.id) ?? rawSub;
        
        // Set cancellation fields for active subscriptions being cancelled
        if (type === "customer.subscription.updated" && 
            sub.status === "active" && 
            (sub.cancel_at_period_end === true || sub.cancel_at != null)) {
          // Set canceled_at if not already set
          sub.canceled_at = sub.canceled_at || Math.floor(Date.now() / 1000);
          sub.cancel_at_period_end = true; // Ensure this is set
        }
        
        const customerId = asId(sub.customer);
        const uid = sub?.metadata?.supabase_uid ?? (customerId ? await uidFromCustomer(customerId) : null);
        if (!uid) {
          console.warn(`[webhook] ${type} missing uid; customer=${customerId ?? "null"}`);
          return;
        }
        if (customerId) await upsertCustomerMapping(uid, customerId);
        await upsertSubscription(uid, customerId, sub);
        return;
      }
    case "invoice.paid":
    case "invoice.payment_failed":
      {
        const inv = event.data.object;
        const subId = asId(inv.subscription);
        if (!subId) return;
        const sub = await safeRetrieveSubscription(subId);
        if (!sub) return;
        const customerId = asId(sub.customer);
        const uid = sub?.metadata?.supabase_uid ?? (customerId ? await uidFromCustomer(customerId) : null);
        if (!uid) return;
        if (customerId) await upsertCustomerMapping(uid, customerId);
        await upsertSubscription(uid, customerId, sub);
        return;
      }
    case "customer.created":
    case "customer.updated":
    case "customer.deleted":
      {
        const cust = event.data.object;
        const meta = cust?.metadata ?? {};
        const uid = meta.supabase_uid ?? meta.user_id ?? null;
        const customerId = cust?.id ?? null;
        if (uid && customerId && type !== "customer.deleted") {
          await upsertCustomerMapping(uid, customerId);
        }
        return;
      }
    default:
      return;
  }
}
// ---------- Utilities ----------
function asId(x) {
  if (!x) return null;
  if (typeof x === "string") return x;
  if (typeof x === "object" && x && "id" in x && typeof x.id === "string") {
    return x.id;
  }
  return null;
}
async function uidFromCustomer(customerId) {
  try {
    if (!stripe) return null;
    const cust = await stripe.customers.retrieve(customerId);
    const meta = cust.metadata ?? {};
    return meta.supabase_uid ?? meta.user_id ?? null;
  } catch (e) {
    console.warn(`[webhook] fetch customer ${customerId} failed:`, e instanceof Error ? e.message : e);
    return null;
  }
}
async function safeRetrieveSubscription(id) {
  try {
    if (!stripe) return null;
    return await stripe.subscriptions.retrieve(id, {
      expand: [
        "items.data.price",
        "latest_invoice.payment_intent"
      ]
    });
  } catch  {
    return null;
  }
}
// Upsert a single row per user in `subscriptions`
async function upsertCustomerMapping(userId, customerId) {
  const { error } = await supabase.from("subscriptions").upsert({
    user_id: userId,
    stripe_customer_id: customerId
  }, {
    onConflict: "user_id"
  });
  if (error) console.warn("[webhook] mapping upsert failed:", error.message);
}
async function upsertSubscription(userId, customerId, sub) {
  const status = sub.status; // 'active' | 'trialing' | 'past_due' | 'canceled' | 'incomplete' | 'paused' | etc.
  
  // Finn riktig period end:
  // 1) Top-nivå current_period_end hvis satt
  // 2) Fallback: første subscription_item.current_period_end
  const periodEndUnix = sub.current_period_end ?? sub.items?.data?.[0]?.current_period_end ?? null;
  const periodEndISO = periodEndUnix ? new Date(periodEndUnix * 1000).toISOString() : null;
  const priceId = sub.items?.data?.[0]?.price?.id ?? null;

  // Cancellation fields
  const cancelAtPeriodEnd = sub.cancel_at_period_end ?? false;
  const canceledAtUnix = sub.canceled_at ?? null;
  const canceledAtISO = canceledAtUnix ? new Date(canceledAtUnix * 1000).toISOString() : null;
  const cancelAtUnix = sub.cancel_at ?? null;
  const cancelAtISO = cancelAtUnix ? new Date(cancelAtUnix * 1000).toISOString() : null;

  // Cancellation details
  const cancellationDetails = sub.cancellation_details ?? null;
  const cancellationReason = cancellationDetails?.reason ?? null;
  const cancellationFeedback = cancellationDetails?.feedback ?? null;
  const cancellationComment = cancellationDetails?.comment ?? null;

  // Typed-løst for enkelhet og kompatibilitet med supabase-js
  const payload = {
    user_id: userId,
    stripe_customer_id: customerId ?? null,
    stripe_subscription_id: sub.id,
    status,
    current_period_end: periodEndISO,
    cancel_at_period_end: cancelAtPeriodEnd,
    canceled_at: canceledAtISO,
    cancel_at: cancelAtISO,
    cancellation_reason: cancellationReason,
    cancellation_feedback: cancellationFeedback,
    cancellation_comment: cancellationComment,
    ...priceId ? {
      price_id: priceId
    } : {}
  };
  const upsertStatuses = [
    "active",
    "trialing",
    "past_due",
    "incomplete",
    "paused"
  ];
  const endStatuses = [
    "canceled",
    "incomplete_expired",
    "unpaid"
  ];
  if (upsertStatuses.includes(status)) {
    const { error } = await supabase.from("subscriptions").upsert(payload, {
      onConflict: "user_id"
    });
    if (error) console.error("[webhook] subscription upsert failed:", error.message);
  } else if (endStatuses.includes(status)) {
    const { error } = await supabase.from("subscriptions").update({
      status,
      current_period_end: periodEndISO,
      price_id: priceId ?? null,
      cancel_at_period_end: cancelAtPeriodEnd,
      canceled_at: canceledAtISO,
      cancel_at: cancelAtISO,
      cancellation_reason: cancellationReason,
      cancellation_feedback: cancellationFeedback,
      cancellation_comment: cancellationComment
    }).eq("user_id", userId);
    if (error) console.error("[webhook] subscription update failed:", error.message);
  } else {
    const { error } = await supabase.from("subscriptions").upsert(payload, {
      onConflict: "user_id"
    });
    if (error) console.error("[webhook] subscription upsert(fallback) failed:", error.message);
  }
}
// ---------- Response helpers ----------
function res(body, status = 200, headers = {}) {
  return new Response(body, {
    status,
    headers
  });
}
function json(obj, status = 200) {
  return res(JSON.stringify(obj), status, {
    "Content-Type": "application/json"
  });
}
