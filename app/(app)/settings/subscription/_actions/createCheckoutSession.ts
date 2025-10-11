'use server';

import Stripe from 'stripe';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import { logger } from '@/lib/logger';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2024-06-20',
});

interface CheckoutSessionResult {
  success: boolean;
  url?: string;
  error?: string;
}

export async function createCheckoutSession(priceId: string): Promise<CheckoutSessionResult> {
  try {
    // Get authenticated user
    const supabase = await createSupabaseServerClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      logger.error('User not authenticated', authError);
      return { success: false, error: 'Du må være logget inn for å oppgradere' };
    }

    // Get user email
    const email = user.email;
    if (!email) {
      logger.error('User has no email');
      return { success: false, error: 'Kunne ikke finne e-postadressen din' };
    }

    // Build success and cancel URLs
    const baseUrl = process.env.NEXT_PUBLIC_APP_BASE_URL || 'http://localhost:3000';
    const successUrl = `${baseUrl}/settings/subscription/success?session_id={CHECKOUT_SESSION_ID}`;
    const cancelUrl = `${baseUrl}/settings/subscription/cancel`;

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
