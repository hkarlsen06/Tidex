# Testing Patterns

**Analysis Date:** 2026-01-13

## Test Framework

**Runner:**
- Vitest 4.0.17
- Config: `vitest.config.ts` in project root

**Assertion Library:**
- Vitest built-in expect
- Jest DOM matchers via `@testing-library/jest-dom` 6.9.1
- Matchers: `toBe`, `toEqual`, `toThrow`, `toMatchObject`

**Run Commands:**
```bash
pnpm test                              # Run all tests
pnpm test -- --watch                   # Watch mode
pnpm test -- path/to/file.test.ts     # Single file
pnpm test:coverage                     # Coverage report
pnpm test:ui                           # Interactive UI mode
```

## Test File Organization

**Location:**
- Centralized in `tests/` directory
- `tests/integration/` - Integration tests
- `tests/e2e/` - Playwright E2E tests
- `tests/setup.ts` - Shared test setup

**Naming:**
- Unit/integration: `{name}.test.ts`
- E2E: `{name}.spec.ts`
- No distinction in filename between unit/integration

**Structure:**
```
tests/
├── integration/
│   ├── payroll-integration.test.ts
│   ├── calc.test.ts
│   ├── snapshot.test.ts
│   └── date-utils.test.ts
├── e2e/
│   └── auth-wake-refresh.spec.ts
├── setup.ts
└── tsconfig.json
```

## Test Structure

**Suite Organization:**
```typescript
import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';

describe('ModuleName', () => {
  describe('functionName', () => {
    beforeEach(() => {
      // reset state
    });

    it('should handle valid input', () => {
      // arrange
      const input = createTestInput();

      // act
      const result = functionName(input);

      // assert
      expect(result).toEqual(expectedOutput);
    });

    it('should throw on invalid input', () => {
      expect(() => functionName(null)).toThrow('Invalid input');
    });
  });
});
```

**Patterns:**
- Use `beforeEach` for per-test setup, avoid `beforeAll`
- Use `afterEach` from Testing Library for cleanup
- Explicit arrange/act/assert comments in complex tests
- One assertion focus per test (multiple expects OK)

## Mocking

**Framework:**
- Vitest built-in mocking (vi)
- Module mocking via `vi.mock()` at top of test file

**Patterns:**
```typescript
import { vi } from 'vitest';
import { externalFunction } from './external';

// Mock module
vi.mock('./external', () => ({
  externalFunction: vi.fn()
}));

describe('test suite', () => {
  it('mocks function', () => {
    const mockFn = vi.mocked(externalFunction);
    mockFn.mockReturnValue('mocked result');

    // test code using mocked function

    expect(mockFn).toHaveBeenCalledWith('expected arg');
  });
});
```

**What to Mock:**
- External API calls
- Database queries (Supabase)
- Environment variables (process.env)
- Date/time (vi.useFakeTimers)

**What NOT to Mock:**
- Internal pure functions
- Simple utilities
- TypeScript types

## Fixtures and Factories

**Test Data:**
```typescript
// Factory functions in test file
const createShift = (overrides?: Partial<ShiftRow>): ShiftRow => ({
  id: 'test-shift-1',
  user_id: 'test-user',
  shift_date: '2025-01-15',
  start_time: '09:00',
  end_time: '17:00',
  ...overrides,
});

const createSettings = (overrides?: Partial<UserSettings>): UserSettings => ({
  pause_deduction_enabled: true,
  pause_deduction_method: 'proportional',
  pause_threshold_hours: 5.5,
  pause_deduction_minutes: 30,
  ...overrides,
});
```

**Location:**
- Factory functions: Define in test file near usage
- Shared fixtures: `tests/fixtures/` if needed

## Coverage

**Requirements:**
- No enforced coverage target
- Coverage tracked for awareness
- Focus on critical paths (payroll, auth)

**Configuration:**
- Vitest coverage via v8 (built-in)
- Excludes: `*.test.ts`, config files, `*.d.ts`, `node_modules/`, `tests/`

**View Coverage:**
```bash
pnpm test:coverage
open coverage/index.html
```

## Test Types

**Unit Tests:**
- Test single function in isolation
- Mock all external dependencies
- Fast: each test <100ms
- Examples: `calc.test.ts`, `date-utils.test.ts`

**Integration Tests:**
- Test multiple modules together
- Mock only external boundaries (Supabase)
- Examples: `payroll-integration.test.ts` (tests payroll + snapshots)

**E2E Tests:**
- Framework: Playwright 1.57.0
- Config: `playwright.config.ts`
- Location: `tests/e2e/`
- Examples: `auth-wake-refresh.spec.ts`

**Property-Based Tests:**
- Framework: fast-check via `@fast-check/vitest` 0.2.4
- Usage: Payroll invariant testing
- Pattern: Verify properties hold for all inputs

## Common Patterns

**Async Testing:**
```typescript
it('should handle async operation', async () => {
  const result = await asyncFunction();
  expect(result).toBe('expected');
});
```

**Error Testing:**
```typescript
it('should throw on invalid input', () => {
  expect(() => parse(null)).toThrow('Cannot parse null');
});

// Async error
it('should reject on failure', async () => {
  await expect(asyncCall()).rejects.toThrow('error message');
});
```

**Effect Testing:**
```typescript
import { Effect } from 'effect';
import { computeShift } from '@/lib/payroll/effect';

it('should compute shift correctly', async () => {
  const program = computeShift(shift, settings, rules);
  const result = await Effect.runPromise(program);

  expect(result.gross).toBeGreaterThan(0);
});

it('should handle validation errors', async () => {
  const program = computeShift(invalidShift, settings, rules);
  const result = await Effect.runPromise(Effect.either(program));

  expect(result._tag).toBe('Left');
  if (result._tag === 'Left') {
    expect(result.left._tag).toBe('ValidationError');
  }
});
```

**Realistic Domain Tests:**
```typescript
describe('Realistic Norwegian shift scenarios', () => {
  it('should calculate regular weekday shift with preset tariff', () => {
    // Wednesday 09:00-17:00, wage level 3, with 30min break
    const shift = createShift({
      shift_date: '2025-01-15', // Wednesday
      start_time: '09:00',
      end_time: '17:00',
    });

    const result = computeShift(shift, settings, [], snapshot);

    expect(result.durationHours).toBe(8);
    expect(result.paidHours).toBe(7.5); // 8 - 0.5 break
    expect(result.basePay).toBe(1405.95); // 7.5 * 187.46
  });
});
```

**Snapshot Testing:**
- Not used in this codebase
- Prefer explicit assertions for clarity

## Test Setup (`tests/setup.ts`)

```typescript
import { expect, afterEach } from 'vitest';
import { cleanup } from '@testing-library/react';
import * as matchers from '@testing-library/jest-dom/matchers';

// Extend Vitest expect with jest-dom matchers
expect.extend(matchers);

// Clean up after each test
afterEach(() => {
  cleanup();
});

// Mock environment variables
process.env.NEXT_PUBLIC_SUPABASE_URL = 'https://test.supabase.co';
process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY = 'test-key';
process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY = 'test-turnstile';
```

## Test Coverage by Area

**Well Covered:**
- Payroll calculations (683 lines) - `payroll-integration.test.ts`
- Date utilities (518 lines) - `date-utils.test.ts`
- Snapshot logic (425 lines) - `snapshot.test.ts`
- Core payroll (403 lines) - `calc.test.ts`

**Coverage Gaps:**
- API route handlers (`app/api/*`) - No tests
- Server actions (`*_actions/*.ts`) - No tests
- DAL functions - Limited integration testing
- Chat executor - No tests
- Sharing service - No tests

---

*Testing analysis: 2026-01-13*
*Update when test patterns change*
