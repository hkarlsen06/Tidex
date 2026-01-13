# Codebase Concerns

**Analysis Date:** 2026-01-13

## Tech Debt

**Large Complex Files:**
- Issue: Several files exceed recommended size limits
- Files:
  - `lib/chat/executor.ts` - 2,007 lines (chat tool execution)
  - `components/shifts/ShiftsView.tsx` - 3,184 lines (shift management UI)
  - `lib/services/sharing.ts` - 1,442 lines (sharing logic)
  - `components/settings/data/DataForm.tsx` - 1,124 lines (settings form)
- Impact: High cognitive load, difficult to maintain and test
- Fix approach: Extract into smaller, focused modules/components

**dangerouslySetInnerHTML Usage:**
- Issue: HTML injection via translation strings without sanitization
- Files:
  - `app/[locale]/(app)/onboarding/_components/BreakStep.tsx:282` - `methodExplanations`
  - `app/layout.tsx:80+` - Theme initialization script
- Why: Translation strings contain formatting (HTML tags)
- Impact: XSS risk if translations become user-editable
- Fix approach: Use React components instead of HTML strings, or add DOMPurify sanitization

**Unused Dependency:**
- Issue: `neverthrow` package included but Effect-TS now handles all Result types
- File: `package.json`
- Impact: Unnecessary bundle size
- Fix approach: Remove neverthrow, ensure all code uses Effect

## Known Bugs

**Race condition in subscription updates:**
- Symptoms: User shows as "free" tier for 5-10 seconds after successful payment
- Trigger: Fast navigation after Stripe checkout redirect, before webhook processes
- Files: `app/[locale]/(app)/settings/subscription/` (various)
- Workaround: Webhook eventually updates status (self-heals)
- Root cause: Webhook processing slower than user navigation
- Documented in: `CLAUDE.md`

## Security Considerations

**dangerouslySetInnerHTML with translations:**
- Risk: XSS if translation system ever supports user input
- Files: `app/[locale]/(app)/onboarding/_components/BreakStep.tsx:282`
- Current mitigation: Translations are developer-controlled static strings
- Recommendations: Refactor to use React components for formatted content

**Unsafe type assertions:**
- Risk: Runtime type errors if assumptions are wrong
- Count: 434 instances of `@ts-ignore`, `any`, `as any` patterns
- Files: Concentrated in Capacitor integration, River streaming, Firebase
- Current mitigation: Limited to third-party integration code
- Recommendations: Gradually add proper typing, especially in modified code

## Performance Bottlenecks

**Large translation dictionaries:**
- Problem: Full dictionary loaded even when only specific namespaces needed
- Files: `lib/i18n/dictionaries/no.ts` (1,812 lines), `lib/i18n/dictionaries/en.ts` (1,803 lines)
- Cause: Dictionary structure not optimized for tree-shaking
- Improvement path: Use `getAppDictionary(locale, namespaces)` consistently, consider dynamic imports

**Duplicate snapshot resolution logic:**
- Problem: Same logic exists in multiple places
- Files:
  - `components/shifts/ShiftsView.tsx:81-90` - `getSnapshotForDate` function
  - `lib/services/shifts.ts` - Similar logic in service
- Cause: Component-level convenience function duplicates service logic
- Improvement path: Centralize in single utility, remove duplication

## Fragile Areas

**Chat executor (`lib/chat/executor.ts`):**
- Why fragile: Monolithic file handling 10+ tool types with shared state
- Common failures: New tool type added without proper error handling
- Safe modification: Test each tool type independently before changes
- Test coverage: No unit tests currently

**Payroll computation (`lib/payroll/`):**
- Why fragile: Complex business logic with many edge cases
- Common failures: Cross-midnight shifts, supplement overlaps, break edge cases
- Safe modification: Well-tested, add tests for new scenarios
- Test coverage: Good (683 lines of integration tests)

## Scaling Limits

**Supabase quotas:**
- Current capacity: Project-level quotas per Supabase plan
- Limit: Depends on subscription tier
- Symptoms at limit: 429 rate limit errors
- Scaling path: Upgrade Supabase plan, add caching layer

**Translation bundle size:**
- Current capacity: ~3,600 lines of translation strings
- Limit: Impacts initial page load time
- Symptoms at limit: Slower TTFB for pages
- Scaling path: Implement namespace-based code splitting

## Dependencies at Risk

**@capgo/native-purchases:**
- Risk: Third-party native bridge, update frequency to monitor
- Impact: iOS in-app purchases break if incompatible
- Migration plan: None needed currently, actively maintained

**Motion (formerly Framer Motion):**
- Risk: Major rebrand, import paths changed
- Impact: Already migrated to `motion/react`
- Status: Migration complete, no current risk

## Missing Critical Features

**API route test coverage:**
- Problem: No tests for REST API endpoints
- Files: `app/api/*` (18+ routes)
- Current workaround: Manual testing, E2E covers some flows
- Blocks: Confident refactoring of API layer
- Implementation complexity: Medium (need mock Supabase client)

**Server action test coverage:**
- Problem: No tests for server actions
- Files: `*_actions/*.ts` (~50+ actions)
- Current workaround: Manual testing
- Blocks: Confident refactoring of mutation logic
- Implementation complexity: Medium (need mock DAL functions)

**Rate limiting:**
- Problem: Only implemented for admin impersonation
- Files: `app/api/*` routes lack rate limiting
- Current workaround: Rely on Vercel/Supabase limits
- Blocks: Protection against abuse
- Implementation complexity: Low (add middleware)

## Test Coverage Gaps

**API routes:**
- What's not tested: All REST endpoints in `app/api/*`
- Risk: Regressions in data fetching/mutation logic
- Priority: Medium
- Difficulty to test: Need to mock Supabase client

**Server actions:**
- What's not tested: All server actions in `*_actions/` directories
- Risk: Regressions in form handling, cache invalidation
- Priority: Medium
- Difficulty to test: Need to mock DAL functions

**Chat executor:**
- What's not tested: `lib/chat/executor.ts` tool execution
- Risk: AI assistant tool calls break silently
- Priority: High (user-facing feature)
- Difficulty to test: Need to mock Claude API responses

**Sharing service:**
- What's not tested: `lib/services/sharing.ts`
- Risk: Share functionality breaks
- Priority: Medium
- Difficulty to test: Need to mock user lookup logic

## Positive Observations

**Well-Tested Areas:**
- Payroll calculations - Comprehensive integration tests
- Date utilities - Thorough unit tests
- Snapshot resolution - Well-covered edge cases

**Security Strengths:**
- Webhook signature verification (Stripe, Apple)
- Rate limiting on sensitive operations (impersonation)
- Proper JWT-based authentication
- No hardcoded secrets
- Input validation on critical paths

**Architecture Strengths:**
- Effect-TS for type-safe services
- Centralized DAL for data access
- Clear component separation (ui vs app)
- Good use of React cache()
- Consistent cache invalidation patterns

---

*Concerns audit: 2026-01-13*
*Update as issues are fixed or new ones discovered*
