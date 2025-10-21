# Supabase Edge Functions

This directory contains Supabase Edge Functions for the application.

## Directory Structure

```
supabase/functions/
├── _shared/           # Shared utilities and helpers
│   └── cors.ts        # CORS headers configuration
├── example-function/  # Template function (rename for your use case)
│   └── index.ts       # Function entry point
└── README.md          # This file
```

## Creating a New Function

1. **Copy the template:**
   ```bash
   cp -r supabase/functions/example-function supabase/functions/your-function-name
   ```

2. **Edit the function:**
   - Open `supabase/functions/your-function-name/index.ts`
   - Update the request/response types
   - Implement your business logic

3. **Test locally:**
   ```bash
   # Start Supabase locally (if not already running)
   npx supabase start

   # Serve your function
   npx supabase functions serve your-function-name --env-file .env.local

   # In another terminal, test it
   curl -i --location --request POST 'http://localhost:54321/functions/v1/your-function-name' \
     --header 'Authorization: Bearer YOUR_ANON_KEY' \
     --header 'Content-Type: application/json' \
     --data '{"key":"value"}'
   ```

4. **Deploy to production:**
   ```bash
   npx supabase functions deploy your-function-name
   ```

## Calling Functions from Your App

### From the client:

```typescript
import { supabase } from '@/lib/supabase/browser'

const { data, error } = await supabase.functions.invoke('your-function-name', {
  body: { key: 'value' }
})
```

### From the server:

```typescript
import { createSupabaseServerClient } from '@/lib/supabase/server'

const supabase = await createSupabaseServerClient()
const { data, error } = await supabase.functions.invoke('your-function-name', {
  body: { key: 'value' }
})
```

## Environment Variables

Edge Functions have access to these environment variables automatically:
- `SUPABASE_URL` - Your Supabase project URL
- `SUPABASE_ANON_KEY` - Your Supabase anon/public key
- `SUPABASE_SERVICE_ROLE_KEY` - Service role key (use carefully!)

For custom environment variables, set them via:
```bash
npx supabase secrets set MY_SECRET=value
```

## Common Patterns

### Database Operations
```typescript
const { data, error } = await supabaseClient
  .from('table_name')
  .select('*')
  .eq('user_id', user.id)
```

### Authenticated Requests
The template already includes authentication checking. The `user` object is available after verification.

### CORS
CORS headers are defined in `_shared/cors.ts`. Update the allowed origins for production.

## TypeScript Support

Edge Functions use Deno, which has built-in TypeScript support. No build step needed!

## Logging

Use `console.log()` and `console.error()` for logging. View logs with:
```bash
npx supabase functions logs your-function-name
```

## Resources

- [Supabase Edge Functions Docs](https://supabase.com/docs/guides/functions)
- [Deno Deploy Docs](https://deno.com/deploy/docs)
