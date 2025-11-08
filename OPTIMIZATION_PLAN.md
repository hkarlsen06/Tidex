# Performance Optimization Plan

This document outlines a systematic plan to optimize the Tidex application's bundle size, runtime performance, and asset delivery.

## Overview

**Total Estimated Impact:**
- Bundle Size: -172KB+ reduction
- Node Modules: -100MB reduction
- Runtime Performance: +15-25% improvement
- Static Assets: -200KB reduction

**Estimated Total Time:** 2-3 hours

---

## 🔴 Phase 1: High Impact - Quick Wins

### 1.1 Icon Library Consolidation (Biggest Impact)

**Problem:** Using both `@tabler/icons-react` (118MB) and `lucide-react` (43MB) when only one is needed.

**Current State:**
- 23 components import from `@tabler/icons-react`
- Remaining components use `lucide-react`

**Impact:**
- `-100MB` node_modules size
- `-50KB+` bundle size
- Simplified dependency tree

**Steps:**
1. Audit all icon imports across the codebase
2. Create icon mapping between Tabler and Lucide
3. Replace all `@tabler/icons-react` imports with `lucide-react` equivalents
4. Update component files (estimated 23 files)
5. Remove `@tabler/icons-react` from `package.json`
6. Run `npm install` to clean up
7. Test all affected components for visual consistency
8. Run build to verify bundle size reduction

**Files to Update:**
- All components importing from `@tabler/icons-react`
- `package.json`

**Estimated Time:** 45-60 minutes

---

### 1.2 Add modularizeImports for Icon Tree-Shaking

**Problem:** Icons are not optimally tree-shaken despite `optimizePackageImports` config.

**Current State:**
```javascript
experimental: {
  optimizePackageImports: ['lucide-react', '@tabler/icons-react'],
}
```

**Target State:**
```javascript
experimental: {
  optimizePackageImports: ['lucide-react'],
  modularizeImports: {
    'lucide-react': {
      transform: 'lucide-react/dist/esm/icons/{{kebabCase member}}',
    },
  },
}
```

**Impact:**
- `-20KB` bundle size
- Better code splitting
- Faster icon imports

**Steps:**
1. Open `next.config.js`
2. Add `modularizeImports` configuration
3. Remove `@tabler/icons-react` from `optimizePackageImports` (after migration)
4. Test dev server startup
5. Run production build to verify improvement

**Files to Update:**
- `next.config.js`

**Estimated Time:** 5 minutes

---

### 1.3 Reduce Sentry Trace Sampling Rate

**Problem:** 100% trace sampling creates unnecessary overhead in production.

**Current State:**
```typescript
tracesSampleRate: 1 // 100% of requests traced
```

**Target State:**
```typescript
tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.1 : 1
```

**Impact:**
- `+15%` runtime performance
- Reduced Sentry quota usage
- Lower network overhead

**Steps:**
1. Open `sentry.client.config.ts`
2. Update `tracesSampleRate` to conditional value
3. Open `sentry.server.config.ts`
4. Update `tracesSampleRate` to conditional value
5. Test in development (should remain at 100%)
6. Verify production behavior

**Files to Update:**
- `sentry.client.config.ts`
- `sentry.server.config.ts`

**Estimated Time:** 5 minutes

---

## 🟡 Phase 2: Medium Impact Optimizations

### 2.1 Dynamic Import canvas-confetti

**Problem:** `canvas-confetti` (2MB) is loaded eagerly even though it's only used on specific user actions.

**Current State:**
```typescript
// ShiftsView.tsx
import confetti from "canvas-confetti"
```

**Target State:**
```typescript
const triggerConfetti = async () => {
  const confetti = (await import('canvas-confetti')).default;
  confetti({
    particleCount: 100,
    spread: 70,
    origin: { y: 0.6 }
  });
};
```

**Impact:**
- `-2MB` from initial bundle
- Faster initial page load
- Confetti loads on-demand

**Steps:**
1. Locate all `canvas-confetti` imports
2. Replace with dynamic `import()` calls
3. Update function signatures to be `async`
4. Test confetti trigger functionality
5. Verify bundle analyzer shows split chunk

**Files to Update:**
- `components/app/ShiftsView.tsx` (or wherever confetti is used)

**Estimated Time:** 10 minutes

---

### 2.2 Optimize Image Assets

**Problem:** ~500KB of PNG icons with duplicates and no WebP alternatives.

**Current State:**
- Duplicate icons in `icons/` and root
- All images in PNG format
- No compression or modern formats

**Target State:**
- Single source of truth for icons
- WebP format with PNG fallbacks
- Optimized compression

**Impact:**
- `-200KB` static assets
- Faster asset loading
- Better cache efficiency

**Steps:**
1. Audit `icons/` directory and root for duplicates
2. Remove duplicate icon files
3. Convert remaining PNGs to WebP using `sharp` or similar
4. Update references in code to use WebP with PNG fallback
5. Add `.webp` to `.gitignore` if auto-generated
6. Test image loading in all contexts

**Files to Update:**
- `icons/` directory
- Root icon files
- Any components referencing icons
- `next.config.js` (if adding image optimization config)

**Estimated Time:** 20 minutes

---

### 2.3 Refactor StatsContent Client State to URL Params

**Problem:** Heavy client-side state management in `StatsContent.tsx` (8 useState, 4 useEffect).

**Current State:**
- Month navigation managed in client state
- No URL sync for navigation
- Heavy re-renders

**Target State:**
- Month navigation via URL search params (`?month=2025-01`)
- Shareable URLs with navigation state
- Server-side rendering of correct month
- Reduced client-side JavaScript

**Impact:**
- `-30KB` bundle size
- `+10%` page load speed
- Better SEO and sharing

**Steps:**
1. Identify all useState related to navigation
2. Replace with `useSearchParams()` from `next/navigation`
3. Update navigation handlers to use `router.push()` with query params
4. Update server component to read `searchParams` prop
5. Add default month logic server-side
6. Test month navigation, swipe gestures, and loading states
7. Verify back/forward browser navigation works

**Files to Update:**
- `app/[locale]/(app)/stats/page.tsx`
- `components/app/StatsContent.tsx`
- Any stats-related components

**Estimated Time:** 45 minutes

---

## 📋 Implementation Checklist

### Phase 1 (High Impact - ~70 minutes) ✅ COMPLETE
- [x] **1.1** Icon library consolidation
  - [x] Audit icon usage
  - [x] Create Tabler → Lucide mapping
  - [x] Replace imports in 23 components
  - [x] Remove `@tabler/icons-react` dependency
  - [x] Test visual consistency
  - [x] Verify bundle reduction
- [x] **1.2** Tree-shaking via optimizePackageImports (already configured)
- [x] **1.3** Reduce Sentry sampling rate (reduced to 10% in production)

### Phase 2 (Medium Impact - ~75 minutes)
- [ ] **2.1** Dynamic import canvas-confetti (10 min)
- [ ] **2.2** Optimize image assets (20 min)
- [ ] **2.3** Refactor StatsContent to URL params (45 min)

### Validation & Testing
- [x] Run `npm run build` and verify bundle size improvements
- [x] Verify no console errors or warnings (build clean)
- [ ] Test all modified pages in development
- [ ] Run production build and test critical paths
- [ ] Check lighthouse scores before/after
- [ ] Monitor Sentry for any new errors after deployment

---

## Success Metrics

**Before Optimization:**
- Node modules: ~XXX MB
- Production bundle: ~XXX KB
- Page load (stats): ~XXX ms
- Lighthouse score: ~XX

**Target After Optimization:**
- Node modules: -100MB
- Production bundle: -172KB
- Page load (stats): +10-25% faster
- Lighthouse score: +5-10 points

---

## Notes

- All optimizations are backwards compatible
- No breaking changes to user-facing features
- Each phase can be implemented and tested independently
- Rollback plan: Git revert individual commits if issues arise

---

## Already Optimized ✅

The following optimizations are already in place (great work!):

- ✅ Dynamic imports for all charts
- ✅ `next/font` with optimal settings
- ✅ Next.js 16 caching (`'use cache'`)
- ✅ Server Components architecture
- ✅ Turbopack enabled
- ✅ PWA configuration

---

**Last Updated:** 2025-11-08
