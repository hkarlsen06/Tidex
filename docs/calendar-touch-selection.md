# Calendar touch selection issues

This doc describes how to diagnose and fix the "mis-targeted tap" problem on touch devices where fast taps on adjacent day cells unselect the first cell or fail to select the next one. It also covers scroll locking during long-press selection.

## Symptoms
- Fast taps on neighboring days select/unselect the wrong cell.
- The first cell becomes unselected and the second never selects.
- Long-press selection gets canceled when the page scrolls.
- Selection works on desktop but is flaky on mobile.

## Root cause
- On touch devices, the default click target can be influenced by movement, browser heuristics, or the small gaps between cells.
- `react-day-picker` attaches selection to the button click, which may fire on a different element than the user intended.
- Scroll can cancel the pointer sequence, causing `pointercancel` and lost selection.
- `data-day` is present on the day wrapper element (not the button) unless you add it yourself.

## Where the fix lives
- `components/app/ShiftsCalendar.tsx` (main shifts calendar with paging + long-press selection)
- `components/app/SelectDatesCalendar.tsx` (shifts/add date picker)

Key helpers and patterns:
- `hitTestDayCell(x, y)` using `document.elementFromPoint` and an inner inset
- `pointerdown`/`pointermove`/`pointerup` on the calendar container
- `suppressClickRef` + `onClickCapture` to avoid double toggles
- Scroll locking during selection/paging (non-passive touch listeners)

## Diagnostic steps
1. Reproduce on a touch device with rapid taps on adjacent day cells.
2. Log `elementFromPoint` and compare to `event.target` to see mismatches.
3. Inspect the DOM:
   - Confirm which element has `data-day`.
   - Confirm gaps/padding around buttons.
4. Check for `pointercancel` events during selection (usually caused by scroll).

## Fix checklist
### 1) Reliable hit testing
- Use `elementFromPoint` and resolve the nearest day element.
- Apply an inner inset (ex: 4px) so taps near borders do not mis-target.
- Example (simplified):

```ts
const hitTestDayCell = (x: number, y: number) => {
  const target = document.elementFromPoint(x, y);
  const dayEl = target?.closest("[data-day]");
  if (!dayEl) return null;
  const rect = dayEl.getBoundingClientRect();
  if (x < rect.left + inset || x > rect.right - inset) return null;
  if (y < rect.top + inset || y > rect.bottom - inset) return null;
  return dayEl.getAttribute("data-day") as ISODate | null;
};
```

### 2) Resolve selection on pointerup
- Capture `pointerdown` to store start position and start cell.
- On `pointerup`, resolve the cell using `hitTestDayCell`.
- Use the `endCell ?? startCell` fallback to handle edge cases.

### 3) Suppress native click
- If you handle selection manually, prevent the browser click from toggling again.
- Use `onClickCapture` with a ref flag:

```ts
if (suppressClickRef.current) {
  event.preventDefault();
  event.stopPropagation();
}
```

### 4) Lock scrolling during selection
- For long-press selection, stop the page from scrolling:
  - Use `touch-action: none` while selecting.
  - Add a non-passive `touchmove` listener (capture) and `preventDefault` when selecting.
- If you see `pointercancel`, the scroll lock is not strong enough.

## Notes and pitfalls
- `react-day-picker` applies `data-day` to the day wrapper, not the button. If you use `closest("button[data-day]")`, add `data-day` to your custom day button or update the selector.
- Passive `touchmove` listeners cannot call `preventDefault`. Make sure the listener is `passive: false`.
- If you keep default `onSelect`, always suppress the click after manual selection to avoid double toggles.

## Quick validation
- Tap two adjacent days quickly: each tap should select the intended cell.
- Long-press, then drag vertically and horizontally: selection should update and the page should not scroll.
- Trigger selection near the cell edges: taps should be ignored outside the inner inset.
