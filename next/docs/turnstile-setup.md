# Turnstile CAPTCHA Setup Guide

This guide explains how to set up Cloudflare Turnstile CAPTCHA for authentication routes in this Next.js application.

## Overview

Turnstile CAPTCHA has been integrated into all authentication routes to prevent automated abuse:

- [Login page](<../app/(auth)/login/LoginClient.tsx>) - Email/phone/OAuth login
- [Signup page](<../app/(auth)/signup/page.tsx>) - User registration
- [Reset Password page](<../app/(auth)/reset-password/page.tsx>) - Password recovery

## Prerequisites

- A Cloudflare account
- Access to your Supabase project dashboard

## Setup Steps

### 1. Create Turnstile Site

1. Visit the [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Navigate to **Turnstile** in the sidebar
3. Click **Add Site**
4. Configure your site:

   - **Site name**: Choose a descriptive name (e.g., "Production Auth" or "Development Auth")
   - **Domain**: Add your production domain (e.g., `tidex.dev`)
   - For local development, add `localhost` to the domain allowlist
   - **Widget Mode**: Choose "Managed" (recommended) or "Non-interactive"
   - **Theme**: Dark (matches your auth pages)

5. Click **Create** and note down:
   - **Site Key** (public) - Used in your frontend code
   - **Secret Key** (private) - Used in Supabase

### 2. Configure Supabase

1. Open your [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your project
3. Navigate to **Authentication** → **Settings**
4. Scroll to **Bot and Abuse Protection**
5. Enable **CAPTCHA Protection**
6. Select **Turnstile** as the provider
7. Paste your **Secret Key** from step 1
8. Click **Save**

### 3. Configure Environment Variables

Add the Turnstile site key to your environment variables:

#### Development (`.env.local`)

```bash
NEXT_PUBLIC_TURNSTILE_SITE_KEY=your_site_key_here
```

#### Production

Add the environment variable to your hosting platform:

- **Vercel**: Project Settings → Environment Variables
- **Netlify**: Site Settings → Build & Deploy → Environment
- **Other platforms**: Add `NEXT_PUBLIC_TURNSTILE_SITE_KEY` to your deployment configuration

### 4. Verify Setup

1. Start your development server:

   ```bash
   npm run dev
   ```

2. Navigate to `http://localhost:3000/login`
3. You should see the Turnstile widget appear below the password field
4. The widget should automatically verify (in managed mode) or require interaction
5. Try submitting the form:
   - ✅ **With captcha**: Form submits successfully
   - ❌ **Without captcha**: Error message appears

## Local Testing

To test Turnstile locally:

1. Ensure `localhost` is in your Turnstile domain allowlist (Cloudflare Dashboard → Turnstile → Your Site → Settings)
2. Use a real site key - Turnstile does not provide test keys like reCAPTCHA
3. The widget will work on `localhost:3000` if properly configured

## Implementation Details

### Component Structure

The integration follows the project's two-tier component architecture:

1. **Wrapper Component**: [TurnstileCaptcha.tsx](../components/app/TurnstileCaptcha.tsx)

   - Lives in `components/app/` (app-specific wrapper)
   - Uses `@marsidev/react-turnstile` package
   - Configured with dark theme to match auth pages
   - Handles success/error callbacks

2. **Integration**: Used in all auth forms
   - Captcha token stored in component state
   - Token passed to Supabase auth methods via `options.captchaToken`
   - Submit buttons disabled until captcha is completed

### Auth Methods with Captcha

All Supabase auth calls include the captcha token:

```typescript
// Login - Email/Password
await supabase.auth.signInWithPassword({
  email,
  password,
  options: { captchaToken },
});

// Login - Phone OTP
await supabase.auth.signInWithOtp({
  phone,
  options: { captchaToken },
});

// Signup - Email
await supabase.auth.signUp({
  email,
  password,
  options: {
    data: { first_name },
    captchaToken,
  },
});

// Reset Password - Email
await supabase.auth.resetPasswordForEmail(email, {
  captchaToken,
});
```

### User Experience

- Widget appears automatically in auth forms
- In "Managed" mode, verification happens in the background
- Submit buttons are disabled until captcha completes
- Error messages appear if captcha fails or is not completed
- Widget resets on form field changes for security

## Troubleshooting

### Widget Not Appearing

1. **Check environment variable**: Ensure `NEXT_PUBLIC_TURNSTILE_SITE_KEY` is set
2. **Restart dev server**: Environment variables require restart to take effect
3. **Check browser console**: Look for Turnstile errors
4. **Verify domain**: Ensure your domain is in the Cloudflare allowlist

### "Invalid Site Key" Error

- Site key must match the domain you're accessing
- For localhost, ensure `localhost` is in your Turnstile domain allowlist
- Site key must be for the correct Cloudflare account

### Captcha Succeeds but Login Fails

1. **Check Supabase configuration**: Verify secret key is entered correctly
2. **Check Supabase logs**: Authentication → Logs for captcha verification errors
3. **Verify captcha is enabled**: Settings → Authentication → Bot Protection

### Form Submits Before Captcha Completes

This shouldn't happen - the submit button is disabled until `captchaToken` is set. If it does:

1. Check the component state management
2. Ensure `disabled={isSubmitting || !captchaToken}` is on the button
3. Check browser console for React errors

## Security Considerations

1. **Never commit the secret key** - Only the site key goes in `.env.local`
2. **Use separate keys for dev/prod** - Create different Turnstile sites for each environment
3. **Rotate keys if compromised** - Generate new keys in Cloudflare and update Supabase
4. **Monitor Turnstile analytics** - Check for unusual patterns in your Cloudflare dashboard

## Further Configuration

### Widget Appearance

Modify [TurnstileCaptcha.tsx](../components/app/TurnstileCaptcha.tsx) to customize:

```typescript
options={{
  theme: "dark",        // "light" | "dark" | "auto"
  size: "normal",       // "normal" | "compact"
  action: "login",      // Optional action identifier
  tabindex: 0,          // Tab order
}}
```

### Different Keys per Route

To use different Turnstile sites for different routes:

1. Create multiple sites in Cloudflare
2. Add environment variables: `NEXT_PUBLIC_TURNSTILE_LOGIN_KEY`, `NEXT_PUBLIC_TURNSTILE_SIGNUP_KEY`
3. Update [env.ts](../lib/env.ts) to export all keys
4. Pass the appropriate key to `TurnstileCaptcha` component via props

## Resources

- [Cloudflare Turnstile Documentation](https://developers.cloudflare.com/turnstile/)
- [Supabase Captcha Protection](https://supabase.com/docs/guides/auth/auth-captcha)
- [@marsidev/react-turnstile Package](https://github.com/marsidev/react-turnstile)
- [Project CLAUDE.md](../CLAUDE.md) - Architecture overview

## Support

If you encounter issues:

1. Check the [Troubleshooting](#troubleshooting) section above
2. Review Cloudflare Turnstile logs in your dashboard
3. Check Supabase authentication logs
4. Ensure environment variables are correctly set
