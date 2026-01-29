# Admin Impersonation System

This document describes the secure impersonation system that allows admins to "become" another user for support and debugging purposes.

## Overview

The impersonation system provides a platform-agnostic backend primitive via Supabase Edge Function that works for both:
- **Web (Next.js)**: Cookie-based session management
- **iOS (Swift)**: Direct token-based session swap via `setSession`

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Supabase Edge Function                        │
│                  /functions/v1/impersonation                      │
│                                                                   │
│  ┌─────────────────┐         ┌─────────────────┐                │
│  │  POST /start    │         │  POST /stop     │                │
│  │                 │         │                 │                │
│  │ • Auth admin    │         │ • End session   │                │
│  │ • Mint tokens   │         │ • Audit log     │                │
│  │ • Create audit  │         │ • Return token  │                │
│  └─────────────────┘         └─────────────────┘                │
└─────────────────────────────────────────────────────────────────┘
          │                              │
          ▼                              ▼
┌─────────────────────┐      ┌─────────────────────┐
│     Web (Next.js)   │      │     iOS (Swift)     │
│                     │      │                     │
│ • Call Edge Function│      │ • Call Edge Function│
│ • Set session cookie│      │ • Store admin sess  │
│ • Set context cookie│      │   in Keychain       │
│ • Handle via wrapper│      │ • setSession()      │
│   routes            │      │ • Restore from      │
└─────────────────────┘      │   Keychain          │
                             └─────────────────────┘
```

## API Reference

### Start Impersonation

**Endpoint:** `POST /functions/v1/impersonation/start`

**Authentication:** Bearer token (admin's access token)

**Request Body:**
```json
{
  "targetUserId": "uuid",
  "reason": "string (min 5 chars)",
  "adminRefreshToken": "string (optional, for web session storage)"
}
```

**Success Response (200):**
```json
{
  "ok": true,
  "impersonated": {
    "access_token": "eyJhbGciOiJS...",
    "refresh_token": "eyJhbGciOiJS...",
    "expires_in": 3600,
    "token_type": "bearer",
    "user": {
      "id": "uuid",
      "email": "user@example.com",
      "user_metadata": { ... }
    }
  },
  "session": {
    "id": "uuid",
    "admin_user_id": "uuid",
    "target_user_id": "uuid",
    "expires_at": "2025-01-29T12:00:00.000Z"
  }
}
```

**Error Responses:**
- `400`: Invalid request, nested impersonation attempt, can't impersonate self
- `401`: Not authenticated
- `403`: Not an admin, target is an admin
- `404`: Target user not found
- `429`: Rate limit exceeded (10/hour)
- `500`: Server error

### Stop Impersonation

**Endpoint:** `POST /functions/v1/impersonation/stop`

**Authentication:** Bearer token (admin's or impersonated user's access token)

**Request Body:**
```json
{
  "sessionId": "uuid"
}
```

**Success Response (200):**
```json
{
  "ok": true,
  "session": {
    "id": "uuid",
    "ended_at": "2025-01-29T12:30:00.000Z"
  },
  "admin_refresh_token": "eyJhbGciOiJS..." // Only if stored (web flow)
}
```

**Error Responses:**
- `400`: Invalid sessionId, session already ended
- `401`: Not authenticated
- `403`: Not authorized (neither admin nor target)
- `404`: Session not found
- `500`: Server error

## iOS Integration

### Swift Usage

```swift
import Supabase

class ImpersonationManager {
    private let supabase: SupabaseClient
    private let keychain = KeychainHelper.shared

    private let keychainAdminSessionKey = "tidex_admin_session"
    private let keychainImpersonationSessionKey = "tidex_impersonation_session_id"

    // MARK: - Start Impersonation

    func startImpersonation(
        targetUserId: UUID,
        reason: String
    ) async throws -> ImpersonationResult {
        // 1. Get current admin session
        guard let adminSession = try await supabase.auth.session else {
            throw ImpersonationError.notAuthenticated
        }

        // 2. Store admin session in Keychain (for restoration)
        try keychain.save(
            AdminSession(
                accessToken: adminSession.accessToken,
                refreshToken: adminSession.refreshToken,
                userId: adminSession.user.id
            ),
            forKey: keychainAdminSessionKey
        )

        // 3. Call the Edge Function
        let response: ImpersonationStartResponse = try await supabase.functions.invoke(
            "impersonation/start",
            options: FunctionInvokeOptions(
                body: [
                    "targetUserId": targetUserId.uuidString,
                    "reason": reason
                ]
            )
        )

        guard response.ok, let impersonated = response.impersonated else {
            throw ImpersonationError.serverError(response.error ?? "Unknown error")
        }

        // 4. Store impersonation session ID
        try keychain.save(response.session?.id ?? "", forKey: keychainImpersonationSessionKey)

        // 5. Swap to impersonated user's session
        try await supabase.auth.setSession(
            accessToken: impersonated.accessToken,
            refreshToken: impersonated.refreshToken
        )

        return ImpersonationResult(
            sessionId: response.session?.id ?? "",
            targetUser: impersonated.user,
            expiresAt: response.session?.expiresAt
        )
    }

    // MARK: - Stop Impersonation

    func stopImpersonation() async throws {
        // 1. Get stored session ID
        guard let sessionId: String = try keychain.load(forKey: keychainImpersonationSessionKey),
              !sessionId.isEmpty else {
            throw ImpersonationError.noActiveSession
        }

        // 2. Call the Edge Function (optional - for audit logging)
        // Note: iOS doesn't need the admin_refresh_token from response
        // because we stored the full admin session in Keychain
        let currentSession = try await supabase.auth.session
        if let accessToken = currentSession?.accessToken {
            let _: ImpersonationStopResponse = try await supabase.functions.invoke(
                "impersonation/stop",
                options: FunctionInvokeOptions(
                    body: ["sessionId": sessionId]
                )
            )
        }

        // 3. Restore admin session from Keychain
        guard let adminSession: AdminSession = try keychain.load(forKey: keychainAdminSessionKey) else {
            throw ImpersonationError.adminSessionNotFound
        }

        // 4. Swap back to admin session
        try await supabase.auth.setSession(
            accessToken: adminSession.accessToken,
            refreshToken: adminSession.refreshToken
        )

        // 5. Clean up Keychain
        try keychain.delete(forKey: keychainImpersonationSessionKey)
        try keychain.delete(forKey: keychainAdminSessionKey)
    }

    // MARK: - Check Status

    var isImpersonating: Bool {
        guard let sessionId: String = try? keychain.load(forKey: keychainImpersonationSessionKey) else {
            return false
        }
        return !sessionId.isEmpty
    }
}

// MARK: - Models

struct AdminSession: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: UUID
}

struct ImpersonationStartResponse: Decodable {
    let ok: Bool
    let error: String?
    let impersonated: ImpersonatedSession?
    let session: ImpersonationSession?
}

struct ImpersonatedSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String
    let user: ImpersonatedUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case user
    }
}

struct ImpersonatedUser: Decodable {
    let id: UUID
    let email: String?
    let userMetadata: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case email
        case userMetadata = "user_metadata"
    }
}

struct ImpersonationSession: Decodable {
    let id: String
    let adminUserId: UUID
    let targetUserId: UUID
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case adminUserId = "admin_user_id"
        case targetUserId = "target_user_id"
        case expiresAt = "expires_at"
    }
}

struct ImpersonationStopResponse: Decodable {
    let ok: Bool
    let error: String?
    let session: EndedSession?
}

struct EndedSession: Decodable {
    let id: String
    let endedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case endedAt = "ended_at"
    }
}

struct ImpersonationResult {
    let sessionId: String
    let targetUser: ImpersonatedUser
    let expiresAt: Date?
}

enum ImpersonationError: Error {
    case notAuthenticated
    case notAdmin
    case noActiveSession
    case adminSessionNotFound
    case serverError(String)
}
```

### SwiftUI View Integration

```swift
struct AdminImpersonationView: View {
    @StateObject private var viewModel = AdminImpersonationViewModel()
    @State private var showingImpersonationBanner = false

    var body: some View {
        VStack {
            if viewModel.isImpersonating {
                ImpersonationBanner(
                    targetName: viewModel.impersonatedUserName,
                    expiresAt: viewModel.expiresAt,
                    onStop: { Task { await viewModel.stopImpersonation() } }
                )
            }

            // Rest of the admin view...
        }
    }
}

struct ImpersonationBanner: View {
    let targetName: String
    let expiresAt: Date?
    let onStop: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .foregroundStyle(Color.tidexWarning)

            VStack(alignment: .leading) {
                Text("Impersonating: \(targetName)")
                    .font(.headline)
                if let expiresAt {
                    Text("Expires: \(expiresAt, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Stop", action: onStop)
                .buttonStyle(.borderedProminent)
                .tint(.tidexError)
        }
        .padding()
        .background(Color.tidexWarning.opacity(0.1))
        .cornerRadius(8)
    }
}
```

## Web Integration

The web uses Next.js API routes as wrappers:
- `POST /api/admin/impersonation/start` - Calls Edge Function, sets cookies
- `POST /api/admin/impersonation/stop` - Calls Edge Function, restores session

These routes handle:
1. Reading admin's current session
2. Calling the Edge Function
3. Setting the impersonated session cookies
4. Setting the `tidex_imp` context cookie (signed, HttpOnly)
5. Restoring admin session on stop

## Security

### Authentication & Authorization
- Admin role verified via `app_metadata.role === "admin"`
- Cannot impersonate self or other admins
- Nested impersonation blocked (checks if caller is being impersonated)

### Rate Limiting
- Maximum 10 impersonation attempts per hour per admin
- Tracked in `internal.impersonation_rate_limits` table

### Session Security
- Admin refresh token encrypted with AES-256-GCM before storage (web only)
- Context cookie signed with HMAC-SHA256, HttpOnly
- Sessions expire after 30 minutes (max 60 minutes)
- Single active session per admin (unique constraint)

### Audit Trail
- All events logged to `internal.impersonation_audit_log`
- Includes: session_id, admin_user_id, target_user_id, action, reason, IP, User-Agent

### Restricted Actions
While impersonating, these actions are blocked:
- `change_email`, `change_password`
- `enable_mfa`, `disable_mfa`
- `delete_account`
- `update_subscription`, `cancel_subscription`, `restore_subscription`
- `manage_billing`

## Database Schema

### `internal.impersonation_sessions`
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| admin_user_id | uuid | Admin who started impersonation |
| target_user_id | uuid | User being impersonated |
| reason | text | Required reason (min 5 chars) |
| created_at | timestamptz | When session started |
| expires_at | timestamptz | When session expires |
| ended_at | timestamptz | When session ended (null if active) |
| ended_by_admin_user_id | uuid | Who ended it |
| admin_ip | text | Admin's IP address |
| admin_user_agent | text | Admin's browser/device |
| admin_refresh_token_enc | text | Encrypted admin refresh token |

### `internal.impersonation_audit_log`
| Column | Type | Description |
|--------|------|-------------|
| id | uuid | Primary key |
| session_id | uuid | Reference to session |
| admin_user_id | uuid | Admin involved |
| target_user_id | uuid | Target user involved |
| action | text | start, stop, action_blocked, session_expired |
| reason | text | Reason for action |
| admin_ip | text | IP address |
| admin_user_agent | text | Browser/device |
| metadata | jsonb | Additional context |
| created_at | timestamptz | When event occurred |

## Environment Variables

For the Edge Function:
```
SUPABASE_URL           # Automatically set by Supabase
SUPABASE_SERVICE_ROLE_KEY  # Automatically set by Supabase
IMPERSONATION_ENC_KEY  # 64 hex chars (32 bytes) for AES-256
IMPERSONATION_SIGNING_KEY  # 64+ hex chars for HMAC-SHA256
```

## Deployment

Deploy the Edge Function:
```bash
supabase functions deploy impersonation --no-verify-jwt
```

Note: `--no-verify-jwt` is used because the function handles JWT verification internally (extracts user from Bearer token).

## Troubleshooting

### "Rate limit exceeded"
Admin has made 10+ impersonation attempts in the past hour. Wait for the limit to reset.

### "Nested impersonation is not allowed"
The caller is currently being impersonated by another admin. The original admin must stop their session first.

### "Cannot impersonate admin users"
Target user has `role: "admin"` in their app_metadata. Admins cannot impersonate other admins.

### "Admin session expired. Please log in again."
The stored admin refresh token is no longer valid. This can happen if:
- The impersonation session lasted too long
- The admin's session was revoked elsewhere

### iOS: Session not swapping
Ensure you're calling `setSession` after receiving the tokens:
```swift
try await supabase.auth.setSession(
    accessToken: response.impersonated.accessToken,
    refreshToken: response.impersonated.refreshToken
)
```
