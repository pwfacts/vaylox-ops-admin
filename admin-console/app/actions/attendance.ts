'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'
import { getTenantFromSession, setTenantContext } from '@/lib/tenant'

// ============================================
// CHECK-IN FLOW
// ============================================

export async function guardCheckIn(params: {
    guard_id: string
    working_unit_id: string
    created_by?: string
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // 1️⃣ Validate guard exists and is active
        const { data: guard, error: guardError } = await supabase
            .from('guards')
            .select('id, full_name, primary_unit_id, employment_status')
            .eq('id', params.guard_id)
            .eq('organization_id', orgId)
            .is('deleted_at', null)
            .single()

        if (guardError || !guard) {
            throw new Error('Guard not found')
        }

        if (guard.employment_status !== 'active') {
            throw new Error(`Guard is ${guard.employment_status}. Cannot check in.`)
        }

        // 2️⃣ Guard must have primary unit assigned
        if (!guard.primary_unit_id) {
            throw new Error('Guard has no primary unit assigned')
        }

        // 3️⃣ Check for overlapping active shift (duplicate prevention)
        const { data: activeShift } = await supabase
            .from('work_events')
            .select('id')
            .eq('guard_id', params.guard_id)
            .eq('event_status', 'CHECKED_IN')
            .is('deleted_at', null)
            .maybeSingle()

        if (activeShift) {
            throw new Error('Guard already has an active shift. Must check out first.')
        }

        // 4️⃣ Auto duty classification
        const isPrimaryUnit = params.working_unit_id === guard.primary_unit_id
        const dutyType = isPrimaryUnit ? 'PRIMARY' : 'UNSCHEDULED'

        // 5️⃣ Anomaly detection
        let anomalyFlag = false
        let anomalyReason: string | null = null

        if (!isPrimaryUnit) {
            anomalyFlag = true
            anomalyReason = 'Guard checking into non-primary unit'
        }

        // 6️⃣ Auto approval rules
        const approvalStatus = (isPrimaryUnit && !anomalyFlag) ? 'AUTO_APPROVED' : 'PENDING'

        // 7️⃣ Create work event
        const now = new Date().toISOString()
        const shiftDate = new Date().toISOString().split('T')[0]

        const { data: workEvent, error: insertError } = await supabase
            .from('work_events')
            .insert({
                organization_id: orgId,
                guard_id: params.guard_id,
                primary_unit_id: guard.primary_unit_id,
                working_unit_id: params.working_unit_id,
                check_in_time: now,
                shift_date: shiftDate,
                duty_type: dutyType,
                event_status: 'CHECKED_IN',
                approval_status: approvalStatus,
                anomaly_flag: anomalyFlag,
                anomaly_reason: anomalyReason,
                created_by: params.created_by || null
            })
            .select()
            .single()

        if (insertError) {
            throw insertError
        }

        revalidatePath('/attendance')
        revalidatePath('/')

        return {
            success: true,
            event: workEvent,
            message: approvalStatus === 'AUTO_APPROVED'
                ? 'Check-in successful'
                : 'Check-in pending approval (non-primary unit)'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Check-in failed'
        }
    }
}

// ============================================
// CHECK-OUT FLOW
// ============================================

export async function guardCheckOut(params: {
    guard_id: string
    approved_by?: string
}) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // Find active shift
        const { data: activeShift, error: findError } = await supabase
            .from('work_events')
            .select('*')
            .eq('guard_id', params.guard_id)
            .eq('event_status', 'CHECKED_IN')
            .eq('organization_id', orgId)
            .is('deleted_at', null)
            .maybeSingle()

        if (findError || !activeShift) {
            throw new Error('No active shift found for this guard')
        }

        if (activeShift.locked_at) {
            throw new Error('Cannot check out locked event')
        }

        // Update event
        const now = new Date().toISOString()
        const { data: updatedEvent, error: updateError } = await supabase
            .from('work_events')
            .update({
                check_out_time: now,
                event_status: 'CHECKED_OUT'
            })
            .eq('id', activeShift.id)
            .select()
            .single()

        if (updateError) {
            throw updateError
        }

        revalidatePath('/attendance')
        revalidatePath('/')

        return {
            success: true,
            event: updatedEvent,
            message: 'Check-out successful'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Check-out failed'
        }
    }
}

// ============================================
// APPROVAL ACTIONS
// ============================================

export async function approveWorkEvent(eventId: string, approvedBy: string) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        const now = new Date().toISOString()

        const { data, error } = await supabase
            .from('work_events')
            .update({
                approval_status: 'APPROVED',
                approved_by: approvedBy,
                approved_at: now,
                locked_at: now // Lock on approval
            })
            .eq('id', eventId)
            .eq('organization_id', orgId)
            .eq('approval_status', 'PENDING')
            .is('locked_at', null)
            .select()
            .single()

        if (error) throw error

        revalidatePath('/attendance')

        return { success: true, event: data }
    } catch (error: any) {
        return { success: false, error: error.message }
    }
}

export async function rejectWorkEvent(eventId: string, approvedBy: string) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        const { data, error } = await supabase
            .from('work_events')
            .update({
                approval_status: 'REJECTED',
                approved_by: approvedBy,
                approved_at: new Date().toISOString()
            })
            .eq('id', eventId)
            .eq('organization_id', orgId)
            .eq('approval_status', 'PENDING')
            .is('locked_at', null)
            .select()
            .single()

        if (error) throw error

        revalidatePath('/attendance')

        return { success: true, event: data }
    } catch (error: any) {
        return { success: false, error: error.message }
    }
}

// ============================================
// QUERY ACTIONS
// ============================================

export async function getActiveShifts() {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('work_events')
        .select(`
      *,
      guard:guards!guard_id(id, full_name, guard_code),
      working_unit:units!working_unit_id(id, unit_name)
    `)
        .eq('organization_id', orgId)
        .eq('event_status', 'CHECKED_IN')
        .is('deleted_at', null)
        .order('check_in_time', { ascending: false })

    if (error) throw error

    return data || []
}

export async function getPendingApprovals() {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('work_events')
        .select(`
      *,
      guard:guards!guard_id(id, full_name, guard_code),
      working_unit:units!working_unit_id(id, unit_name),
      primary_unit:units!primary_unit_id(id, unit_name)
    `)
        .eq('organization_id', orgId)
        .eq('approval_status', 'PENDING')
        .is('deleted_at', null)
        .order('created_at', { ascending: false })

    if (error) throw error

    return data || []
}

export async function getGuardAttendanceHistory(guardId: string, limit = 30) {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const { data, error } = await supabase
        .from('work_events')
        .select(`
      *,
      working_unit:units!working_unit_id(id, unit_name)
    `)
        .eq('guard_id', guardId)
        .eq('organization_id', orgId)
        .is('deleted_at', null)
        .order('shift_date', { ascending: false })
        .limit(limit)

    if (error) throw error

    return data || []
}

export async function getTodayAttendanceMetrics() {
    const supabase = createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const today = new Date().toISOString().split('T')[0]

    // Active now (checked in)
    const { count: activeCount } = await supabase
        .from('work_events')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .eq('event_status', 'CHECKED_IN')
        .is('deleted_at', null)

    // Pending approvals
    const { count: pendingCount } = await supabase
        .from('work_events')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .eq('approval_status', 'PENDING')
        .is('deleted_at', null)

    // Anomalies today
    const { count: anomalyCount } = await supabase
        .from('work_events')
        .select('*', { count: 'exact', head: true })
        .eq('organization_id', orgId)
        .eq('shift_date', today)
        .eq('anomaly_flag', true)
        .is('deleted_at', null)

    return {
        onDuty: activeCount || 0,
        pendingApprovals: pendingCount || 0,
        anomalies: anomalyCount || 0
    }
}
