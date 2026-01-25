# Effect-TS Patterns & Examples

This document contains detailed Effect-TS patterns and examples for the Tidex codebase. For a summary, see the Effect-TS Integration section in `CLAUDE.md`.

## Service Usage Examples

### Using SupabaseService

```typescript
import { SupabaseService } from "@/lib/services/supabase"
import { SupabaseLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const supabase = yield* SupabaseService

  const result = yield* supabase.query(
    async (client) => await client.from("shifts").select("*"),
    { retries: 2 }
  )

  return result
}).pipe(Effect.provide(SupabaseLive), Effect.scoped)

const data = await Effect.runPromise(program)
```

### Using ShiftsService

```typescript
import { ShiftsService } from "@/lib/services/shifts"
import { ShiftsLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const shifts = yield* ShiftsService

  const data = yield* shifts.getShiftsWithComputations({
    userId: "user-id",
    year: 2025,
    month: 1
  })

  return data
}).pipe(Effect.provide(ShiftsLive), Effect.scoped)

const shifts = await Effect.runPromise(program)
```

### Using Multiple Services

```typescript
import { AuthService, SettingsService } from "@/lib/services"
import { AuthSettingsLive } from "@/lib/layers/app"

const program = Effect.gen(function* () {
  const auth = yield* AuthService
  const settings = yield* SettingsService

  const session = yield* auth.getSession()
  const userSettings = yield* settings.getUserSettings(session.user.id)

  return { session, userSettings }
}).pipe(Effect.provide(AuthSettingsLive), Effect.scoped)

const data = await Effect.runPromise(program)
```

### Validation with Schema

```typescript
import { validateShiftInput } from "@/lib/validation/schemas"
import { ValidationError } from "@/lib/errors/tagged"

const program = validateShiftInput(data).pipe(
  Effect.mapError((error) => new ValidationError({
    field: "shift",
    message: "Invalid shift data"
  }))
)

const validShift = await Effect.runPromise(program)
```

## Effect Patterns

### 1. Creating a Service

```typescript
import { Context, Effect, Layer } from "effect"
import { SupabaseService } from "./supabase"

export class MyService extends Context.Tag("MyService")<
  MyService,
  {
    readonly getData: (id: string) => Effect.Effect<Data, DatabaseError, never>
  }
>() {}

export const MyServiceLive = Layer.effect(
  MyService,
  Effect.gen(function* () {
    const supabase = yield* SupabaseService

    const getData = (id: string) =>
      Effect.gen(function* () {
        const result = yield* supabase.query(
          async (client) => await client.from("data").select("*").eq("id", id).single(),
          { retries: 2 }
        )
        return result
      })

    return { getData }
  })
)
```

### 2. Composing Layers

```typescript
import { Layer } from "effect"
import { SupabaseLive } from "./supabase"
import { MyServiceLive } from "./my-service"

// Provide dependencies automatically
export const MyServiceWithDeps = Layer.provideMerge(MyServiceLive, SupabaseLive)
```

### 3. Error Handling with catchTag

```typescript
import { NotFoundError, DatabaseError } from "@/lib/errors/tagged"

const program = Effect.gen(function* () {
  const data = yield* supabase.query(...)
  if (!data) {
    yield* Effect.fail(new NotFoundError({ resource: "User", id: "123" }))
  }
  return data
}).pipe(
  Effect.catchTag("NotFoundError", () => Effect.succeed(null)),
  Effect.catchTag("DatabaseError", (error) => {
    if (error.code === "NO_DATA") {
      return Effect.succeed(null)
    }
    logger.error("Database error:", error)
    return Effect.fail(error)
  })
)
```

### 4. Parallel Execution

```typescript
const program = Effect.gen(function* () {
  // Execute queries in parallel
  const [shifts, settings, profile] = yield* Effect.all(
    [
      shiftsService.getShifts(userId),
      settingsService.getUserSettings(userId),
      subscription.getUserProfile(userId),
    ],
    { concurrency: 3 }
  )

  return { shifts, settings, profile }
})
```

### 5. Branded Types for Validation

```typescript
import { Schema } from "effect"

// Define branded type
export const ISODateString = Schema.String.pipe(
  Schema.pattern(/^\d{4}-\d{2}-\d{2}$/),
  Schema.brand("ISODateString")
)

export type ISODateString = typeof ISODateString.Type

// Use in validation
const program = Schema.decodeUnknown(ISODateString)("2025-01-15")
const date = await Effect.runPromise(program) // Type: ISODateString
```

### 6. Caching with Effect.Cache

```typescript
import { Cache, Duration } from "effect"

const cache = yield* Cache.make({
  capacity: 100,
  timeToLive: Duration.minutes(10),
  lookup: (key: string) =>
    Effect.gen(function* () {
      const supabase = yield* SupabaseService
      const data = yield* supabase.query(...)
      return data
    })
})

// Automatic deduplication and caching
const data = yield* cache.get("user-123")
```

### 7. Wrapping Side Effects

```typescript
import { Effect } from "effect"

// Wrap Next.js cache operations
export const invalidateCacheEffect = (userId: string) =>
  Effect.sync(() => {
    revalidateTag(`user-${userId}`, "max")
    revalidatePath("/", "layout")
  })

// Use in Effect pipeline
yield* invalidateCacheEffect(userId)
```

### 8. Promise Wrappers for Next.js

```typescript
// Effect-based internal implementation
async function getUserDataInternal(userId: string): Promise<Data> {
  const program = Effect.gen(function* () {
    const service = yield* MyService
    const data = yield* service.getData(userId)
    return data
  }).pipe(Effect.provide(MyServiceLive), Effect.scoped)

  try {
    return await Effect.runPromise(program)
  } catch (error) {
    logger.error("Failed to get user data:", error)
    return null
  }
}

// Export Promise-based API for Next.js
export const getUserData = cache(getUserDataInternal)
```

## Testing with Effect

### Unit Tests with Effect.runPromise

```typescript
import { Effect } from "effect"
import { computeShift } from "@/lib/payroll/effect"

it("should compute shift correctly", async () => {
  const program = computeShift(shift, settings, rules)
  const result = await Effect.runPromise(program)

  expect(result.gross).toBeGreaterThan(0)
})

it("should handle validation errors", async () => {
  const program = computeShift(invalidShift, settings, rules)
  const result = await Effect.runPromise(Effect.either(program))

  expect(result._tag).toBe("Left")
  if (result._tag === "Left") {
    expect(result.left._tag).toBe("ValidationError")
  }
})
```

### Property-Based Tests with fast-check

```typescript
import { fc } from "@fast-check/vitest"

it("should never have paid hours exceed duration hours", () => {
  fc.assert(
    fc.property(shiftArbitrary, async (shift) => {
      const program = computeShift(shift, settings, [])
      const result = await Effect.runPromise(program)

      expect(result.paidHours).toBeLessThanOrEqual(result.durationHours)
    })
  )
})
```
