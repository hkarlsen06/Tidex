# Component Scaffolder Skill

Generate components, routes, and features following the project's architecture patterns.

## What This Skill Does

This skill helps you quickly scaffold new code following the established patterns in this Next.js 15 shift tracking application:

1. **UI Components**: Generate shadcn/ui components with proper app wrappers
2. **Settings Pages**: Create new settings pages with correct layout structure
3. **Authenticated Routes**: Scaffold protected routes with data loaders
4. **Features**: Generate complete features with components, routes, and data layers

## Architecture Knowledge

This skill understands:
- Two-tier component system (`components/ui` → `components/app`)
- Semantic color token system (never hardcoded colors)
- Server-side Supabase client patterns
- Data loader pattern for server components
- Route group layouts (`(app)` and `(auth)`)
- Import aliases (`@/`, `@components/`, `@ui/`, `@appui/`)

## Usage Examples

### Generate a New UI Component

"Scaffold a Card component"
- Generates `components/ui/card.tsx` (shadcn base)
- Generates `components/app/Card.tsx` (app wrapper with semantic colors)
- Uses proper theming tokens

### Create a Settings Page

"Scaffold a notifications settings page"
- Generates `app/(app)/settings/notifications/page.tsx`
- Includes data loader pattern
- Uses proper layout inheritance
- Follows semantic color system

### Create an Authenticated Route

"Scaffold a reports route with data loader"
- Generates `app/(app)/reports/page.tsx`
- Generates `app/(app)/reports/_data/getReports.ts`
- Includes auth check pattern
- Proper Supabase server client usage

### Generate a Complete Feature

"Scaffold a shift templates feature"
- Component files
- Route files
- Data loader
- TypeScript types
- Follows all architecture patterns

## Commands You Can Use

After invoking this skill, you can say:

- "Generate a [component name] component"
- "Scaffold a [page name] settings page"
- "Create a [route name] route with data loader"
- "Build a [feature name] feature"
- "Add a [component] with [specific requirements]"

## What Gets Generated

All generated code will:
- ✅ Use semantic color tokens (bg-surface-primary, text-text-primary, etc.)
- ✅ Follow the two-tier component architecture
- ✅ Use proper import aliases
- ✅ Include TypeScript types
- ✅ Follow server-side data loading patterns
- ✅ Include proper auth checks for protected routes
- ✅ Support light/dark mode via CSS variables
- ✅ Use createSupabaseServerClient() in server components
- ✅ Use shared supabase client in client components
- ❌ Never import from components/ui directly
- ❌ Never use hardcoded Tailwind colors (slate-*, gray-*, etc.)
- ❌ Never instantiate Supabase clients directly

## Interactive Mode

This skill will:
1. Ask clarifying questions about your requirements
2. Show you what will be generated
3. Confirm before creating files
4. Create all necessary files
5. Update related files if needed (e.g., add exports to index files)

## Examples

**Simple Component:**
```
You: "Generate a Badge component"
Skill: "I'll create a Badge component with semantic colors. What variants do you need? (default, success, warning, error)"
You: "All of them"
Skill: *generates components/ui/badge.tsx and components/app/Badge.tsx*
```

**Settings Page:**
```
You: "Scaffold a notifications settings page"
Skill: "I'll create app/(app)/settings/notifications/page.tsx with a data loader. What settings should it manage? (email notifications, push notifications, etc.)"
You: "Email and push notifications with toggles"
Skill: *generates page with proper structure*
```

**Feature:**
```
You: "Build a shift templates feature"
Skill: "I'll scaffold a complete shift templates feature. Should this be:
- A new route under /templates?
- A modal/dialog accessible from the shifts page?
- Part of the settings?"
You: "New route under /templates"
Skill: *generates route, components, data loaders, types*
```

---

## Ready to Scaffold!

Tell me what you want to generate and I'll create it following all your project's patterns and best practices.
