'use server';

import Stripe from 'stripe';
import { createSupabaseServerClient } from '@/lib/supabase/server';
import { logger } from '@/lib/logger';

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, {
  apiVersion: '2025-09-30.clover',
});

interface PortalSessionResult {
  success: boolean;
  url?: string;
  error?: string;
}

export async function createPortalSession(): Promise<PortalSessionResult> {
  try {
    // Get authenticated user
    const supabase = await createSupabaseServerClient();
    const { data: { user }, error: authError } = await supabase.auth.getUser();

    if (authError || !user) {
      logger.error('User not authenticated', authError);
      return { success: false, error: 'Du må være logget inn' };
    }

    // Get user's subscription to find their Stripe customer ID
    const { data: subscription, error: subError } = await supabase
      .from('subscriptions')
      .select('stripe_customer_id')
      .eq('user_id', user.id)
      .single();

    if (subError || !subscription?.stripe_customer_id) {
      logger.error('No subscription found for user', subError);
      return { success: false, error: 'Kunne ikke finne abonnementsinformasjon' };
    }

    // Build return URL
    const baseUrl = process.env.NEXT_PUBLIC_APP_BASE_URL || 'http://localhost:3000';
    const returnUrl = `${baseUrl}/settings/subscription`;

    // Create Stripe customer portal session
    const session = await stripe.billingPortal.sessions.create({
      customer: subscription.stripe_customer_id,
      return_url: returnUrl,
    });

    if (!session.url) {
      logger.error('Portal session created but no URL returned');
      return { success: false, error: 'Kunne ikke opprette portalsesjon' };
    }

    return { success: true, url: session.url };
  } catch (error) {
    logger.error('Error creating portal session:', error);
    return {
      success: false,
      error: error instanceof Error ? error.message : 'En ukjent feil oppstod'
    };
  }
}
