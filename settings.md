OS Settings Implementation Reference
Settings Menu Navigation
SettingsNav.tsx: components/settings/SettingsNav.tsx - Menu items, icons, and routing logic
Translations
English: lib/i18n/dictionaries/en.ts:782 - settings object
Norwegian: lib/i18n/dictionaries/no.ts:781 - settings object
Individual Settings Pages
Setting	Page	Components	Server Actions
Account	settings/profile/page.tsx	ProfileForm, EmailChangeCard, PasswordCard, DangerZone	-
Security	settings/security/page.tsx	GoogleConnectionCard, AppleConnectionCard, PhoneConnectionCard	-
Subscription	settings/subscription/page.tsx	SubscriptionStatus, UpgradeOptions, AppleIAPUpgradeOptions	createCheckoutSession, createPortalSession
Notifications	settings/notifications/page.tsx	NotificationSettingsForm	-
Appearance	settings/display/page.tsx	DisplayForm, CurrencySelector	-
Pay & Supplements	settings/pay/page.tsx	PayForm, WageSourceCard, SupplementsEditor, WageHistoryTimeline	updateSettings
Data Export	settings/data/page.tsx	DataForm	-
Feedback	settings/feedback/page.tsx	FeedbackForm, FeedbackHistory	submitFeedback
Admin	settings/admin/page.tsx	AdminDashboard, UserListCard, FeedbackCard, SendNotificationCard	getUserList, sendBroadcastNotification
Data Access Layer (DAL)
Settings: data-access/settings.ts - getUserSettings()
Auth/Profile: data-access/auth.ts - verifySession(), getSession()
Subscription: data-access/subscription.ts - getUserSubscriptionData()
iOS-Specific Notes
Subscription: Use StoreKit for iOS instead of Stripe checkout
Notifications: iOS uses native push notification permissions (already have NotificationService.swift)
Appearance: iOS uses system dark mode detection + manual override