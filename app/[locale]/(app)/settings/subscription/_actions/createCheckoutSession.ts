'use server';

import Stripe from 'stripe';
import { cookies } from 'next/headers';
import { logger } from '@/lib/logger';
import { verifySession } from '@/data-access/auth';
import { enforceNotImpersonating } from '@/lib/auth/impersonation';
import { LOCALE_COOKIE, defaultLocale } from '@/lib/i18n/config';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2025-10-29.clover',
});

interface CheckoutSessionResult {
  success: boolean;
  url?: string;
  error?: string;
}

export async function createCheckoutSession(priceId: string): Promise<CheckoutSessionResult> {
  try {
    // Block subscription changes while impersonating
    await enforceNotImpersonating('update_subscription');

    const { user } = await verifySession();

    // Get user email
    const email = user.email;
    if (!email) {
      logger.error('User has no email');
      return { success: false, error: 'Kunne ikke finne e-postadressen din' };
    }

    // Get user's locale from cookie or user metadata
    const cookieStore = await cookies();
    const locale = cookieStore.get(LOCALE_COOKIE)?.value
      || user.user_metadata?.locale
      || defaultLocale;

    // Build success and cancel URLs with locale prefix
    const baseUrl = process.env.NEXT_PUBLIC_APP_BASE_URL || 'http://localhost:3000';
    const successUrl = `${baseUrl}/${locale}/settings/subscription/success?session_id={CHECKOUT_SESSION_ID}`;
    const cancelUrl = `${baseUrl}/${locale}/settings/subscription/cancel`;

    // Create Stripe checkout session
    const session = await stripe.checkout.sessions.create({
      mode: 'subscription',
      payment_method_types: ['card'],
      customer_email: email,
      line_items: [
        {
          price: priceId,
          quantity: 1,
        },
      ],
      // CRITICAL: Pass Supabase user ID in metadata for webhook
      metadata: {
        supabase_uid: user.id,
      },
      subscription_data: {
        // Also include metadata on the subscription itself
        metadata: {
          supabase_uid: user.id,
        },
      },
      success_url: successUrl,
      cancel_url: cancelUrl,
    });

    if (!session.url) {
      logger.error('Stripe session created but no URL returned');
      return { success: false, error: 'Kunne ikke opprette checkout-sesjon' };
    }

    return { success: true, url: session.url };
  } catch (error) {
    logger.error('Error creating checkout session:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'En ukjent feil oppstod'
    };
  }
}
