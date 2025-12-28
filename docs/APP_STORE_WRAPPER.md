# App Store Wrapper Configuration

## External URL Allowlist

The following external domains must be added to your app wrapper's navigation allowlist:

```
checkout.stripe.com
billing.stripe.com
```

## OAuth Deep Links

Add these redirect URIs to your OAuth providers:

### Supabase Dashboard (Authentication > URL Configuration)

```
[YOUR_APP_SCHEME]://auth/callback
```

### Google Cloud Console

```
[YOUR_APP_SCHEME]://auth/callback
```

### Apple Developer Portal

```
[YOUR_APP_SCHEME]://auth/callback
```

## App Scheme

Replace `[YOUR_APP_SCHEME]` with your registered scheme:

```
Scheme: ___________________
Example: com.tidex.app
```

## Testing Checklist

- [ ] Google OAuth login → redirect back to app
- [ ] Apple OAuth login → redirect back to app
- [ ] Stripe checkout → payment → success redirect
- [ ] App backgrounding → resume → session valid
- [ ] Offline → shows offline page → reconnect → auto-reload
