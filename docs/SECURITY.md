# Security Disclosure

This document describes the security disclosure setup for Tidex.

## security.txt

The project implements [RFC 9116](https://www.rfc-editor.org/rfc/rfc9116) via a `security.txt` file that provides standardized security contact information for researchers.

### Location

- **File**: `marketing/public/.well-known/security.txt`
- **URL**: `https://tidex.no/.well-known/security.txt`

### Fields

| Field | Value | Description |
|-------|-------|-------------|
| Contact | `mailto:contact@tidex.no` | Primary security contact |
| Expires | `2027-01-05T00:00:00.000Z` | File validity (update annually) |
| Preferred-Languages | `no, en` | Supported languages |
| Canonical | `https://tidex.no/.well-known/security.txt` | Canonical location |
| Policy | `https://tidex.no/security` | Link to disclosure policy |

### Updating

The `Expires` field uses a static date that should be updated annually. To update:

1. Edit `marketing/public/.well-known/security.txt`
2. Set `Expires` to one year from the current date in ISO 8601 format
3. Commit and deploy

## Security Disclosure Policy

The security disclosure policy is available at:

- Norwegian: `https://tidex.no/security`
- English: `https://tidex.no/en/security`

### Response Commitments

- Acknowledge receipt within 72 hours
- Initial assessment within 10 business days
- Resolution timeline depends on severity

### Source Files

- **Translations**: `marketing/lib/i18n/dictionaries/legal.*.ts` (security section)
- **Component**: `marketing/components/legal/SecurityPolicy.tsx`
- **Pages**: `marketing/app/[locale]/security/page.tsx` and `marketing/public/_redirects`

## Security Contact

All security reports should be sent to: `contact@tidex.no`
