// Follow this template on deno.land/x to import from the Supabase ecosystem
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from '../_shared/cors.ts'

interface RequestBody {
  // Define your expected request body structure here
  exampleField?: string
}

interface ResponseData {
  // Define your response structure here
  message: string
  data?: any
}

Deno.serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    // Get authorization header
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      throw new Error('Missing authorization header')
    }

    // Create Supabase client with user's auth token
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      {
        global: {
          headers: { Authorization: authHeader },
        },
      }
    )

    // Verify user is authenticated
    const {
      data: { user },
      error: userError,
    } = await supabaseClient.auth.getUser()

    if (userError || !user) {
      throw new Error('Unauthorized')
    }

    // Parse request body
    const body: RequestBody = await req.json()

    // Your function logic goes here
    // Example: Query database
    // const { data, error } = await supabaseClient
    //   .from('your_table')
    //   .select('*')
    //   .eq('user_id', user.id)

    // Example response
    const responseData: ResponseData = {
      message: 'Success',
      data: {
        userId: user.id,
        receivedData: body,
      },
    }

    return new Response(JSON.stringify(responseData), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })
  } catch (error) {
    console.error('Error:', error)

    return new Response(
      JSON.stringify({
        error: error.message || 'An unexpected error occurred',
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: error.message === 'Unauthorized' ? 401 : 500,
      }
    )
  }
})

/* To invoke this function locally:

  1. Start the Supabase local development server:
     npx supabase start

  2. Run this function:
     npx supabase functions serve example-function --env-file .env.local

  3. Make a request:
     curl -i --location --request POST 'http://localhost:54321/functions/v1/example-function' \
       --header 'Authorization: Bearer YOUR_ANON_KEY' \
       --header 'Content-Type: application/json' \
       --data '{"exampleField":"value"}'

  To deploy:
     npx supabase functions deploy example-function

*/
