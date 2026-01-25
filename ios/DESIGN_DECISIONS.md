# iOS Design Decisions

## Why Local-First?

**Decision**: All reads from SwiftData, network calls only for sync.

**Rationale**:
- **Offline Support**: App works without network
- **Performance**: Local reads are instant (no network latency)
- **Reliability**: Doesn't depend on server availability
- **Battery**: Reduces network calls and CPU usage
- **UX**: Instant feedback on user actions

**Trade-off**: Requires bidirectional sync logic (SyncCoordinator)

## Why Singleton Services?

**Decision**: AppCoordinator, SyncCoordinator, Repositories are singletons.

**Rationale**:
- **Single Source of Truth**: One instance per service
- **State Sharing**: All views see same state
- **Memory Efficient**: One instance per app lifetime
- **Simplicity**: No dependency injection boilerplate

**Trade-off**: Harder to test (mitigated by optional init parameters)

## Why @MainActor?

**Decision**: All UI-related code runs on main thread.

**Rationale**:
- **Thread Safety**: SwiftUI requires main thread
- **Prevents Crashes**: Avoids race conditions
- **Compiler Checked**: @MainActor enforces at compile time
- **Clear Intent**: Obvious which code is UI-related

**Trade-off**: Can't do heavy computation on main thread (use background tasks)

## Why Dirty Tracking?

**Decision**: Records marked dirty/clean for incremental sync.

**Rationale**:
- **Bandwidth**: Only dirty fields sent in PATCH
- **Conflict Surface**: Fewer fields = fewer conflicts
- **Efficiency**: Skip unchanged records
- **Auditability**: Know what changed locally

**Trade-off**: More complex sync logic

## Why Field-Level Merge?

**Decision**: Conflict resolution at field level, not row level.

**Rationale**:
- **Fewer Conflicts**: User edits one field, server edits another = no conflict
- **Auto-Merge**: Many conflicts resolve automatically
- **User Experience**: Less manual conflict resolution
- **Data Preservation**: Keep both local and server changes when possible

**Trade-off**: More complex conflict detection (need snapshots)

## Why Snapshot-Based Configuration?

**Decision**: Wage/tax settings versioned by date.

**Rationale**:
- **Historical Accuracy**: Shifts computed with settings from shift date
- **Flexibility**: Change settings without affecting past shifts
- **Auditability**: Know what settings applied to each shift
- **Consistency**: Same logic as web backend

**Trade-off**: More complex snapshot resolution (binary search)

## Why Caching with TTL?

**Decision**: View models cache computed data (5-minute TTL).

**Rationale**:
- **Performance**: Avoid redundant computation
- **Responsiveness**: Instant month navigation
- **Freshness**: 5 minutes balances freshness vs performance
- **Prefetching**: Load neighbors in background

**Trade-off**: Stale data for 5 minutes (acceptable for this use case)

## Why Notifications for Cross-Feature Communication?

**Decision**: Use Notification.Name for shifts changed, etc.

**Rationale**:
- **Decoupling**: Features don't need to know about each other
- **Simplicity**: No complex dependency injection
- **Flexibility**: Multiple listeners possible
- **Standard**: iOS standard pattern

**Trade-off**: Less type-safe than direct callbacks

## Why Async/Await?

**Decision**: Use async/await for all async operations.

**Rationale**:
- **Readability**: Looks like synchronous code
- **Safety**: Compiler prevents common mistakes
- **Cancellation**: Task cancellation built-in
- **Modern**: Swift 5.5+ standard

**Trade-off**: Requires iOS 13+ (acceptable for modern app)

## Why SwiftData?

**Decision**: Use SwiftData for local storage (not Core Data or Realm).

**Rationale**:
- **Modern**: Built-in to iOS 17+
- **Type-Safe**: Compile-time type checking
- **Macro-Based**: Less boilerplate than Core Data
- **Integrated**: Works seamlessly with SwiftUI
- **Apple-Supported**: First-party framework

**Trade-off**: iOS 17+ only (acceptable for new app)

## Why Supabase?

**Decision**: Use Supabase for backend (not Firebase or custom).

**Rationale**:
- **Open Source**: Can self-host if needed
- **PostgreSQL**: Powerful relational database
- **Real-Time**: Built-in real-time subscriptions
- **Auth**: Integrated authentication
- **Edge Functions**: Serverless functions
- **Cost**: Generous free tier

**Trade-off**: Less mature than Firebase (but sufficient for this app)

## Why Separate Web & iOS?

**Decision**: Native iOS app, not web wrapper (Capacitor).

**Rationale**:
- **Performance**: Native is faster
- **UX**: Native patterns and animations
- **Offline**: Better offline support
- **Platform Features**: Access to iOS APIs
- **Maintenance**: Separate codebases, but clearer intent

**Trade-off**: More code to maintain (mitigated by shared backend)

## Why Payroll Computed Server-Side?

**Decision**: Compute payroll in DAL, cache locally.

**Rationale**:
- **Consistency**: Single source of truth
- **Correctness**: Complex logic in one place
- **Auditability**: Server has authoritative computation
- **Offline**: iOS can compute locally with cached snapshots

**Trade-off**: iOS must replicate computation logic

## Why Incremental Sync?

**Decision**: Pull only changed records (updated_at cursor).

**Rationale**:
- **Bandwidth**: Don't re-download unchanged data
- **Performance**: Faster sync
- **Scalability**: Works with large datasets
- **Efficiency**: Reduces server load

**Trade-off**: More complex cursor management

## Why Soft Deletes?

**Decision**: Mark deleted_at instead of hard delete.

**Rationale**:
- **Auditability**: Know when records were deleted
- **Recovery**: Can restore deleted records
- **Sync**: Easier to sync deletions
- **Compliance**: May be required for regulations

**Trade-off**: Slightly more complex queries (filter deleted_at)

## Summary

The iOS architecture prioritizes:
1. **Offline Support** (local-first)
2. **Performance** (caching, prefetching)
3. **Reliability** (conflict resolution, dirty tracking)
4. **Consistency** (snapshot-based config, server-computed payroll)
5. **Maintainability** (clear patterns, type safety)

These decisions create a robust, performant app that works offline and syncs reliably with the server.

