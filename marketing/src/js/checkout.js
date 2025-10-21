import { supabase } from '../../../app/src/supabase-client.js'
import { API_BASE } from './apiBase.js'

/**
 * Start a Stripe Checkout flow for a given price.
 *
 * Usage:
 *   import { startCheckout } from '/src/js/checkout.js'
 *   await startCheckout('price_123', { mode: 'subscription', quantity: 1 })
 *
 * Notes:
 * - This function obtains the Supabase JWT and sends it as Bearer auth.
 * - Do NOT pass userId from the client; the server derives it from the token.
 * - Defaults: mode='subscription', quantity=1
 *
 * @param {string} priceId - Stripe Price ID
 * @param {{ mode?: 'subscription'|'payment', quantity?: number, redirect?: boolean }} [opts]
 * @returns {Promise<string>} The Stripe-hosted Checkout URL
 */
export async function startCheckout(priceId, opts = {}) {
  const { mode = 'subscription', quantity = 1, redirect = true } = opts;

  if (!priceId || typeof priceId !== 'string') {
    const err = new Error('Missing priceId');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Klarte ikke å starte betaling: mangler priceId.');
    }
    throw err;
  }

  // Get current session for JWT
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token;
  if (!token) {
    const err = new Error('Not authenticated');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Du må være innlogget for å starte et kjøp.');
    }
    throw err;
  }

  // Call backend to create Checkout session
  let res = await fetch(`${API_BASE}/api/checkout`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    },
    body: JSON.stringify({ priceId, mode, quantity })
  });

  // Some proxies strip /api → backend expects /checkout; retry without /api on 404
  if (res.status === 404) {
    try {
      res = await fetch(`${API_BASE}/checkout`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        },
        body: JSON.stringify({ priceId, mode, quantity })
      });
    } catch (_) { /* fall through to error handling */ }
  }

  if (!res.ok) {
    const text = await safeReadText(res);
    const msg = res.status === 404
      ? 'Kunne ikke starte kjøp (404). Tjenesten er ikke tilgjengelig her. Prøv å oppdatere siden eller kontakt support.'
      : `Kunne ikke starte Stripe Checkout (${res.status}).`;
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError(msg);
    }
    const err = new Error(text || msg);
    err.status = res.status;
    throw err;
  }

  const { url } = await res.json();
  if (!url) {
    const err = new Error('Ugyldig svar fra serveren (mangler url).');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Ugyldig svar fra serveren (mangler url).');
    }
    throw err;
  }

  if (redirect && typeof window !== 'undefined') {
    window.location.href = url;
  }
  return url;
}

/**
 * Open Stripe Billing Portal for the current user.
 * @param {{ redirect?: boolean }} [opts]
 * @returns {Promise<string>} The Stripe Billing Portal URL
 */
export async function startBillingPortal(opts = {}) {
  const { redirect = true } = opts;
  // Get current session for JWT
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token;
  if (!token) {
    const err = new Error('Not authenticated');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Du må være innlogget for å administrere abonnementet.');
    }
    throw err;
  }

  // Call server to create a Billing Portal session
  let res = await fetch(`${API_BASE}/api/stripe/create-portal-session`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${token}`
    }
  });

  // Dev proxy often strips /api; try without /api on 404
  if (res.status === 404) {
    try {
      res = await fetch(`${API_BASE}/stripe/create-portal-session`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${token}`
        }
      });
    } catch (_) { /* fallthrough to error handling below */ }
  }

  if (!res.ok) {
    const text = await safeReadText(res);
    const msg = `Kunne ikke åpne administrasjonssiden (${res.status}).`;
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError(msg);
    }
    const err = new Error(text || msg);
    err.status = res.status;
    throw err;
  }

  const { url } = await res.json();
  if (!url) {
    const err = new Error('Ugyldig svar fra serveren (mangler url).');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Ugyldig svar fra serveren (mangler url).');
    }
    throw err;
  }

  if (redirect && typeof window !== 'undefined') {
    window.location.href = url;
  }
  return url;
}

/**
 * Open Billing Portal deep link to upgrade an existing subscription.
 * Uses flow_data=subscription_update targeting the user's active subscription.
 */
export async function startPortalUpgrade(opts = {}) {
  const { redirect = true } = opts;
  const { data: { session } } = await supabase.auth.getSession();
  const token = session?.access_token;
  if (!token) {
    const err = new Error('Not authenticated');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Du må være innlogget for å oppgradere.');
    }
    throw err;
  }

  let res = await fetch(`${API_BASE}/api/portal/upgrade`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` }
  });
  if (res.status === 404) {
    try {
      res = await fetch(`${API_BASE}/portal/upgrade`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` }
      });
    } catch (_) { /* fall through */ }
  }

  if (!res.ok) {
    const text = await safeReadText(res);
    const msg = res.status === 400 ? 'Ingen aktivt abonnement å oppgradere.' : `Kunne ikke åpne Stripe (${res.status}).`;
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError(msg);
    }
    const err = new Error(text || msg);
    err.status = res.status;
    throw err;
  }

  const { url } = await res.json();
  if (!url) {
    const err = new Error('Ugyldig svar fra serveren (mangler url).');
    if (typeof window !== 'undefined' && window.ErrorHelper) {
      window.ErrorHelper.showError('Ugyldig svar fra serveren (mangler url).');
    }
    throw err;
  }

  if (redirect && typeof window !== 'undefined') {
    window.location.href = url;
  }
  return url;
}

async function safeReadText(res) {
  try { return await res.text(); } catch (_) { return ''; }
}

// Optional: expose on window for easy use in non-module contexts
if (typeof window !== 'undefined') {
  window.startCheckout = startCheckout;
  window.startBillingPortal = startBillingPortal;
  window.startPortalUpgrade = startPortalUpgrade;
}

