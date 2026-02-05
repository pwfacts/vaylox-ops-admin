'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'
import { getTenantFromSession, checkGuardLimit, setTenantContext } from '@/lib/tenant'

// ============================================
// GUARDS
// ============================================

export async function getGuards(params?: {
    search?: string
    unitId?: string
    status?: string
    page?: number
    limit?: number
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const page = params?.page || 1
    const limit = params?.limit || 50
    const offset = (page - 1) * limit

    let query = supabase
        .from('guards')
        .select('*, unit:units!primary_unit_id(unit_name)', { count: 'exact' })
        .eq('organization_id', orgId)
        .is('deleted_at', null)
        .order('created_at', { ascending: false })

    // Search
    if (params?.search) {
        query = query.or(`full_name.ilike.%${params.search}%,phone_number.ilike.%${params.search}%,guard_code.ilike.%${params.search}%`)
    }

    // Filter by unit
    if (params?.unitId) {
        query = query.eq('primary_unit_id', params.unitId)
    }

    // Filter by status
    if (params?.status) {
        query = query.eq('employment_status', params.status)
    }

    const { data, error, count } = await query.range(offset, offset + limit - 1)

    if (error) throw error

    return {
        guards: data,
        total: count || 0,
        page,
        totalPages: Math.ceil((count || 0) / limit)
    }
}

export async function createGuard(formData: {
    full_name: string
    phone_number: string
    guard_code: string
    primary_unit_id?: string
    employment_status?: 'active' | 'inactive' | 'suspended'
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    // 🔥 GUARD LIMIT ENFORCEMENT
    const limitCheck = await checkGuardLimit(orgId)
    if (!limitCheck.allowed) {
        throw new Error(limitCheck.message || 'Guard limit reached')
    }

    const { data, error } = await supabase
        .from('guards')
        .insert({
            organization_id: orgId,
            full_name: formData.full_name,
            phone_number: formData.phone_number,
            guard_code: formData.guard_code,
            primary_unit_id: formData.primary_unit_id || null,
            employment_status: formData.employment_status || 'active'
        })
        .select()
        .single()

    if (error) throw error

    revalidatePath('/workforce')
    revalidatePath('/')

    return data
}


export async function updateGuard(id: string, formData: {
    full_name?: string
    phone_number?: string
    guard_code?: string
    primary_unit_id?: string
    employment_status?: 'active' | 'inactive' | 'suspended'
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('guards')
        .update(formData)
        .eq('id', id)
        .eq('organization_id', orgId)
        .is('deleted_at', null)
        .select()
        .single()

    if (error) throw error

    revalidatePath('/workforce')
    revalidatePath('/')

    return data
}

export async function deleteGuard(id: string) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    // Soft delete
    const { data, error } = await supabase
        .from('guards')
        .update({
            deleted_at: new Date().toISOString(),
            employment_status: 'inactive'
        })
        .eq('id', id)
        .eq('organization_id', orgId)
        .select()
        .single()

    if (error) throw error

    revalidatePath('/workforce')
    revalidatePath('/')

    return data
}

// ============================================
// UNITS
// ============================================

export async function getUnits() {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('units')
        .select('*')
        .eq('organization_id', orgId)
        .is('deleted_at', null)
        .order('unit_name')

    if (error) throw error

    return data
}

export async function createUnit(formData: {
    unit_name: string
    address?: string
    required_guard_count?: number
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('units')
        .insert({
            organization_id: orgId,
            unit_name: formData.unit_name,
            address: formData.address || null,
            required_guard_count: formData.required_guard_count || 1
        })
        .select()
        .single()

    if (error) throw error

    revalidatePath('/workforce')
    revalidatePath('/units')

    return data
}

export async function deleteUnit(id: string) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    // Soft delete
    const { data, error } = await supabase
        .from('units')
        .update({
            deleted_at: new Date().toISOString()
        })
        .eq('id', id)
        .eq('organization_id', orgId)
        .select()
        .single()

    if (error) throw error

    revalidatePath('/workforce')
    revalidatePath('/units')

    return data
}

// ============================================
// DASHBOARD METRICS
// ============================================

export async function getDashboardMetrics() {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    // Active guards count
    const { count: activeGuards } = await supabase
        .from('guards')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .eq('employment_status', 'active')
        .is('deleted_at', null)

    // Units with guard counts
    const { data: units } = await supabase
        .from('units')
        .select('id, required_guard_count')
        .eq('organization_id', orgId)
        .is('deleted_at', null)

    let understaffedCount = 0
    if (units) {
        for (const unit of units) {
            const { count } = await supabase
                .from('guards')
                .select('*', { count: 'exact', head: true })
                .eq('primary_unit_id', unit.id)
                .eq('employment_status', 'active')
                .is('deleted_at', null)

            if ((count || 0) < unit.required_guard_count) {
                understaffedCount++
            }
        }
    }

    return {
        activeGuards: activeGuards || 0,
        understaffedSites: understaffedCount
    }
}
