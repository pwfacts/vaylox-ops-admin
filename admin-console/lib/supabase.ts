import { createServerClient, type CookieOptions } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        async get(name: string) {
          return cookieStore.get(name)?.value
        },
        async set(name: string, value: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value, ...options })
          } catch (error) {
            // Cookie setting can fail in Server Components
          }
        },
        async remove(name: string, options: CookieOptions) {
          try {
            cookieStore.set({ name, value: '', ...options })
          } catch (error) {
            // Cookie removal can fail in Server Components
          }
        },
      },
    }
  )
}

/**
 * Get current authenticated user or null
 */
export async function getCurrentUser() {
  const supabase = await createClient()

  const { data: { user }, error } = await supabase.auth.getUser()

  if (error || !user) {
    return null
  }

  return user
}

/**
 * Check if current user is platform super admin
 */
export async function isPlatformAdmin(): Promise<boolean> {
  const user = await getCurrentUser()

  if (!user) return false

  const supabase = await createClient()

  const { data } = await supabase
    .from('platform_admins')
    .select('id')
    .eq('user_id', user.id)
    .maybeSingle()

  return !!data
}

/**
 * Get user's organization membership
 */
export async function getUserOrganization() {
  const user = await getCurrentUser()

  if (!user) return null

  const supabase = await createClient()

  const { data } = await supabase
    .from('organization_users')
    .select('organization_id, role, organization:organizations(*)')
    .eq('user_id', user.id)
    .maybeSingle()

  return data
}

/**
 * Require authentication - throws if not logged in
 */
export async function requireAuth() {
  const user = await getCurrentUser()

  if (!user) {
    throw new Error('Authentication required')
  }

  return user
}

/**
 * Require platform admin access - throws if not admin
 */
export async function requirePlatformAdmin() {
  const user = await requireAuth()
  const isAdmin = await isPlatformAdmin()

  if (!isAdmin) {
    throw new Error('Platform admin access required')
  }

  return user
}
