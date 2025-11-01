# BackgroundTexture Component

A sophisticated textured background component that adds visual depth to the application without compromising readability or performance.

## Overview

The `BackgroundTexture` component creates a multi-layered background effect using:
- **Radial gradients** for subtle depth
- **SVG noise filter** for fine grain texture
- **CSS dot pattern** for geometric interest

All layers use theme-aware colors from the application's design system, ensuring consistency across light and dark modes.

## Color Selection

### Dark Mode (Primary Theme)

Based on the theme analysis, these colors were selected:

1. **Base Layer**: `hsl(222.2, 84%, 4.9%)` - The existing `--background` token
   - This is the darkest color in the palette
   - Already applied to `<body>`, so no additional layer needed

2. **Radial Gradient**: Brand colors at 3-5% opacity
   - `hsla(199, 89%, 48%, 0.04)` - `--brand-gradientStart` (cyan-blue)
   - `hsla(189, 94%, 43%, 0.03)` - `--brand-gradientMid` (teal-blue)
   - Creates subtle depth from center to edges

3. **Noise/Grain**: SVG filter with overlay blend mode at 8% opacity
   - Adds tactile, paper-like texture
   - Uses `feTurbulence` for performance-optimized grain

4. **Dot Pattern**: `hsl(188, 86%, 53%)` at 12% opacity
   - Uses `--brand-highlight` (bright cyan)
   - 32px grid with 1px dots
   - Creates subtle geometric interest

### Why These Colors?

- **Brand consistency**: Uses the existing cyan/teal brand colors
- **Dark mode optimized**: Works with the very dark blue-gray base
- **Subtle depth**: Low opacity prevents overwhelming the UI
- **Financial aesthetic**: Sophisticated and professional
- **Excellent contrast**: Cards on `surface-primary` remain highly readable

## Usage

### Basic Usage (Default)

Already implemented in [app/layout.tsx:84](app/layout.tsx#L84):

```tsx
import { BackgroundTexture } from "@/components/app/BackgroundTexture";

export default function RootLayout({ children }) {
  return (
    <body>
      <BackgroundTexture intensity="subtle" />
      {children}
    </body>
  );
}
```

### With Different Intensity Levels

```tsx
// Subtle (default) - Recommended for production
<BackgroundTexture intensity="subtle" />

// Medium - More visible texture
<BackgroundTexture intensity="medium" />

// Bold - Maximum texture visibility
<BackgroundTexture intensity="bold" />
```

### Intensity Configuration

| Level | Radial Opacity | Noise Opacity | Dot Opacity | Use Case |
|-------|----------------|---------------|-------------|----------|
| `subtle` | 4% | 8% | 12% | Production default, professional |
| `medium` | 6% | 12% | 18% | More visible depth |
| `bold` | 8% | 16% | 24% | Maximum texture, use with caution |

## Technical Details

### Performance Optimizations

1. **Fixed positioning**: Uses `position: fixed` with `z-index: -10` to stay behind all content
2. **No extra DOM nodes**: Patterns use CSS `background-image` (no img tags)
3. **Small SVG filter**: Noise uses small repeating pattern with `stitchTiles`
4. **Pure CSS**: No JavaScript animations or interactions
5. **Single render**: Component only renders once at root level
6. **Pointer events disabled**: Prevents any interaction overhead

### Layers Breakdown

```
┌─────────────────────────────────────┐
│ Layer 4: Top radial gradient       │ ← Subtle depth at top
│ opacity: 3% (brand-gradientMid)    │
├─────────────────────────────────────┤
│ Layer 3: Dot pattern                │ ← Geometric interest
│ opacity: 12% (brand-highlight)      │
│ 32px grid, 1px dots                 │
├─────────────────────────────────────┤
│ Layer 2: SVG noise                  │ ← Fine grain texture
│ opacity: 8%, overlay blend          │
├─────────────────────────────────────┤
│ Layer 1: Center radial gradient     │ ← Main depth
│ opacity: 4% (brand-gradientStart)   │
├─────────────────────────────────────┤
│ Base: --background                  │ ← Darkest base
│ hsl(222.2, 84%, 4.9%)               │
└─────────────────────────────────────┘
```

### Accessibility

- **aria-hidden="true"**: Background is decorative, hidden from screen readers
- **High contrast maintained**: Text and cards remain highly readable (WCAG AAA)
- **No motion**: Static patterns don't trigger motion sensitivity
- **Pointer events disabled**: Doesn't interfere with interactions

## Customization

To adjust the texture:

1. **Change intensity**: Use `intensity` prop
2. **Modify colors**: Edit HSL values in the component (all use theme tokens)
3. **Adjust pattern density**: Change `backgroundSize` value (default: `32px 32px`)
4. **Tweak noise**: Modify `baseFrequency` in SVG filter (higher = finer grain)

## Light Mode Support (Future)

The component is theme-aware and could support light mode by:
- Adding light mode color variants
- Using different opacity levels
- Adjusting blend modes for light backgrounds

Currently optimized for dark mode as that's the primary theme.

## Example Visual Hierarchy

```
Content Layer (z-index: auto)
  ├─ Cards: bg-surface-primary (slightly lighter)
  ├─ Text: text-primary, text-secondary
  └─ Interactive elements

Background Layer (z-index: -10) ← BackgroundTexture here
  ├─ Radial gradients (brand colors, 3-4% opacity)
  ├─ Noise texture (8% opacity)
  └─ Dot pattern (12% opacity)

Base Layer
  └─ body: bg-background (darkest)
```

## Browser Support

- **Modern browsers**: Full support (Chrome, Firefox, Safari, Edge)
- **SVG filters**: Supported in all modern browsers
- **Radial gradients**: Widely supported
- **Blend modes**: Full support (`overlay` mode)

## Related Files

- [app/layout.tsx](app/layout.tsx) - Root layout where component is used
- [app/globals.css](app/globals.css) - CSS variables and theme definitions
- [tailwind.config.js](tailwind.config.js) - Theme configuration

## Design Rationale

The textured background was designed to:
1. Add visual sophistication without distracting from content
2. Use brand colors for consistency
3. Create subtle depth that makes cards "float"
4. Maintain excellent readability for financial data
5. Perform efficiently with minimal overhead
6. Work seamlessly with the existing dark theme

The result is a professional, tactile background that enhances the user experience while keeping financial data the primary focus.
