# TODO

## Localization

### Server Action Error Messages

Server actions currently return hardcoded Norwegian error messages directly to the client. This works but prevents proper localization for English users.

**Current pattern:**
```typescript
// Server action returns Norwegian error string
return { success: false, error: "Kunne ikke opprette deling" };

// Client displays it directly
{error && <p className="text-sm text-error">{error}</p>}
```

**Recommended pattern:**
```typescript
// Server action returns error code
return { success: false, errorCode: "FAILED_TO_CREATE" };

// Client maps to localized string
{errorCode && <p className="text-sm text-error">{t.pages.sharing.errors[errorCode]}</p>}
```

**Affected files:**
- `app/[locale]/(app)/sharing/_actions/sharing.ts` - `SHARING_ERRORS` object
- `app/[locale]/(app)/settings/pay/_actions/wage-snapshots.ts`
- `app/[locale]/(app)/shifts/_actions/*.ts` - Multiple shift action files
- `lib/errors/messages.ts` - Centralized `ERRORS` object

**Dictionary keys already exist** for sharing errors at `pages.sharing.errors.*` in both `en.ts` and `no.ts`.

**Effort:** Medium - requires updating server actions to return codes and client components to map codes to translations.
