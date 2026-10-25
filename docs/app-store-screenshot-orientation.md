# App Store screenshot phone orientation

Notes on the 3D phones that `scripts/render-3d-screenshots.mjs` draws, from research done for Paeonia on 2026-10-25. Paeonia uses the same renderer.

## Apple's rules

Apple's [Marketing Resources and Identity Guidelines](https://developer.apple.com/app-store/marketing/guidelines/) forbid tilting iPhone images, adding reflections, shadows or highlights, and "Rendering in 3D or creating any simulation of an Apple product". `phone3d.mjs` does all of these. The [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) and the [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) say nothing about angles or 3D. Tidex's 3D screenshots passed App Review without trouble, and Calm and Paired ship tilted phones too, so review does not enforce the marketing text.

## What the evidence says

- No published A/B test compares tilted or framed phones with flat screenshots. Choosing angles is a matter of taste, not data.
- Search results show the first one to three portrait screenshots ([Apple](https://developer.apple.com/app-store/product-page/)), so panel 1 carries the most weight.

## Tidex's angles are the reference

`scripts/assets/app-store/tidex-3d.json` is the look the developer likes. It reads as balanced for three reasons:

- The hero has yaw and no roll (`[0, 14, 0]`). The screen turns for depth, but its lines stay level with the headline above it.
- Where a phone has roll, the roll is small and has the same sign as the yaw (`[0, 24, 6]`).
- The phones relate to each other. Two phones face inward toward a straight phone that bridges their shared border.

A single rule applied to every panel (each phone turned toward the next one, with roll against the yaw) looked misaligned and was rejected in Paeonia's round 4. Compose the phones as a set instead.
