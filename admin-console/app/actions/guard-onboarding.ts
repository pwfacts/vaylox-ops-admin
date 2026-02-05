'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'
import { getTenantFromSession, setTenantContext } from '@/lib/tenant'

// ============================================
// COMPREHENSIVE GUARD ONBOARDING
// ============================================

export async function createGuardWithFullBio(params: {
    // Basic Info
    full_name: string
    father_name: string
    mother_name?: string
    guard_code: string
    date_of_birth: string
    blood_group?: string

    // Contact
    email: string
    phone_number: string
    emergency_contact_name: string
    emergency_contact_phone: string
    emergency_contact_relation: string

    // Address
    present_address: string
    permanent_address: string

    // Identity
    aadhar_number: string
    aadhar_front_url: string
    aadhar_front_imagekit_id: string
    aadhar_back_url: string
    aadhar_back_imagekit_id: string
    pan_number?: string
    pan_card_url?: string
    pan_card_imagekit_id?: string

    // Bank Details
    bank_account_number?: string
    bank_name?: string
    bank_ifsc_code?: string
    bank_passbook_url?: string
    bank_passbook_imagekit_id?: string

    // Employment
    uan_number?: string
    primary_unit_id: string
    assigned_shift: 'day' | 'night' | 'rotating'
    shift_start_time: string
    shift_end_time: string
    employment_type: string
    monthly_salary: number

    // Role
    is_supervisor?: boolean
    supervised_unit_id?: string

    // Additional documents (up to 5)
    additional_documents?: Array<{
        document_url: string
        imagekit_file_id: string
        file_name: string
        document_type: string
    }>

    created_by: string
}) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // 1. Create guard record with all bio data
        const { data: guard, error: guardError } = await supabase
            .from('guards')
            .insert({
                organization_id: orgId,
                full_name: params.full_name,
                father_name: params.father_name,
                mother_name: params.mother_name,
                guard_code: params.guard_code,
                email: params.email,
                phone_number: params.phone_number,
                date_of_birth: params.date_of_birth,
                blood_group: params.blood_group,

                // Contact
                emergency_contact_name: params.emergency_contact_name,
                emergency_contact_phone: params.emergency_contact_phone,
                emergency_contact_relation: params.emergency_contact_relation,

                // Address
                present_address: params.present_address,
                permanent_address: params.permanent_address,

                // Identity
                aadhar_number: params.aadhar_number,
                aadhar_front_url: params.aadhar_front_url,
                aadhar_front_imagekit_id: params.aadhar_front_imagekit_id,
                aadhar_back_url: params.aadhar_back_url,
                aadhar_back_imagekit_id: params.aadhar_back_imagekit_id,
                pan_number: params.pan_number,
                pan_card_url: params.pan_card_url,
                pan_card_imagekit_id: params.pan_card_imagekit_id,

                // Bank
                bank_account_number: params.bank_account_number,
                bank_name: params.bank_name,
                bank_ifsc_code: params.bank_ifsc_code,
                bank_passbook_url: params.bank_passbook_url,
                bank_passbook_imagekit_id: params.bank_passbook_imagekit_id,

                // Employment
                uan_number: params.uan_number,
                primary_unit_id: params.primary_unit_id,
                assigned_shift: params.assigned_shift,
                shift_start_time: params.shift_start_time,
                shift_end_time: params.shift_end_time,
                employment_type: params.employment_type,
                monthly_salary: params.monthly_salary,
                employment_status: 'active',
                join_date: new Date().toISOString().split('T')[0],

                // Supervisor
                is_supervisor: params.is_supervisor || false,
                supervised_unit_id: params.supervised_unit_id,

                created_by: params.created_by
            })
            .select()
            .single()

        if (guardError) throw guardError

        // 2. Upload additional documents
        if (params.additional_documents && params.additional_documents.length > 0) {
            const documentsToInsert = params.additional_documents.map(doc => ({
                guard_id: guard.id,
                organization_id: orgId,
                document_type: 'other',
                custom_document_type: doc.document_type,
                document_url: doc.document_url,
                imagekit_file_id: doc.imagekit_file_id,
                file_name: doc.file_name,
                uploaded_by: params.created_by
            }))

            const { error: docsError } = await supabase
                .from('guard_documents')
                .insert(documentsToInsert)

            if (docsError) {
                console.error('Failed to upload additional documents:', docsError)
            }
        }

        revalidatePath('/workforce')

        return {
            success: true,
            guard: guard,
            message: 'Guard onboarded successfully!'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to create guard'
        }
    }
}

// ============================================
// PHOTO-BASED ATTENDANCE
// ============================================

/**
 * Guard marks attendance with photo and location
 */
export async function markAttendance(params: {
    guard_id: string
    unit_id: string
    punch_type: 'IN' | 'OUT'
    punch_photo_url: string
    punch_photo_imagekit_id: string
    latitude?: number
    longitude?: number
    location_accuracy?: number
    location_address?: string
    face_match_score?: number
    marked_by?: string // If supervisor marking for guard
}) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // 1. Verify guard exists and is active
        const { data: guard, error: guardError } = await supabase
            .from('guards')
            .select('id, full_name, employment_status, primary_unit_id, face_verification_enabled')
            .eq('id', params.guard_id)
            .eq('organization_id', orgId)
            .single()

        if (guardError || !guard) {
            throw new Error('Guard not found')
        }

        if (guard.employment_status !== 'active') {
            throw new Error('Guard is not active')
        }

        // 2. Check if already punched in/out today
        const today = new Date().toISOString().split('T')[0]
        const { data: existingPunch } = await supabase
            .from('attendance_logs')
            .select('id, punch_type')
            .eq('guard_id', params.guard_id)
            .eq('punch_date', today)
            .order('punch_time', { ascending: false })
            .limit(1)
            .maybeSingle()

        if (params.punch_type === 'IN' && existingPunch?.punch_type === 'IN') {
            throw new Error('Already punched in today. Punch out first.')
        }

        if (params.punch_type === 'OUT' && (!existingPunch || existingPunch.punch_type === 'OUT')) {
            throw new Error('Must punch in before punching out')
        }

        // 3. Face verification (if enabled)
        let faceVerified = false
        if (guard.face_verification_enabled && params.face_match_score !== undefined) {
            faceVerified = params.face_match_score >= 70 // 70% threshold
        }

        // 4. Create attendance log
        const { data: log, error: logError } = await supabase
            .from('attendance_logs')
            .insert({
                organization_id: orgId,
                guard_id: params.guard_id,
                unit_id: params.unit_id,
                punch_type: params.punch_type,
                punch_time: new Date().toISOString(),
                punch_date: today,
                punch_photo_url: params.punch_photo_url,
                punch_photo_imagekit_id: params.punch_photo_imagekit_id,
                face_match_score: params.face_match_score,
                face_verified: faceVerified,
                latitude: params.latitude,
                longitude: params.longitude,
                location_accuracy: params.location_accuracy,
                location_address: params.location_address,
                marked_by: params.marked_by
            })
            .select()
            .single()

        if (logError) throw logError

        revalidatePath('/guard/attendance')
        revalidatePath('/attendance')

        return {
            success: true,
            log: log,
            message: `Punched ${params.punch_type.toLowerCase()} successfully!`,
            face_verified: faceVerified
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to mark attendance'
        }
    }
}

/**
 * Supervisor marks attendance for their unit's guards
 */
export async function supervisorMarkAttendance(params: {
    supervisor_id: string
    guard_id: string
    punch_type: 'IN' | 'OUT'
    punch_photo_url: string
    punch_photo_imagekit_id: string
    notes?: string
}) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // 1. Verify supervisor
        const { data: supervisor, error: supError } = await supabase
            .from('guards')
            .select('id, supervised_unit_id, is_supervisor')
            .eq('id', params.supervisor_id)
            .eq('organization_id', orgId)
            .single()

        if (supError || !supervisor || !supervisor.is_supervisor) {
            throw new Error('Not authorized as supervisor')
        }

        // 2. Verify guard belongs to supervisor's unit
        const { data: guard, error: guardError } = await supabase
            .from('guards')
            .select('id, primary_unit_id')
            .eq('id', params.guard_id)
            .eq('organization_id', orgId)
            .single()

        if (guardError || !guard) {
            throw new Error('Guard not found')
        }

        if (guard.primary_unit_id !== supervisor.supervised_unit_id) {
            throw new Error('Guard not in your supervised unit')
        }

        // 3. Mark attendance
        const result = await markAttendance({
            guard_id: params.guard_id,
            unit_id: guard.primary_unit_id,
            punch_type: params.punch_type,
            punch_photo_url: params.punch_photo_url,
            punch_photo_imagekit_id: params.punch_photo_imagekit_id,
            marked_by: params.supervisor_id
        })

        return result
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to mark attendance'
        }
    }
}

/**
 * Update guard's face data for verification
 */
export async function updateGuardFaceData(params: {
    guard_id: string
    face_data_url: string
    face_data_imagekit_id: string
}) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        const { error } = await supabase
            .from('guards')
            .update({
                face_data_url: params.face_data_url,
                face_data_imagekit_id: params.face_data_imagekit_id,
                face_data_updated_at: new Date().toISOString(),
                face_verification_enabled: true
            })
            .eq('id', params.guard_id)
            .eq('organization_id', orgId)

        if (error) throw error

        revalidatePath('/guard/profile')

        return {
            success: true,
            message: 'Face data updated successfully'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to update face data'
        }
    }
}

/**
 * Get attendance history for a guard
 */
export async function getGuardAttendanceLogs(guard_id: string, days = 30) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    const startDate = new Date()
    startDate.setDate(startDate.getDate() - days)

    const { data, error } = await supabase
        .from('attendance_logs')
        .select(`
      *,
      unit:units!unit_id(id, unit_name),
      marked_by_guard:guards!marked_by(id, full_name, guard_code)
    `)
        .eq('guard_id', guard_id)
        .eq('organization_id', orgId)
        .gte('punch_date', startDate.toISOString().split('T')[0])
        .order('punch_time', { ascending: false })

    if (error) throw error

    return data || []
}

/**
 * Get today's attendance for supervisor's unit
 */
export async function getSupervisorUnitAttendance(supervisor_id: string) {
    const supabase = await createClient()
    const orgId = await getTenantFromSession()
    await setTenantContext(supabase, orgId)

    try {
        // Get supervisor's unit
        const { data: supervisor } = await supabase
            .from('guards')
            .select('supervised_unit_id')
            .eq('id', supervisor_id)
            .single()

        if (!supervisor?.supervised_unit_id) {
            throw new Error('Not a supervisor')
        }

        const today = new Date().toISOString().split('T')[0]

        // Get all guards in unit
        const { data: guards } = await supabase
            .from('guards')
            .select('id, full_name, guard_code, phone_number')
            .eq('primary_unit_id', supervisor.supervised_unit_id)
            .eq('employment_status', 'active')
            .eq('organization_id', orgId)

        if (!guards) return []

        // Get today's attendance for each guard
        const { data: logs } = await supabase
            .from('attendance_logs')
            .select('*')
            .eq('unit_id', supervisor.supervised_unit_id)
            .eq('punch_date', today)
            .in('guard_id', guards.map(g => g.id))

        // Combine data
        return guards.map(guard => {
            const guardLogs = logs?.filter(l => l.guard_id === guard.id) || []
            const lastPunch = guardLogs[0]

            return {
                ...guard,
                attendance_status: lastPunch ? lastPunch.punch_type : 'ABSENT',
                last_punch_time: lastPunch?.punch_time,
                logs: guardLogs
            }
        })
    } catch (error: any) {
        throw error
    }
}
