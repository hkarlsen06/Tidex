# Test Coverage Report

This document provides an overview of the test suite for the Tidex application.

## Test Statistics

- **Total Test Files**: 7
- **Total Tests**: 152
- **Status**: ✅ All passing

## Test Organization

### Unit Tests (132 tests)

#### Validation (42 tests)
- **shift-validators.test.ts** (8 tests)
  - ISO date format validation (YYYY-MM-DD)
  - Time format validation (HH:MM)

- **phone.test.ts** (34 tests)
  - Norwegian phone number validation (8 digits)
  - E.164 format normalization (+47XXXXXXXX)
  - Display formatting (XX XXX XXX)
  - Email validation
  - Input type detection
  - Integration workflows

#### Payroll System (90 tests)
- **calc.test.ts** (19 tests)
  - Basic shift calculations
  - Break deductions
  - Supplement calculations
  - Wage rate resolution
  - Cross-midnight shifts
  - Precision and rounding

- **breaks.test.ts** (18 tests)
  - Threshold-based break deduction
  - Proportional deduction method
  - End-of-shift deduction method
  - Base-only deduction method
  - Edge cases and audit trail

- **periods.test.ts** (26 tests)
  - Wage period building with supplements
  - Fixed rate vs percentage supplements
  - Overlapping supplement handling
  - Cross-midnight shifts
  - Weekday filtering
  - Norwegian tariff rules

- **snapshot.test.ts** (27 tests)
  - Wage snapshot resolution
  - Supplement rules snapshotting
  - Preset vs custom wage handling
  - Priority handling
  - Edge cases

### Integration Tests (20 tests)
- **payroll-integration.test.ts** (20 tests)
  - Realistic Norwegian shift scenarios
  - Weekend and evening shifts
  - Break deduction scenarios
  - Wage level scenarios (apprentice to senior)
  - Historical accuracy with snapshots
  - Complex real-world scenarios
  - Production edge cases

## Coverage by Module

| Module | Files | Tests | Coverage |
|--------|-------|-------|----------|
| Validation | 2 | 42 | ✅ Complete |
| Payroll Core | 4 | 90 | ✅ Complete |
| Integration | 1 | 20 | ✅ Complete |
| **Total** | **7** | **152** | **✅ Complete** |

## Running Tests

```bash
# Run all tests once
npm run test

# Run tests in watch mode
npm run test:watch

# Run tests with UI
npm run test:ui

# Run tests with coverage report
npm run test:coverage
```

## Test Framework

- **Framework**: Vitest 4.0.7
- **Testing Library**: @testing-library/react 16.3.0
- **DOM Matchers**: @testing-library/jest-dom 6.9.1
- **Environment**: jsdom 27.1.0

## Key Testing Principles

1. **Isolation**: Each test is independent and can run in any order
2. **Clarity**: Descriptive test names that explain what is being tested
3. **Structure**: Arrange-Act-Assert pattern for consistency
4. **Coverage**: Tests cover happy paths, edge cases, and error conditions
5. **Realism**: Integration tests use real-world scenarios
6. **Maintainability**: Helper functions for creating test data

## Critical Business Logic Coverage

### Norwegian Labor Regulations
- ✅ Weekday evening supplements (18:00-21:00, 21:00-23:59)
- ✅ Saturday supplements (13:00-15:00, 15:00-18:00, 18:00-23:59)
- ✅ Sunday full-day supplement (00:00-23:59)
- ✅ Break deduction thresholds and methods
- ✅ Cross-midnight shift handling

### Wage Calculation Accuracy
- ✅ Preset wage levels (-2 to 6)
- ✅ Custom wage rates
- ✅ Historical wage snapshots
- ✅ Precision: 3 decimal places for hours, 2 for currency
- ✅ Rounding at different calculation stages

### Data Validation
- ✅ Norwegian phone numbers (8 digits, E.164 format)
- ✅ Email addresses
- ✅ ISO date format (YYYY-MM-DD)
- ✅ Time format (HH:MM)
- ✅ Input sanitization and normalization

## Maintenance

To add new tests:
1. Create test file in appropriate directory (`tests/unit/` or `tests/integration/`)
2. Use `.test.ts` or `.spec.ts` extension
3. Follow existing test structure and naming conventions
4. Update this document with new test counts

Last updated: 2025-11-04
