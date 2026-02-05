'use server'

import { createClient } from '@/lib/supabase'
import { cookies } from 'next/headers'

/**
 * Tenant Service
 * 
 * Handles organization context resolution and enforcement.
 * RLS is NOT enabled yet, but this service prepares for it.
 */

// ============================================
// TENANT RESOLUTION
// ============================================

/**
 * Get organization ID from authenticated user session
 * 
 * For now, returns default org. Later will resolve from user's org membership.
 */
export async function getTenantFromSession(): Promise<string> {
    const supabase = createClient()

    try {
        // Get authenticated user
        const { data: { user }, error: authError } = await supabase.auth.getUser()

        if (authError || !user) {
            throw new Error('Not authenticated')
        }

        // TODO: Later, query organization_users to get user's organization
        // For now, return default organization
        // const { data: orgUser } = await supabase
        //   .from('organization_users')
        //   .select('organization_id')
        //   .eq('user_id', user.id)
        //   .single()

        // return orgUser?.organization_id || DEFAULT_ORG_ID

        return '00000000-0000-0000-0000-000000000000' // Default org
    } catch (error) {
        console.error('Tenant resolution error:', error)
        return '00000000-0000-0000-0000-000000000000' // Fallback to default
    }
}

/**
 * Check if user is platform super admin
 */
export async function isPlatformAdmin(userId: string): Promise<boolean> {
    const supabase = createClient()

    const { data } = await supabase
        .from('platform_admins')
        .select('id')
        .eq('user_id', userId)
        .maybeSingle()

    return !!data
}

/**
 * Check if user has access to organization
 */
export async function verifyUserOrgAccess(userId: string, orgId: string): Promise<boolean> {
    const supabase = createClient()

    const { data } = await supabase
        .from('organization_users')
        .select('id')
        .eq('user_id', userId)
        .eq('organization_id', orgId)
        .maybeSingle()

    return !!data
}

// ============================================
// TENANT CONTEXT (for future RLS)
// ============================================

/**
 * Set tenant context in database session
 * 
 * This will be used by RLS policies when enabled.
 */
export async function setTenantContext(supabase: any, orgId: string): Promise<void> {
    try {
        await supabase.rpc('set_current_org_id', { org_id: orgId })
    } catch (error) {
        console.error('Failed to set tenant context:', error)
        // Don't throw - RLS not enabled yet
    }
}

/**
 * Wrapper for server actions to enforce tenant context
 * 
 * Usage:
 * const result = await withTenant(async (orgId) => {
 *   // Your logic here
 * })
 */
export async function withTenant<T>(
    operation: (orgId: string) => Promise<T>
): Promise<T> {
    const orgId = await getTenantFromSession()
    const supabase = createClient()

    // Set context for future RLS
    await setTenantContext(supabase, orgId)

    // Execute operation with org ID
    return operation(orgId)
}

// ============================================
// ORGANIZATION QUERIES
// ============================================

export async function getOrganization(orgId: string) {
    const supabase = createClient()

    const { data, error } = await supabase
        .from('organizations')
        .select('*')
        .eq('id', orgId)
        .is('deleted_at', null)
        .single()

    if (error) throw error
    return data
}

export async function getOrganizationBySlug(slug: string) {
    const supabase = createClient()

    const { data, error } = await supabase
        .from('organizations')
        .select('*')
        .eq('slug', slug)
        .is('deleted_at', null)
        .single()

    if (error) throw error
    return data
}

/**
 * Check if organization is active and can be accessed
 */
export async function checkSubscriptionStatus(orgId: string): Promise<{
    allowed: boolean
    reason?: string
}> {
    try {
        const org = await getOrganization(orgId)

        if (org.subscription_status === 'suspended') {
            return { allowed: false, reason: 'Organization is suspended' }
        }

        if (org.subscription_status === 'cancelled') {
            return { allowed: false, reason: 'Subscription cancelled' }
        }

        if (org.subscription_status === 'trial' && org.trial_ends_at) {
            const trialEnd = new Date(org.trial_ends_at)
            if (trialEnd < new Date()) {
                return { allowed: false, reason: 'Trial expired' }
            }
        }

        return { allowed: true }
    } catch (error) {
        return { allowed: false, reason: 'Organization not found' }
    }
}

/**
 * Check if organization can create more guards
 */
export async function checkGuardLimit(orgId: string): Promise<{
    allowed: boolean
    current: number
    limit: number
    message?: string
}> {
    const supabase = createClient()

    try {
        const org = await getOrganization(orgId)

        const { data: countData } = await supabase
            .rpc('get_active_guard_count', { org_id: orgId })

        const current = countData || 0
        const limit = org.guard_limit

        if (current >= limit) {
            return {
                allowed: false,
                current,
                limit,
                message: `Guard limit reached (${current}/${limit}). Please upgrade your plan.`
            }
        }

        return { allowed: true, current, limit }
    } catch (error) {
        console.error('Guard limit check error:', error)
        return { allowed: true, current: 0, limit: 0 } // Fail open for now
    }
}
