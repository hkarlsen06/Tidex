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

# Check 1: Verify singleton pattern in lib/supabase/client.ts
echo "1️⃣  Checking browser client singleton..."
if grep -q "let browserClient:" lib/supabase/client.ts && grep -q "if (browserClient) return browserClient" lib/supabase/client.ts; then
    echo -e "${GREEN}✓ Singleton pattern implemented${NC}"
else
    echo -e "${RED}✗ Singleton pattern NOT found${NC}"
    exit 1
fi

# Check 2: Verify global logging in app/supabase-listener.tsx
echo "2️⃣  Checking global auth event logging..."
if grep -q "\[SUPABASE AUTH\]" app/supabase-listener.tsx; then
    echo -e "${GREEN}✓ Global logging implemented${NC}"
else
    echo -e "${RED}✗ Global logging NOT found${NC}"
    exit 1
fi

# Check 3: Verify no useMemo in login page
echo "3️⃣  Checking login page uses singleton..."
if ! grep -q "useMemo.*createSupabaseBrowserClient" app/\(auth\)/login/page.tsx; then
    echo -e "${GREEN}✓ Login page uses singleton (no useMemo)${NC}"
else
    echo -e "${RED}✗ Login page still uses useMemo${NC}"
    exit 1
fi

# Check 4: Verify reduced SSR calls in layout
echo "4️⃣  Checking layout uses session.user..."
if grep -q "const user = session?.user" app/\(app\)/layout.tsx; then
    echo -e "${GREEN}✓ Layout uses session.user (reduced SSR calls)${NC}"
else
    echo -e "${RED}✗ Layout still calls auth.getUser()${NC}"
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
echo "  3. Check browser console for [SUPABASE AUTH] logs"
echo "  4. Read REPORT.md for full details"
echo ""
