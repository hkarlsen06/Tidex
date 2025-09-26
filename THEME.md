# Theme Tokens

This project centralizes color usage through Tailwind's theme extension. All shared colors live in `tailwind.config.js` under `theme.extend.colors` and are grouped into semantic namespaces (e.g. `background`, `surface`, `text`, `border`, `brand`).

## Adding or Editing Colors

1. Open `tailwind.config.js` and locate the `extend.colors` block.
2. Add or update semantic tokens (for example `surface.card` or `brand.primary`) with hex values.
3. Use the new utility classes directly in components (e.g. `bg-surface-secondary`, `text-brand-highlight`). Tailwind will generate the corresponding CSS.
4. Restart or refresh your dev server (`npm run dev`) so Tailwind picks up the changes.

Keeping colors centralized ensures consistent branding and simplifies future palette changes.
