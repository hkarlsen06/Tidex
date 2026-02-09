# Liquid Glass Findings (iOS 26)

Last updated: 2026-02-09

This document captures web-researched findings for Liquid Glass behavior in iOS 26, and how to apply them safely in Tidex.

## Scope

- Main month picker bar (`ios/TidexApp/App/MainTabView.swift`)
- Calendar view-mode toggle (`ios/TidexApp/Shared/Components/Calendar/CalendarViewModeToggle.swift`)
- Add Shift mode toggle (`ios/TidexApp/Features/AddShift/Components/ShiftModeToggle.swift`)

## Official Guidance (Apple)

### 1) Use `GlassEffectContainer` for adjacent glass elements

Apple guidance indicates grouped nearby glass elements should share a container for visual correctness and better performance/sampling behavior.

Implication for Tidex:
- Use a single container for bars with multiple adjacent glass controls.
- Prefer stable geometry inside that container.

### 2) Use `glassEffectID` only when you need cross-state morphing

Apple positions `glassEffectID` as a way to tell the system two elements "belong together" across transitions/state changes.

Implication for Tidex:
- Do not apply `glassEffectID` by default to all glass controls.
- Use it only when morphing semantics are clear and geometry remains stable.

### 3) Prefer glass-specific transition control for add/remove effects

Apple provides `GlassEffectTransition` and `glassEffectTransition(_:)` for effect lifecycle transitions.

Implication for Tidex:
- Avoid stacking aggressive custom SwiftUI transitions on glass-backed views (for example `.scale + .opacity`) when morphing is active.

### 4) Legibility expectations depend on text being inside the glass-composited view

Apple notes that text inside glass gets adaptive treatment for readability.

Implication for Tidex:
- If text appears "behind" glass, move the composition so the label content is part of the selected glass element or rendered above a single moving underlay.

## Symptoms Observed In Tidex

### A) Broken month-picker morph path ("orbit"/"carousel" behavior)

Likely cause:
- Multiple transition systems were combined:
  - conditional insertion/removal
  - per-child scale/opacity transitions
  - parent movement transition
  - glass morphing semantics

Result:
- Pathological transform composition in some iOS 26 rendering paths.

### B) Toggle text behind glass + oversize artifacts

Likely cause:
- Glass applied as a separate background layer while labels are composed as siblings.
- Additional geometry effects can reorder compositing unexpectedly.

Result:
- Legibility issues and occasional oversized/ghost-like pill behavior.

## Working Patterns For Tidex

### Month picker bar

- Keep adjacent controls grouped.
- Prefer simple `.opacity` transitions for conditional glass controls.
- Avoid per-child scale transitions on glass-backed controls.
- Use `interactive` for truly interactive glass controls.
- Only reintroduce `glassEffectID` where morph pairing is explicit and stable.

### Segmented/toggle controls

- Use a **single moving glass underlay pill** behind labels.
- Keep labels/buttons above the underlay.
- Avoid creating separate glass capsules as sibling background layers per segment when that causes z-order/compositing artifacts.

## Recommended A/B Matrix For Future Regressions

### Month picker

1. A: keep container, no `glassEffectID`, only `.opacity` transitions  
2. B: add `glassEffectID` only for one pair of stable elements, still no scale transitions

Interpretation:
- If A is stable and B regresses, issue is likely morph pairing/geometry mismatch.

### Toggle

1. A: single moving underlay pill  
2. B: per-segment selected capsule

Interpretation:
- If A is stable and B regresses, issue is likely compositing/z-order interaction.

## Primary Sources

- WWDC25 - Build a SwiftUI app with the new design  
  https://developer.apple.com/videos/play/wwdc2025/323/
- Meet with Apple - Explore the biggest updates from WWDC25  
  https://developer.apple.com/videos/play/meet-with-apple/201/
- WWDC25 - Meet Liquid Glass  
  https://developer.apple.com/videos/play/wwdc2025/219/
- Applying Liquid Glass to custom views  
  https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- `GlassEffectContainer`  
  https://developer.apple.com/documentation/swiftui/glasseffectcontainer
- `glassEffectID(_:in:)`  
  https://developer.apple.com/documentation/swiftui/view/glasseffectid(_:in:)
- `GlassEffectTransition`  
  https://developer.apple.com/documentation/swiftui/glasseffecttransition
- `glassEffectTransition(_:)`  
  https://developer.apple.com/documentation/swiftui/view/glasseffecttransition(_:)

## Relevant Forum Threads (Known Glitch Family)

- https://developer.apple.com/forums/thread/808720
- https://developer.apple.com/forums/thread/799491
- https://developer.apple.com/forums/thread/808017
- https://developer.apple.com/forums/thread/811012
- https://developer.apple.com/forums/thread/787594
- https://developer.apple.com/forums/thread/800801

