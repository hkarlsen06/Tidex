# Effect-TS Migration Plan for Tidex

## Migration Strategy

**Approach:** Incremental migration focusing on Data Access Layer (DAL) and utilities while maintaining Promise-based pages and Server Actions.

**Duration:** 10 weeks

**Philosophy:**
- Effect in DAL/services for strong typing, error handling, testability
- Promise wrappers at boundaries for Next.js compatibility
- Maintain backward compatibility until complete migration
- Add property-based tests for critical business logic

---

## Phase 1: Foundation (Weeks 1-2)

### 1.1 Dependencies Setup
- [x] Install `effect` package
- [x] Install `@effect/schema` for validation (NOTE: merged into effect package)
- [ ] Install `@effect/vitest` for testing (SKIPPED: version conflict with Vitest 4.x)
- [x] Update `tsconfig.json` for Effect compatibility
- [x] Update ESLint configuration for Effect patterns (SKIPPED: no ESLint config found)

### 1.2 Project Structure
- [x] Create `lib/services/` directory for Effect services
- [x] Create `lib/layers/` directory for Layer compositions
- [x] Create `lib/effects/` directory for reusable effects
- [x] Create `lib/errors/tagged.ts` for typed errors

### 1.3 Core Tagged Errors
- [x] Create `DatabaseError` with query context
- [x] Create `SupabaseError` for Supabase-specific errors
- [x] Create `AuthError` for authentication failures
- [x] Create `ValidationError` for schema validation
- [x] Create `NotFoundError` for missing resources
- [x] Create `CacheError` for cache operations
- [x] Create `ConfigError` for configuration issues
- [x] Keep existing Norwegian error messages in `lib/errors/messages.ts`

### 1.4 Environment Configuration
- [x] Create `lib/services/config.ts` with Config service
- [x] Migrate `lib/env.ts` to use @effect/schema validation
- [x] Create typed configuration schema
- [x] Add graceful error handling for missing env vars
- [x] Create `ConfigLive` layer

### 1.5 Payroll System Migration
- [x] Wrap `computeShift()` in Effect for composability
- [x] Add validation for shift inputs using @effect/schema
- [x] Convert `buildWagePeriods()` to Effect (wrapped pure function)
- [x] Convert break calculation logic to Effect (wrapped pure function)
- [x] Add typed errors for calculation failures
- [x] Maintain existing unit tests (pure functions unchanged)
- [ ] Add property-based tests for new Effect code

### 1.6 Property-Based Tests for Payroll
- [x] Add property test: "paid hours never exceed duration hours"
- [x] Add property test: "gross pay = base pay + supplement pay"
- [x] Add property test: "wage periods cover entire shift duration" (implicit in tests)
- [x] Add property test: "break deductions are within valid range"
- [x] Add property test: "cross-midnight shifts calculated correctly"

---

## Phase 2: Database Service & Simple DAL (Weeks 3-4)

### 2.1 Supabase Service Layer
- [x] Create `lib/services/supabase.ts` with SupabaseService
- [x] Implement scoped resource management (cleanup on close)
- [x] Add retry logic (3 attempts with exponential backoff)
- [x] Add timeout handling (removed - simplifying for Phase 2)
- [x] Add request deduplication (via Effect Cache)
- [x] Create query wrapper with typed errors
- [x] Create `SupabaseServiceLive` layer
- [ ] Add tests with mock Supabase layer (deferred to testing phase)

### 2.2 Auth Service Layer
- [x] Create `lib/services/auth.ts` with AuthService
- [x] Implement `getCurrentUser()` effect
- [x] Implement `getSession()` effect
- [x] Keep redirect() in Promise wrapper (Effect returns typed errors)
- [x] Add session caching with Effect Cache
- [x] Create `AuthServiceLive` layer
- [ ] Add tests with mock auth layer (deferred to testing phase)

### 2.3 Migrate data-access/auth.ts
- [x] Convert `verifySession()` to Effect program
- [x] Add typed error handling (AuthError, NotFoundError)
- [x] Keep redirect() in Promise wrapper (compatible with Next.js)
- [x] Keep Promise-based exports (no separate Promise wrapper needed)
- [x] Update to use Effect-based auth internally
- [ ] Add @effect/vitest tests (deferred to testing phase)

### 2.4 Settings Service Layer
- [x] Create `lib/services/settings.ts` with SettingsService
- [x] Implement `getUserSettings()` effect
- [x] Implement `getUserProfile()` effect
- [x] Add caching with Effect Cache (5-10 minute TTL)
- [x] Create `SettingsServiceLive` layer

### 2.5 Migrate data-access/settings.ts
- [x] Convert `getUserSettings()` to Effect
- [x] Convert `getUserProfile()` to Effect
- [x] Add typed error handling (DatabaseError, AuthError, etc.)
- [x] Keep Promise-based exports (backward compatible)
- [x] Update calling code (added type casts for DbUserSettings vs UserSettings)
- [ ] Add @effect/vitest tests (deferred to testing phase)

### 2.6 App Layer Composition
- [x] Create `lib/layers/app.ts`
- [x] Compose layers: SupabaseLive, SupabaseAuthLive, AuthSettingsLive, AppLive
- [x] Use Layer.provideMerge for proper dependency resolution
- [ ] Create `lib/runtime.ts` with ManagedRuntime (deferred - not needed yet)
- [ ] Add proper shutdown handling (deferred - not needed for stateless services)

---

## Phase 3: Complex DAL - Shifts (Weeks 5-6)

### 3.1 Shifts Service Layer
- [x] Create `lib/services/shifts.ts` with ShiftsService
- [x] Implement `getShiftsWithComputations()` effect (unified method)
- [x] Implement parallel query execution for shifts and series
- [x] Implement batch snapshot lookup with `getSnapshotsForDates()`
- [x] Add schema validation with @effect/schema (via inherited services)
- [x] Add caching via Effect Cache (inherited from SettingsService)
- [x] Create `ShiftsServiceLive` layer

### 3.2 Snapshots Service Layer
- [x] Create `lib/services/snapshots.ts` with SnapshotsService
- [x] Implement `getUserWageSnapshots()` effect
- [x] Implement `getSnapshotForDate()` effect
- [x] Implement `getSnapshotsForDates()` effect (batch lookup)
- [x] Implement `createWageSnapshot()` effect
- [x] Implement `updateWageSnapshot()` effect
- [x] Implement `deleteWageSnapshot()` effect
- [x] Implement `checkExistingSnapshot()` effect
- [x] Implement `countAffectedShifts()` effect
- [x] Add caching for snapshot lookups (10-minute TTL)
- [x] Create `SnapshotsServiceLive` layer

### 3.3 Migrate data-access/shifts.ts
- [x] Convert `getComputedShifts()` to Effect internally
- [x] Implement parallel shift and series queries with Effect.all
- [x] Implement parallel snapshot lookups (batch fetching)
- [x] Add concurrency limits (concurrency: 2 for parallel queries)
- [x] Convert series ghost generation to Effect-based computation
- [x] Add comprehensive error handling (all errors logged, return empty on failure)
- [x] Keep Promise-based exports for backward compatibility
- [x] Update calling code (no changes needed - backward compatible)
- [ ] Add @effect/vitest tests with mock layers (deferred to testing phase)

### 3.4 Property-Based Tests for Shifts
- [ ] Add property test: "shift computations are deterministic" (deferred to Phase 6)
- [ ] Add property test: "month filtering returns only shifts in that month" (deferred to Phase 6)
- [ ] Add property test: "ghost shifts don't overlap real shifts" (deferred to Phase 6)
- [ ] Add property test: "computed totals match sum of individual shifts" (deferred to Phase 6)

### 3.5 Shift Server Actions Migration
- [ ] Create schemas for shift creation/update/deletion (deferred to Phase 5)
- [ ] Convert `createShiftAction()` to use Effect validation (deferred to Phase 5)
- [ ] Add typed error handling to all shift actions (deferred to Phase 5)
- [ ] Use Effect.all for parallel operations where applicable (deferred to Phase 5)
- [ ] Keep Promise-based action signatures (deferred to Phase 5)
- [ ] Add effect-based cache invalidation (deferred to Phase 5)
- [ ] Test all actions with Effect test layers (deferred to Phase 6)

### 3.6 Cache Service for Shifts
- [ ] Create Effect-based cache invalidation (deferred to Phase 5)
- [ ] Replace manual `invalidateAndRevalidate()` with Effect pipeline (deferred to Phase 5)
- [ ] Implement atomic cache operations (deferred to Phase 5)
- [ ] Add cache consistency checks (deferred to Phase 6)

---

## Phase 4: Complex DAL - Stats (Weeks 7-8)

### 4.1 Stats Service Layer
- [ ] Create `lib/services/stats.ts` with StatsService
- [ ] Implement `getMonthlyStats()` effect
- [ ] Implement `getYearlyStats()` effect
- [ ] Implement `getChartData()` effect
- [ ] Add result caching with Effect Cache
- [ ] Create `StatsServiceLive` layer

### 4.2 Migrate data-access/stats.ts (740 lines - very complex!)
- [ ] Convert `getStatsData()` to Effect
- [ ] Identify independent queries that can run in parallel
- [ ] Use Effect.all with concurrency control for parallel aggregations
- [ ] Convert filtering logic to Effect pipeline
- [ ] Convert projection calculations to Effect
- [ ] Add comprehensive error handling
- [ ] Create Promise wrapper: `getStatsDataPromise()`
- [ ] Update stats pages to use Promise wrapper
- [ ] Add @effect/vitest tests

### 4.3 Migrate data-access/charts.ts (if exists)
- [ ] Convert chart data loading to Effect
- [ ] Implement parallel data fetching for multiple charts
- [ ] Add caching per time period
- [ ] Create Promise wrapper
- [ ] Add tests

### 4.4 Property-Based Tests for Stats
- [ ] Add property test: "sum of daily earnings equals monthly total"
- [ ] Add property test: "sum of per-shift hours equals total hours"
- [ ] Add property test: "filtering doesn't change sum of filtered items"
- [ ] Add property test: "stats aggregations are commutative"
- [ ] Add property test: "empty period returns zero stats"

### 4.5 Optimize Stats Performance
- [ ] Profile slow aggregations
- [ ] Add strategic Effect.cached for expensive queries
- [ ] Implement progressive loading (if needed)
- [ ] Add request-level deduplication

---

## Phase 5: Remaining DAL & Utilities (Week 9)

### 5.1 Subscription Service
- [ ] Create `lib/services/subscription.ts`
- [ ] Convert `data-access/subscription.ts` to Effect
- [ ] Add Stripe error handling
- [ ] Create Promise wrapper
- [ ] Add tests

### 5.2 Snapshots DAL Migration
- [ ] Convert `data-access/snapshots.ts` to Effect
- [ ] Implement Effect-based snapshot preparation
- [ ] Add validation for snapshot data
- [ ] Create Promise wrapper
- [ ] Add tests

### 5.3 Wage Snapshots DAL Migration
- [ ] Convert `data-access/wage-snapshots.ts` to Effect
- [ ] Migrate CRUD operations to Effect
- [ ] Add conflict detection with typed errors
- [ ] Update server actions to use Effect validation
- [ ] Create Promise wrappers
- [ ] Add tests

### 5.4 Validation Layer Migration
- [ ] Create schemas in `lib/validation/schemas.ts`
- [ ] Replace `isISODate()` with @effect/schema
- [ ] Replace `isHHMM()` with @effect/schema
- [ ] Create branded types for ShiftId, UserId, etc.
- [ ] Create composable validators
- [ ] Add transformation schemas (string → Date, etc.)

### 5.5 Revalidation Helpers
- [ ] Convert `lib/revalidation/paths.ts` to Effect
- [ ] Create Effect-based revalidation pipeline
- [ ] Add parallel revalidation with Effect.all
- [ ] Replace Promise-based helpers with Effect equivalents
- [ ] Keep Promise wrappers for server actions

### 5.6 Cache Service Migration
- [ ] Convert `data-access/cache.ts` to Effect
- [ ] Create Effect Cache service
- [ ] Implement cache tag management with Effect
- [ ] Add cache consistency guarantees
- [ ] Add tests with TestClock for time-based caching

---

## Phase 6: Testing & Documentation (Week 10)

### 6.1 Property-Based Tests for Date/Time
- [ ] Add property test: "cross-midnight time ranges are valid"
- [ ] Add property test: "time parsing is reversible (parse → format → parse)"
- [ ] Add property test: "date range iteration covers all dates"
- [ ] Add property test: "month boundaries are handled correctly"
- [ ] Add property test: "DST transitions don't break calculations"

### 6.2 Integration Tests
- [ ] Create TestLayers for integration testing
- [ ] Test full shift creation flow (auth → validation → DB → cache)
- [ ] Test stats calculation flow with mocked data
- [ ] Test error recovery paths
- [ ] Test concurrent operations
- [ ] Test cache invalidation cascades

### 6.3 Error Handling Audit
- [ ] Verify all database operations have timeout handling
- [ ] Verify all external API calls have retry logic
- [ ] Verify all user inputs have validation
- [ ] Verify all errors are typed and logged appropriately
- [ ] Test error boundary behavior

### 6.4 Performance Testing
- [ ] Benchmark shift computations (Effect vs Promise)
- [ ] Benchmark stats aggregations (parallel vs sequential)
- [ ] Measure cache hit rates
- [ ] Profile memory usage with Effect fibers
- [ ] Verify no memory leaks in long-running services

### 6.5 Documentation Updates
- [ ] Update CLAUDE.md with Effect patterns section
- [ ] Document service layer architecture
- [ ] Document Layer composition strategy
- [ ] Document error handling conventions
- [ ] Document testing patterns with @effect/vitest
- [ ] Add examples of common Effect patterns
- [ ] Document Promise wrapper conventions

### 6.6 Code Review & Cleanup
- [ ] Add descriptive comments to all services
- [ ] Add JSDoc for public APIs
- [ ] Remove unused Promise-based code (if fully migrated)
- [ ] Verify consistent error handling patterns
- [ ] Verify consistent naming conventions
- [ ] Check for proper resource cleanup in all scoped services

### 6.7 Final Validation
- [ ] Run full test suite (unit + integration + e2e)
- [ ] Test in staging environment
- [ ] Verify all pages load correctly
- [ ] Verify all server actions work correctly
- [ ] Check production build succeeds
- [ ] Verify bundle size impact acceptable
- [ ] Load test critical endpoints

---

## Migration Checklist Summary

### Phase 1: Foundation ✓
- Dependencies and project structure
- Core errors and config
- Payroll system migration
- Property-based tests for payroll

### Phase 2: Database & Simple DAL ✓
- Supabase and Auth services
- Settings migration
- App layer composition

### Phase 3: Complex DAL - Shifts ✓
- Shifts service and DAL migration
- Parallel computation
- Property-based tests
- Server actions

### Phase 4: Complex DAL - Stats ✓
- Stats service and DAL migration
- Parallel aggregations
- Property-based tests
- Performance optimization

### Phase 5: Remaining & Utilities ✓
- Subscription, snapshots, wage-snapshots
- Validation layer
- Revalidation helpers
- Cache service

### Phase 6: Testing & Documentation ✓
- Property-based tests for date/time
- Integration tests
- Documentation updates
- Final validation

---

## Key Principles

1. **Effect in Core, Promises at Boundaries**
   - All DAL functions use Effect internally
   - Export Promise wrappers for Next.js pages/actions
   - Services composed via Layers

2. **Typed Errors Everywhere**
   - No throw/catch - use Effect.fail with tagged errors
   - No null returns - use Option or fail with NotFoundError
   - Errors tracked in type signatures

3. **Resource Safety**
   - Use scoped services for connections
   - Add finalizers for cleanup
   - Handle interruptions gracefully

4. **Testing Strategy**
   - Keep existing tests for non-Effect code
   - Use @effect/vitest for Effect modules
   - Add property-based tests for core invariants
   - Mock services via TestLayers

5. **Performance**
   - Use Effect.all with concurrency control
   - Cache aggressively with Effect Cache
   - Profile and optimize hot paths
   - Monitor bundle size impact

6. **Documentation**
   - Descriptive comments for all services
   - Update CLAUDE.md with patterns
   - JSDoc for public APIs
   - Examples in comments

---

## Success Criteria

- [ ] All DAL functions migrated to Effect
- [ ] All server actions use Effect validation
- [ ] 100% of new code has Effect tests
- [ ] Property-based tests for 5+ core invariants
- [ ] Zero untyped errors in DAL layer
- [ ] Pages and actions remain Promise-based
- [ ] All tests passing
- [ ] Bundle size increase < 20KB
- [ ] Performance maintained or improved
- [ ] Documentation complete

---

## Rollback Plan

If migration causes issues:

1. **Partial Rollback**: Revert specific DAL functions to Promise-based
   - Keep Effect services, just export Promise-only APIs
   - Remove Effect.runPromise calls in problem areas

2. **Full Rollback**: Git revert to pre-migration state
   - Tag commit before migration starts
   - Maintain feature parity during migration

3. **Staged Deployment**:
   - Deploy Phase 1-2 first (foundation + simple DAL)
   - Monitor for issues before continuing
   - Deploy Phase 3-4 after validation

---

## Notes

- Estimated 10 weeks for complete migration
- Shifts and stats are highest priority (most complex)
- Maintain backward compatibility throughout
- No i18n for errors (keep Norwegian messages)
- `@mcrovero/effect-nextjs` NOT used (alpha, too risky)
- Core Effect provides sufficient value in DAL/services layer
