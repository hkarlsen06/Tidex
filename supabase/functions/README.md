# Supabase Edge Functions

This directory contains Supabase Edge Functions for the application.

## Directory Structure

```
supabase/functions/
├── _shared/           # Shared domain utilities and helpers
├── function-name/     # One directory per deployed function
│   └── index.ts       # Fetch handler entry point
├── deno.json          # Shared import map and runtime configuration
└── README.md          # This file
```

## Creating a New Function

1. **Create the function:**
   ```bash
   supabase functions new your-function-name
   ```

2. **Edit the function:**
   - Open `supabase/functions/your-function-name/index.ts`
   - Declare the caller with `withSupabase`
   - Implement your business logic

   ```typescript
   import { withSupabase } from "@supabase/server";

   export default {
     fetch: withSupabase({ auth: "user" }, async (_request, context) => {
       const { data, error } = await context.supabase.from("profiles").select();
       if (error) {
         return Response.json({ error: error.message }, { status: 500 });
       }
       return Response.json(data);
     }),
   };
   ```

3. **Test locally:**
   ```bash
   # Start Supabase locally (if not already running)
   bunx supabase start

   # Serve your function
   bunx supabase functions serve your-function-name --env-file .env.local

   # In another terminal, test it
   curl -i --location --request POST 'http://localhost:54321/functions/v1/your-function-name' \
     --header 'Authorization: Bearer YOUR_ANON_KEY' \
     --header 'Content-Type: application/json' \
     --data '{"key":"value"}'
   ```

4. **Deploy to production:** Sync the function to
   `/srv/tidex/tidex-sb/volumes/functions/` on `mdr`, then restart the
   `functions` service.

   Keep per-function JWT behavior in `supabase/config.toml`. This repository's
   CLI deploy workflow always includes `--no-verify-jwt`.

## Calling Functions from Your App

### From the client:

```typescript
import { supabase } from "@/lib/supabase/browser";

const { data, error } = await supabase.functions.invoke("your-function-name", {
  body: { key: "value" },
});
```

### From the server:

```typescript
import { createSupabaseServerClient } from "@/lib/supabase/server";

const supabase = await createSupabaseServerClient();
const { data, error } = await supabase.functions.invoke("your-function-name", {
  body: { key: "value" },
});
```

## Environment Variables

Edge Functions have access to these environment variables automatically:

- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_PUBLISHABLE_KEYS` - Named publishable keys
- `SUPABASE_SECRET_KEYS` - Named server-only keys
- `SUPABASE_JWKS` - Keys used to verify user JWTs

`@supabase/server` resolves these variables and creates request-scoped clients.
Do not read Supabase keys directly in new functions.

For custom environment variables, set them via:

```bash
bunx supabase secrets set MY_SECRET=value
```

## Common Patterns

### Database Operations

```typescript
const { data, error } = await context.supabase
  .from("table_name")
  .select("*");
```

### Authenticated Requests

Use `auth: "user"`. `context.supabase` is scoped to the caller and respects RLS;
`context.supabaseAdmin` bypasses RLS and must only be used deliberately.

### CORS

`withSupabase` handles standard Supabase CORS headers and preflight requests.
Use `cors: "disabled"` for webhooks and other server-only endpoints.

## TypeScript Support

Edge Functions use Deno, which has built-in TypeScript support. No build step
needed!

## Logging

Use `console.log()` and `console.error()` for logging. View logs with:

```bash
bunx supabase functions logs your-function-name
```

## Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Deno Deploy Docs](https://deno.com/deploy/docs)
