import 'server-only'
import { cache } from 'react'
import { createSupabaseServerClient } from '@/lib/supabase/server'
import { redirect } from 'next/navigation'

/**
 * Verify user session and redirect to login if not authenticated
 * Use this in Server Components and Server Actions
 */
export const verifySession = cache(async () => {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    redirect('/login')
  }

  return { user }
})

/**
 * Get user session without redirecting
 * Returns null if not authenticated
 * Use this in API routes where redirect() is not supported
 */
export const getSession = cache(async () => {
  const supabase = await createSupabaseServerClient()
  const { data: { user } } = await supabase.auth.getUser()

  if (!user) {
    return null
  }

  return { user }
})
