---
# shadcn Components Guide
---

## 1. Structure

- **components/ui** → raw shadcn components
- **components/app** → wrapped app components
- Wrapper names are **Capitalized** (`Button.tsx`, `Input.tsx`, etc.)
- App code imports **only** from `components/app`

```
components/
  ui/button.tsx
  app/Button.tsx
```

---

## 2. Install

List all available shadcn components:

```bash
npm dlx shadcn@latest add
```

Add any shadcn components you need:

```bash
npm dlx shadcn@latest add <component-name> [more-components...]
```

Example:

```bash
npm dlx shadcn@latest add button input dialog
```

Tailwind setup (already done):

```ts
// tailwind.config.ts
content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"];
plugins: [require("tailwindcss-animate")];
```

---

## 3. Wrap Components

**Pattern**

```tsx
// components/app/Button.tsx
import * as React from "react";
import { Button as BaseButton } from "@/components/ui/button";
import { cn } from "@/lib/cn";

type Props = React.ComponentProps<typeof BaseButton> & { loading?: boolean };

export function Button({ className, loading, children, ...props }: Props) {
  return (
    <BaseButton
      {...props}
      disabled={loading || props.disabled}
      className={cn("font-medium", className)}
    >
      {loading ? "…" : children}
    </BaseButton>
  );
}
```

**Simple re-export**

```tsx
// components/app/Dialog.tsx
export * from "@/components/ui/dialog";
```

---

## 4. Usage

```tsx
import { Button } from "@/components/app/Button";
import { Dialog } from "@/components/app/Dialog";
```

Never import from `components/ui` directly.

---

## 5. Add a New Component

```bash
pnpm dlx shadcn@latest add <name>
cp components/ui/<name>.tsx components/app/<Name>.tsx
```

Modify wrapper only if app logic or styles are needed.

---

## 6. Lint Rule (optional)

Prevent direct `ui` imports:

```js
"no-restricted-imports": ["error", { "patterns": ["@/components/ui/*"] }]
```

---

## 7. Update

```bash
pnpm dlx shadcn@latest add <name>  # refresh ui component
```

---

**Summary:**
→ Generate in `components/ui`
→ Wrap in `components/app`
→ Use only wrapped components everywhere.

---
