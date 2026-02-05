'use server'

import { createClient } from '@/lib/supabase'
import { guardCheckIn, guardCheckOut } from './attendance'

const CURRENT_ORG_ID = '00000000-0000-0000-0000-000000000000'

// ============================================
// GUARD AUTH (Lightweight MVP)
// ============================================

export async function guardLogin(guardCode: string, otp: string) {
    const supabase = createClient()

    try {
        // Validate guard exists and is active
        const { data: guard, error } = await supabase
            .from('guards')
            .select('id, full_name, guard_code, primary_unit_id, employment_status, unit:units!primary_unit_id(unit_name)')
            .eq('guard_code', guardCode.toUpperCase())
            .eq('organization_id', CURRENT_ORG_ID)
            .is('deleted_at', null)
            .single()

        if (error || !guard) {
            return { success: false, error: 'Invalid guard code' }
        }

        if (guard.employment_status !== 'active') {
            return { success: false, error: `Account is ${guard.employment_status}` }
        }

        // TODO: In production, validate OTP against sent code
        // For MVP, accept any 4-digit OTP
        if (otp.length !== 4) {
            return { success: false, error: 'Invalid OTP' }
        }

        return {
            success: true,
            guard: {
                id: guard.id,
                full_name: guard.full_name,
                guard_code: guard.guard_code,
                primary_unit_id: guard.primary_unit_id,
                primary_unit_name: (guard as any).unit?.unit_name || 'Unassigned'
            }
        }
    } catch (error: any) {
        return { success: false, error: error.message || 'Login failed' }
    }
}

// ============================================
// GUARD STATUS CHECK
// ============================================

export async function getGuardStatus(guardId: string) {
    const supabase = createClient()

    try {
        // Check for active shift
        const { data: activeShift } = await supabase
            .from('work_events')
            .select('id, check_in_time, working_unit_id, duty_type, unit:units!working_unit_id(unit_name)')
            .eq('guard_id', guardId)
            .eq('event_status', 'CHECKED_IN')
            .eq('organization_id', CURRENT_ORG_ID)
            .is('deleted_at', null)
            .maybeSingle()

        if (activeShift) {
            return {
                isCheckedIn: true,
                checkInTime: activeShift.check_in_time,
                workingUnit: (activeShift as any).unit?.unit_name,
                dutyType: activeShift.duty_type
            }
        }

        return { isCheckedIn: false }
    } catch (error: any) {
        throw new Error(error.message || 'Failed to get status')
    }
}

// ============================================
// GUARD CHECK-IN (Field Terminal)
// ============================================

export async function guardFieldCheckIn(guardId: string, primaryUnitId: string) {
    // Use primary unit as working unit for field check-in
    return guardCheckIn({
        guard_id: guardId,
        working_unit_id: primaryUnitId,
        created_by: guardId
    })
}

// ============================================
// GUARD CHECK-OUT (Field Terminal)
// ============================================

export async function guardFieldCheckOut(guardId: string) {
    return guardCheckOut({
        guard_id: guardId,
        approved_by: guardId
    })
}
