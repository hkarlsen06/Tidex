# iOS Shifts Tab Issues to Fix

## Status Summary

| Issue | Status | Fix Applied |
|-------|--------|-------------|
| 1. NextShiftCountdownCard Location | ✅ FIXED | Removed from ShiftsView.swift |
| 2. Today's Shift Countdown Text | ⏳ PENDING | Need to add countdown text below today's shift |
| 3. TodayPlaceholderCard | ⏳ PENDING | Need to create and insert placeholder |
| 4. Swipe Action Bleeding | ✅ FIXED | Action backgrounds hidden when offset=0 |
| 5. Swipe Gestures | ✅ FIXED | Using highPriorityGesture with proper thresholds |
| 6. Cards Cut Off | ✅ FIXED | Removed GeometryReader/minHeight/clipped |
| 7. Pull-to-Refresh | ✅ FIXED | Using native .refreshable() modifier |
| 8. Tap Sensitivity | ✅ FIXED | Using ScrollFriendlyButtonStyle |
| 9. Week Number Inset | ✅ FIXED | Increased padding to 6pt/4pt |
| 10. Calendar/List View Toggle | ✅ FIXED | Added toggle button in header |
| 11. Slow Card Animations | ✅ FIXED | Changed stagger 0.05→0.03, slide from left |

---

## Remaining Tasks

### 2. Today's Shift Countdown Text
- **Issue**: Shifts for today should show countdown text underneath
- **Expected**: Like Next.js ShiftsView - countdown text below today's shift card
- **Fix**: Add countdown text display below ShiftRowCard for today's shift (isToday && isNextUpcoming)
- **Reference**: components/shifts/ShiftsView.tsx lines 401-403

### 3. TodayPlaceholderCard for Empty Today
- **Issue**: When there are no shifts today, an empty placeholder card should appear in chronological position
- **Expected**: Like Next.js TodayPlaceholderCard.tsx - shows today's date with "——" for earnings
- **Fix**: Create TodayPlaceholderCard.swift and insert it in the shifts list at the right position
- **Reference**: components/shifts/TodayPlaceholderCard.tsx

---

## Completed Fixes

### 1. NextShiftCountdownCard Location ✅
- **Change**: Removed NextShiftCountdownCard section from ShiftsView.swift shiftsContent
- **File**: ShiftsView.swift

### 4. Swipe Action Colors Bleeding ✅
- **Change**: Action backgrounds now only visible when offset > 0 (edit) or offset < 0 (delete)
- **File**: SwipeableShiftCard.swift

### 5. Swipe Gestures ✅
- **Change**:
  - Using `highPriorityGesture` instead of regular gesture
  - Fixed actionWidth to 80pt instead of percentage
  - Proper horizontal vs vertical detection (1.5x ratio)
  - Velocity-based trigger detection
- **File**: SwipeableShiftCard.swift

### 6. Cards Cut Off ✅
- **Change**: Removed GeometryReader, minHeight, and .clipped() that were causing clipping
- **File**: SwipeableShiftCard.swift

### 7. Pull-to-Refresh ✅
- **Change**: Replaced custom PullToRefreshContainer with native `.refreshable()` modifier
- **File**: ShiftsView.swift

### 8. Tap Sensitivity ✅
- **Change**: Added ScrollFriendlyButtonStyle that uses opacity animation instead of scale
- **File**: ShiftRowCard.swift

### 9. Week Number Inset ✅
- **Change**: Increased padding from 3pt/2pt to 6pt/4pt
- **File**: ShiftsCalendarView.swift (ShiftsCalendarDayCell)

### 10. Calendar/List View Toggle ✅
- **Change**:
  - Added `showListView` state variable
  - Added toggle button in toolbar (left of title)
  - Button shows list icon when in calendar mode, calendar icon when in list mode
  - Animated symbol transition using `.contentTransition(.symbolEffect(.replace))`
  - Separate content views for calendar vs list modes
- **File**: ShiftsView.swift

### 11. Slow Card Animations ✅
- **Change**:
  - Changed stagger delay from 0.05s to 0.03s (matching web app)
  - Changed animation from vertical slide to horizontal slide from left (like web)
  - Changed spring response from 0.4 to 0.25 for snappier feel
- **File**: ScrollAppearModifier.swift
