# Motion for React

Guide for animating with the Motion for React animation library.

## When to use this skill

- User wants to add animations to React components
- Need to implement transitions, gestures, or spring animations
- Working with `.tsx` or `.jsx` files that need animation
- Integrating Motion with Radix UI components
- Optimizing animation performance

## Important Context

Framer Motion is now called **Motion for React**. All knowledge from Framer Motion applies to Motion for React.

## Importing

- **Never** import from `framer-motion`
- Whenever you want to import from `framer-motion`, import from `motion/react`
- For **client components** (files with `"use client"`): `import { motion } from "motion/react"`
- For **server components**: `import * as motion from "motion/react-client"`
- For the `animate` function in React files: `import { animate } from "motion/react"`
- For the `animate` function in non-React files: `import { animate } from "motion"`

## Performance Best Practices

### Animation Frame Functions

Inside functions that run every animation frame (`useTransform`, `onUpdate`, etc.):

- Avoid object allocation, prefer mutation where safe
- Prefer `for` loops over `forEach` or `map`
- Avoid `Object.entries`, `Object.values` etc as these create new objects

Outside of these functions, use normal coding style.

### Hardware Acceleration

When animating transforms (`transform`, `x`, `y`, `scale`, etc.), add `willChange: "transform"` to the style.

**Only add these values to `willChange`:**
- `transform`
- `opacity`
- `clipPath`
- `filter`

```tsx
// Good: Hardware accelerated
<motion.div
  animate={{ x: 100 }}
  style={{ willChange: "transform" }}
/>
```

### Independent Transforms

Use independent transforms (`x`, `y`, `scaleX`, `scaleY`) when:
- You have competing/composable transforms
- Defining transforms via `style` prop
- Mixing with layout animations

```tsx
// Good: Independent transforms for composability
<motion.div animate={{ x: 100 }} whileHover={{ scale: 1.1 }} />

// Good: Independent transforms in style
<motion.div animate={{ x: 100 }} style={{ scale: 2 }} />
```

## Motion Values

**Never use deprecated syntax:**
```tsx
// Bad: Deprecated
value.onChange(update)

// Good: Current syntax
value.on("change", update)
```

**Never read MotionValue in render:**
```tsx
// Bad: Reading in render
<div style={{ opacity: value.get() }} />

// Good: Reading in useTransform callback
const opacity = useTransform(() => value.get() * 2)
```

## useTransform

Prefer the range mapping syntax when possible:

```tsx
// Preferred: Range mapping
const opacity = useTransform(scrollY, [0, 100], [1, 0])

// Also valid: Function syntax
const scale = useTransform(() => otherValue.get() * 2)

// Deprecated: Never use this syntax
const bad = useTransform(value, (latestValue) => newValue)
```

## Principles

1. **Compose values** - Chain `useTransform`, `useSpring`, `useMotionValue`, `useVelocity` rather than using complicated `if` logic
2. **Use `willChange`** - Prefer over `transform: translateZ(0)`
3. **Animate source values** - Use `animate()` to animate the source MotionValue directly
4. **Derived values follow automatically** - Values from `useTransform`, `useSpring`, etc. follow the source

## Radix UI Integration

When integrating with Radix components:

### Adding Animations

Provide the Radix component `asChild` and add a `motion` component as the first child:

```tsx
<Dialog.Overlay asChild>
  <motion.div
    initial={{ opacity: 0 }}
    animate={{ opacity: 1 }}
    exit={{ opacity: 0 }}
  />
</Dialog.Overlay>
```

### Exit/Layout Animations

Hoist Radix state into `useState` using `open`/`onOpenChange` or `value`/`onValueChange`:

```tsx
const [open, setOpen] = useState(false)

<AnimatePresence>
  {open && (
    <Dialog.Root open={open} onOpenChange={setOpen}>
      <Dialog.Content forceMount asChild>
        <motion.div
          initial={{ opacity: 0, scale: 0.95 }}
          animate={{ opacity: 1, scale: 1 }}
          exit={{ opacity: 0, scale: 0.95 }}
        />
      </Dialog.Content>
    </Dialog.Root>
  )}
</AnimatePresence>
```

**Important:**
- Conditionally render the Radix component that accepts `forceMount`
- Always set `forceMount` on Radix components (never on DOM components)

## Example: Animated Button

```tsx
"use client"

import { motion } from "motion/react"

export function AnimatedButton({ children }: { children: React.ReactNode }) {
  return (
    <motion.button
      whileHover={{ scale: 1.05 }}
      whileTap={{ scale: 0.95 }}
      style={{ willChange: "transform" }}
    >
      {children}
    </motion.button>
  )
}
```

## Example: Scroll-Linked Animation

```tsx
"use client"

import { motion, useScroll, useTransform } from "motion/react"

export function ParallaxSection() {
  const { scrollYProgress } = useScroll()
  const y = useTransform(scrollYProgress, [0, 1], [0, -100])
  const opacity = useTransform(scrollYProgress, [0, 0.5, 1], [1, 0.5, 0])

  return (
    <motion.div
      style={{ y, opacity, willChange: "transform, opacity" }}
    >
      Content
    </motion.div>
  )
}
```
