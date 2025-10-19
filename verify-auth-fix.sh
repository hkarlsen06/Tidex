#!/bin/bash

# Auth Fix Verification Script
# Run this script to verify all auth fixes are working correctly

set -e

echo "🔍 Auth Fix Verification Script"
echo "================================"
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check 1: Verify shared browser client export
echo "1️⃣  Checking browser client export..."
if grep -q "export const supabase" lib/supabase/browser.ts && grep -q "createBrowserClient" lib/supabase/browser.ts; then
    echo -e "${GREEN}✓ Shared browser client exported${NC}"
else
    echo -e "${RED}✗ Shared browser client export NOT found${NC}"
    exit 1
fi

# Check 2: Verify Supabase listener uses shared client
echo "2️⃣  Checking Supabase listener..."
if grep -q "from \"@/lib/supabase/browser\"" app/supabase-listener.tsx && grep -q "router.refresh()" app/supabase-listener.tsx; then
    echo -e "${GREEN}✓ Supabase listener uses shared client${NC}"
else
    echo -e "${RED}✗ Supabase listener NOT using shared client${NC}"
    exit 1
fi

# Check 3: Verify no legacy browser client usage remains
echo "3️⃣  Checking for legacy browser client usage..."
if ! rg -q "createSupabaseBrowserClient" app lib components; then
    echo -e "${GREEN}✓ Legacy browser client removed${NC}"
else
    echo -e "${RED}✗ Legacy browser client references still present${NC}"
    exit 1
fi

# Check 4: Verify no manual setSession usage
echo "4️⃣  Checking for manual setSession usage..."
if ! rg -q "auth\.setSession" app lib components; then
    echo -e "${GREEN}✓ Manual setSession calls removed${NC}"
else
    echo -e "${RED}✗ Manual setSession calls still present${NC}"
    exit 1
fi

# Check 5: Verify test file exists
echo "5️⃣  Checking E2E test file..."
if [ -f "tests/e2e/auth-stability.spec.ts" ]; then
    echo -e "${GREEN}✓ E2E test file exists${NC}"
else
    echo -e "${RED}✗ E2E test file NOT found${NC}"
    exit 1
fi

# Check 6: Verify documentation exists
echo "6️⃣  Checking documentation..."
if [ -f "REPORT.md" ] && [ -f "TESTS.md" ] && [ -f "AUTH_FIX_SUMMARY.md" ]; then
    echo -e "${GREEN}✓ All documentation files present${NC}"
else
    echo -e "${RED}✗ Some documentation files missing${NC}"
    exit 1
fi

# Check 7: TypeScript build
echo "7️⃣  Running TypeScript build..."
if npm run build > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Build succeeds${NC}"
else
    echo -e "${RED}✗ Build failed (run 'npm run build' for details)${NC}"
    exit 1
fi

echo ""
echo "================================"
echo -e "${GREEN}✅ All verification checks passed!${NC}"
echo ""
echo "Next steps:"
echo "  1. Run E2E tests: npx playwright test tests/e2e/auth-stability.spec.ts"
echo "  2. Test manually: npm run dev and login"
echo "  3. Verify browser auth flows manually"
echo "  4. Read REPORT.md for full details"
echo ""
