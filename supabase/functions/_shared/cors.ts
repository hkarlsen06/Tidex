// Shared CORS headers for Edge Functions
// Customize the allowed origins based on your needs

export const corsHeaders = {
  'Access-Control-Allow-Origin': '*', // Change to your specific domain in production
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS, PUT, DELETE',
}
