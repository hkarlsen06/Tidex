# Apple In-App Purchase Setup Runbook

This document provides step-by-step instructions for configuring Apple In-App Purchases for Tidex.

## Prerequisites

- Apple Developer Account with App Store Connect access
- The iOS app is already configured with bundle ID: `no.tidex.app`
- Team ID: `48ZSLD4RMP`

---

## 1. App Store Connect: Create Subscription Products

### Navigate to Subscriptions
1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. Select your app (Tidex)
3. Go to **Features** → **In-App Purchases** → **Subscriptions**

### Create a Subscription Group
1. Click **+ Create** to create a new subscription group
2. Name: `Tidex Pro`
3. Reference Name: `tidex_pro_group`

### Create Subscription Products

Create the following subscription products within the group:

| Reference Name | Product ID | Duration | Price Tier |
|---------------|-----------|----------|------------|
| Pro Monthly | `no.tidex.pro.monthly` | 1 Month | Choose appropriate tier |
| Pro Yearly | `no.tidex.pro.yearly` | 1 Year | Choose appropriate tier |
| Storage Monthly | `no.tidex.storage.monthly` | 1 Month | Choose appropriate tier |
| Storage Yearly | `no.tidex.storage.yearly` | 1 Year | Choose appropriate tier |

For each product:
1. Set the **Subscription Duration**
2. Set **Subscription Prices** for all territories
3. Add **Localization** (display name, description) for Norwegian and English
4. Submit for review when ready

---

## 2. App Store Connect: Configure Server Notifications

### Enable App Store Server Notifications V2

1. In App Store Connect, go to your app
2. Navigate to **General** → **App Information**
3. Scroll to **App Store Server Notifications**
4. Set **URL for App Store Server Notifications**:
   ```
   https://<YOUR_SUPABASE_PROJECT_REF>.supabase.co/functions/v1/apple-server-notifications
   ```
5. Select **Version 2 Notifications** (required for this implementation)
6. Save changes

### Get Your Supabase Project Reference
Your Supabase project reference can be found in your Supabase dashboard URL:
`https://supabase.com/dashboard/project/<PROJECT_REF>`

---

## 3. Create App Store Connect API Key

This key is needed for server-to-server API calls (transaction verification).

### Generate API Key

1. Go to **Users and Access** in App Store Connect
2. Select **Keys** tab → **App Store Connect API** subtab
3. Click **+** to generate a new key
4. Name: `Tidex Server API`
5. Access: **Admin** (or at minimum, access to your app)
6. Download the key (.p8 file) - **SAVE THIS SECURELY, IT CAN ONLY BE DOWNLOADED ONCE**

### Note the Key Details
After creating the key, note these values:
- **Key ID**: Displayed next to the key name (e.g., `ABC123XYZ`)
- **Issuer ID**: Displayed at the top of the Keys page (e.g., `12345678-1234-1234-1234-123456789012`)

---

## 4. Configure Supabase Secrets

Add the following secrets to your Supabase project:

### Via Supabase Dashboard
1. Go to your Supabase project
2. Navigate to **Settings** → **Edge Functions**
3. Add the following secrets:

| Secret Name | Value | Description |
|-------------|-------|-------------|
| `APPLE_APP_BUNDLE_ID` | `no.tidex.app` | Your iOS app bundle ID |
| `APPLE_TEAM_ID` | `48ZSLD4RMP` | Your Apple Developer Team ID |
| `APPLE_KEY_ID` | `<from step 3>` | The Key ID from App Store Connect |
| `APPLE_ISSUER_ID` | `<from step 3>` | The Issuer ID from App Store Connect |
| `APPLE_PRIVATE_KEY` | `<contents of .p8 file>` | The full private key content |

### Via Supabase CLI
```bash
supabase secrets set APPLE_APP_BUNDLE_ID=no.tidex.app
supabase secrets set APPLE_TEAM_ID=48ZSLD4RMP
supabase secrets set APPLE_KEY_ID=<your-key-id>
supabase secrets set APPLE_ISSUER_ID=<your-issuer-id>
supabase secrets set APPLE_PRIVATE_KEY="$(cat /path/to/AuthKey_XXX.p8)"
```

**Important**: The private key must include the full content including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` headers.

---

## 5. Deploy Edge Functions

Deploy the Apple IAP Edge Functions to Supabase:

```bash
# Deploy purchase verification endpoint
supabase functions deploy apple-verify-purchase

# Deploy server notifications endpoint
supabase functions deploy apple-server-notifications
```

### Verify Deployment
1. Check that both functions are listed in Supabase Dashboard → Edge Functions
2. Verify the functions are using the correct secrets

---

## 6. Install Capacitor IAP Plugin

Add the IAP plugin to your iOS project:

```bash
# Install the native purchases plugin
pnpm add @capgo/native-purchases

# Sync Capacitor
npx cap sync ios
```

### Verify iOS Project Configuration
1. Open the iOS project in Xcode: `npx cap open ios`
2. Verify the bundle ID matches: `no.tidex.app`
3. Verify the Team is set to: `48ZSLD4RMP`
4. Ensure **In-App Purchase** capability is enabled:
   - Select your target → **Signing & Capabilities**
   - Click **+ Capability** → Add **In-App Purchase**

---

## 7. Testing with Sandbox

### Create Sandbox Testers
1. In App Store Connect, go to **Users and Access**
2. Select **Sandbox** tab → **Testers**
3. Create sandbox tester accounts for testing

### Test on Device
1. Sign out of the App Store on your test device
2. Install your app (TestFlight or dev build)
3. When prompted for purchase, use sandbox tester credentials
4. Complete test purchases

### Verify in Debug Page
After a test purchase:
1. Open the app and go to Settings → Subscription → Debug
2. Verify the subscription record shows:
   - Provider: `apple`
   - Status: `active`
   - Environment: `Sandbox`

---

## 8. Production Checklist

Before going live:

- [ ] All subscription products are approved in App Store Connect
- [ ] Server notification URL is configured and receiving notifications
- [ ] Edge Functions are deployed with production secrets
- [ ] In-App Purchase capability is enabled in Xcode
- [ ] App is submitted for review with IAP enabled
- [ ] Test end-to-end flow with sandbox tester

### Verify Server Notifications
1. Make a sandbox purchase
2. Check Supabase Edge Function logs for `apple-server-notifications`
3. Verify the `apple_notifications` table has received the notification
4. Verify the subscription was updated correctly

---

## Troubleshooting

### "Products not loading"
- Verify product IDs in code match App Store Connect exactly
- Ensure products are "Ready to Submit" or "Approved" status
- Check that you're using the correct bundle ID

### "Purchase verification failed"
- Check Supabase Edge Function logs for errors
- Verify Apple API credentials are set correctly
- Ensure the private key is properly formatted

### "Server notifications not received"
- Verify the notification URL is correct in App Store Connect
- Check that the Edge Function is deployed and accessible
- Look for errors in Supabase Edge Function logs

### "User not entitled after purchase"
- Check the debug page for subscription status
- Verify the `apple_notifications` table for processing errors
- Check `apple_orphan_notifications` for unmatched transactions

---

## Environment Variables Summary

### Supabase Secrets (Edge Functions)
```
APPLE_APP_BUNDLE_ID=no.tidex.app
APPLE_TEAM_ID=48ZSLD4RMP
APPLE_KEY_ID=<your-key-id>
APPLE_ISSUER_ID=<your-issuer-id>
APPLE_PRIVATE_KEY=<your-private-key>
```

### Next.js Environment (already configured)
```
NEXT_PUBLIC_SUPABASE_URL=<your-supabase-url>
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<your-supabase-key>
```

---

## Product ID Reference

| Internal ID | Apple Product ID | Description |
|------------|------------------|-------------|
| `pro_monthly` | `no.tidex.pro.monthly` | Pro plan - Monthly |
| `pro_yearly` | `no.tidex.pro.yearly` | Pro plan - Yearly |
| `storage_plus_monthly` | `no.tidex.storage.monthly` | Storage plan - Monthly |
| `storage_plus_yearly` | `no.tidex.storage.yearly` | Storage plan - Yearly |
