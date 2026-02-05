'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'
import { getTenantFromSession, setTenantContext, isPlatformAdmin } from '@/lib/tenant'

// ============================================
// ORGANIZATION MANAGEMENT
// ============================================

export async function getAllOrganizations() {
    const supabase = createClient()

    // TODO: Verify platform admin access

    const { data, error } = await supabase
        .from('organizations')
        .select('*')
        .is('deleted_at', null)
        .order('created_at', { ascending: false })

    if (error) throw error

    return data || []
}

export async function createOrganization(formData: {
    name: string
    slug: string
    plan?: 'starter' | 'professional' | 'enterprise'
    guard_limit?: number
}) {
    const supabase = createClient()

    // TODO: Verify platform admin access

    const { data, error } = await supabase
        .from('organizations')
        .insert({
            name: formData.name,
            slug: formData.slug.toLowerCase().replace(/\s+/g, '-'),
            plan: formData.plan || 'starter',
            guard_limit: formData.guard_limit || 50,
            subscription_status: 'trial',
            trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
        })
        .select()
        .single()

    if (error) throw error

    revalidatePath('/platform')

    return data
}

export async function updateOrganization(orgId: string, updates: {
    name?: string
    plan?: 'starter' | 'professional' | 'enterprise'
    guard_limit?: number
    subscription_status?: 'trial' | 'active' | 'suspended' | 'cancelled'
}) {
    const supabase = createClient()

    // TODO: Verify platform admin access

    const { data, error } = await supabase
        .from('organizations')
        .update(updates)
        .eq('id', orgId)
        .select()
        .single()

    if (error) throw error

    revalidatePath('/platform')

    return data
}

export async function suspendOrganization(orgId: string) {
    return updateOrganization(orgId, { subscription_status: 'suspended' })
}

export async function reactivateOrganization(orgId: string) {
    return updateOrganization(orgId, { subscription_status: 'active' })
}

export async function setGuardLimit(orgId: string, limit: number) {
    return updateOrganization(orgId, { guard_limit: limit })
}

// ============================================
// PLATFORM METRICS
// ============================================

export async function getPlatformMetrics() {
    const supabase = createClient()

    // Total organizations
    const { count: totalOrgs } = await supabase
        .from('organizations')
        .select('*', { count: 'exact', head: true })
        .is('deleted_at', null)

    // Active orgs
    const { count: activeOrgs } = await supabase
        .from('organizations')
        .select('*', { count: 'exact', head: true })
        .eq('subscription_status', 'active')
        .is('deleted_at', null)

    // Suspended orgs
    const { count: suspendedOrgs } = await supabase
        .from('organizations')
        .select('*', { count: 'exact', head: true })
        .eq('subscription_status', 'suspended')
        .is('deleted_at', null)

    // Trial orgs  
    const { count: trialOrgs } = await supabase
        .from('organizations')
        .select('*', { count: 'exact', head: true })
        .eq('subscription_status', 'trial')
        .is('deleted_at', null)

    // Total guards across platform
    const { count: totalGuards } = await supabase
        .from('guards')
        .select('*', { count: 'exact', head: true })
        .eq('employment_status', 'active')
        .is('deleted_at', null)

    return {
        totalOrganizations: totalOrgs || 0,
        activeOrganizations: activeOrgs || 0,
        suspendedOrganizations: suspendedOrgs || 0,
        trialOrganizations: trialOrgs || 0,
        totalGuards: totalGuards || 0
    }
}

export async function getOrganizationDetails(orgId: string) {
    const supabase = createClient()

    const { data: org, error: orgError } = await supabase
        .from('organizations')
        .select('*')
        .eq('id', orgId)
        .single()

    if (orgError) throw orgError

    // Get guard count
    const { count: guardCount } = await supabase
        .from('guards')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .eq('employment_status', 'active')
        .is('deleted_at', null)

    // Get unit count
    const { count: unitCount } = await supabase
        .from('units')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .is('deleted_at', null)

    return {
        ...org,
        activeGuards: guardCount || 0,
        units: unitCount || 0
    }
}
