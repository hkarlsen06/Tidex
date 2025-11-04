# Add shadcn/ui Component

Guide for adding new shadcn/ui components to the tidex project with proper wrapping.

## When to use this skill

- User requests a new UI component (button, dialog, dropdown, etc.)
- Need to add a shadcn/ui component to the project
- Want to integrate a new shadcn component following project conventions

## Important Context

This project uses a **two-tier component architecture**:
- `components/ui/*` - Raw shadcn/ui components (generated, NEVER import directly)
- `components/app/*` - Wrapped components with app-specific logic and styling

**Critical rule**: Always import from `components/app`, never from `components/ui`

## Steps

### 1. Add the shadcn component

Run the shadcn CLI to generate the base component:

```bash
npm dlx shadcn@latest add <component-name>
```

**Examples:**
```bash
npm dlx shadcn@latest add button
npm dlx shadcn@latest add dialog
npm dlx shadcn@latest add dropdown-menu
npm dlx shadcn@latest add select
```

This creates the raw component in `components/ui/<component-name>.tsx`

### 2. Review the generated component

Check the generated file in `components/ui/` to understand:
- Component props and variants
- Available customization options
- Default styling and behavior

**Do NOT modify files in `components/ui/`** - they are generated and may be regenerated

### 3. Create wrapper in components/app

Create a new file in `components/app/` following the naming pattern:

```bash
# File: components/app/ComponentName.tsx
```

**Example wrapper structure:**

```tsx
// components/app/Button.tsx
import { Button as ShadcnButton } from "@ui/button";
import { type ComponentPropsWithoutRef } from "react";

// Add any app-specific props or customizations
type ButtonProps = ComponentPropsWithoutRef<typeof ShadcnButton> & {
  // Add custom props here if needed
};

export function Button({ className, ...props }: ButtonProps) {
  return (
    <ShadcnButton
      className={className}
      {...props}
    />
  );
}
```

### 4. Follow existing patterns

Look at other wrapped components in `components/app/` for guidance:
- Check how they handle theming (semantic tokens vs hardcoded colors)
- See how they extend the base component
- Follow consistent naming and export patterns

### 5. Use semantic color tokens

Ensure the wrapper uses semantic color tokens from `app/globals.css`:

**Good (semantic tokens):**
```tsx
className="bg-surface-primary text-text-primary border-border"
```

**Bad (hardcoded colors):**
```tsx
className="bg-slate-900 text-gray-400 border-gray-600"
```

### 6. Update imports across codebase

If replacing an old component, update all imports:

**Before:**
```tsx
import { Button } from "@ui/button";
```

**After:**
```tsx
import { Button } from "@appui/Button";
```

## Verification

1. Component is generated in `components/ui/`
2. Wrapper exists in `components/app/`
3. Wrapper uses semantic color tokens (no hardcoded colors)
4. All imports use `@appui/*` alias, not `@ui/*`
5. Component works in both light and dark modes

## Import Aliases Reference

- `@ui/*` → `components/ui/` (DO NOT USE directly)
- `@appui/*` → `components/app/` (USE THIS)
- `@components/*` → `components/`

## Example: Adding a Dialog Component

```bash
# Step 1: Generate base component
npm dlx shadcn@latest add dialog

# Step 2: Create wrapper
# File: components/app/Dialog.tsx
```

```tsx
import {
  Dialog as ShadcnDialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@ui/dialog";

export const Dialog = ShadcnDialog;
export { DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger };
```

```tsx
// Step 3: Use in your code
import { Dialog, DialogContent, DialogTitle } from "@appui/Dialog";

function MyComponent() {
  return (
    <Dialog>
      <DialogContent>
        <DialogTitle>My Dialog</DialogTitle>
      </DialogContent>
    </Dialog>
  );
}
```
