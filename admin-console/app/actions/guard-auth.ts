'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'

// ============================================
// GUARD AUTHENTICATION - ADMIN MANAGED
// ============================================

/**
 * Admin creates guard account with email/password
 */
export async function createGuardAccount(params: {
    guard_id: string
    email: string
    password: string
    created_by: string
}) {
    const supabase = await createClient()

    try {
        // 1. Create auth user
        const { data: authData, error: authError } = await supabase.auth.admin.createUser({
            email: params.email,
            password: params.password,
            email_confirm: true, // Auto-confirm for admin-created accounts
            user_metadata: {
                role: 'guard',
                guard_id: params.guard_id,
                created_by: params.created_by
            }
        })

        if (authError || !authData.user) {
            throw authError || new Error('Failed to create auth user')
        }

        // 2. Link auth user to guard record
        const { error: updateError } = await supabase
            .from('guards')
            .update({
                user_id: authData.user.id,
                auth_provider: 'email'
            })
            .eq('id', params.guard_id)

        if (updateError) {
            // Rollback: delete auth user if guard update fails
            await supabase.auth.admin.deleteUser(authData.user.id)
            throw updateError
        }

        revalidatePath('/workforce')

        return {
            success: true,
            user_id: authData.user.id,
            message: 'Guard account created successfully'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to create guard account'
        }
    }
}

/**
 * Admin resets guard password
 */
export async function resetGuardPassword(params: {
    guard_id: string
    new_password: string
    reset_by: string
}) {
    const supabase = await createClient()

    try {
        // Get guard's user_id
        const { data: guard, error: guardError } = await supabase
            .from('guards')
            .select('user_id, full_name')
            .eq('id', params.guard_id)
            .single()

        if (guardError || !guard?.user_id) {
            throw new Error('Guard account not found')
        }

        // Update password
        const { error: updateError } = await supabase.auth.admin.updateUserById(
            guard.user_id,
            { password: params.new_password }
        )

        if (updateError) {
            throw updateError
        }

        // Log password reset
        await supabase
            .from('guard_documents')
            .insert({
                guard_id: params.guard_id,
                document_type: 'other',
                document_url: 'N/A',
                file_name: 'password_reset_log',
                notes: `Password reset by admin ${params.reset_by}`,
                uploaded_by: params.reset_by
            })

        revalidatePath('/workforce')

        return {
            success: true,
            message: `Password reset successful for ${guard.full_name}`
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to reset password'
        }
    }
}

// ============================================
// GUARD LOGIN
// ============================================

/**
 * Guard login with email/password
 */
export async function guardLoginWithEmail(email: string, password: string) {
    const supabase = await createClient()

    try {
        const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password
        })

        if (error) throw error

        // Verify user is a guard
        const { data: guard } = await supabase
            .from('guards')
            .select('id, full_name, guard_code, primary_unit_id, employment_status')
            .eq('user_id', data.user.id)
            .single()

        if (!guard) {
            await supabase.auth.signOut()
            throw new Error('Not registered as a guard')
        }

        if (guard.employment_status !== 'active') {
            await supabase.auth.signOut()
            throw new Error(`Account status:${guard.employment_status}. Contact admin.`)
        }

        revalidatePath('/', 'layout')

        return {
            success: true,
            guard: guard, user: data.user
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Login failed'
        }
    }
}

/**
 * Get Google OAuth URL for guards
 */
export async function getGuardGoogleOAuthUrl() {
    const supabase = await createClient()

    const { data, error } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: {
            redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/auth/callback?type=guard`,
            queryParams: {
                access_type: 'offline',
                prompt: 'consent'
            }
        }
    })

    if (error) {
        return { success: false, error: error.message }
    }

    return { success: true, url: data.url }
}

/**
 * Handle Google OAuth callback for guards
 */
export async function handleGuardGoogleCallback(user_id: string, google_id: string) {
    const supabase = await createClient()

    try {
        // Check if guard already exists with this Google ID
        const { data: existingGuard } = await supabase
            .from('guards')
            .select('id, full_name')
            .eq('google_id', google_id)
            .maybeSingle()

        if (existingGuard) {
            // Link user_id if not already linked
            await supabase
                .from('guards')
                .update({ user_id })
                .eq('id', existingGuard.id)

            return {
                success: true,
                guard_id: existingGuard.id,
                message: 'Login successful'
            }
        }

        // New Google user - needs manual linking by admin
        return {
            success: false,
            error: 'Google account not linked. Please contact your administrator.'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message
        }
    }
}

/**
 * Admin links Google account to guard
 */
export async function linkGuardGoogleAccount(params: {
    guard_id: string
    google_email: string
    google_id: string
}) {
    const supabase = await createClient()

    try {
        const { error } = await supabase
            .from('guards')
            .update({
                google_id: params.google_id,
                auth_provider: 'google'
            })
            .eq('id', params.guard_id)

        if (error) throw error

        revalidatePath('/workforce')

        return {
            success: true,
            message: 'Google account linked successfully'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to link Google account'
        }
    }
}

// ============================================
// GUARD PROFILE MANAGEMENT
// ============================================

/**
 * Update guard profile (by guard themselves)
 */
export async function updateGuardProfile(params: {
    guard_id: string
    profile_data: {
        date_of_birth?: string
        blood_group?: string
        emergency_contact_name?: string
        emergency_contact_phone?: string
        permanent_address?: string
        current_address?: string
        aadhar_number?: string
        pan_number?: string
        bio_data?: Record<string, any>
    }
}) {
    const supabase = await createClient()

    try {
        // Get current user
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) throw new Error('Not authenticated')

        // Verify guard owns this profile
        const { data: guard } = await supabase
            .from('guards')
            .select('id')
            .eq('id', params.guard_id)
            .eq('user_id', user.id)
            .single()

        if (!guard) {
            throw new Error('Unauthorized')
        }

        // Update profile
        const { error } = await supabase
            .from('guards')
            .update(params.profile_data)
            .eq('id', params.guard_id)

        if (error) throw error

        revalidatePath('/guard/profile')

        return {
            success: true,
            message: 'Profile updated successfully'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to update profile'
        }
    }
}

/**
 * Update guard profile photo (ImageKit)
 */
export async function updateGuardProfilePhoto(params: {
    guard_id: string
    photo_url: string
    imagekit_file_id: string
}) {
    const supabase = await createClient()

    try {
        // Get current user
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) throw new Error('Not authenticated')

        // Verify guard owns this profile
        const { data: guard } = await supabase
            .from('guards')
            .select('id, profile_photo_imagekit_id')
            .eq('id', params.guard_id)
            .eq('user_id', user.id)
            .single()

        if (!guard) {
            throw new Error('Unauthorized')
        }

        // TODO: Delete old photo from ImageKit if exists
        // if (guard.profile_photo_imagekit_id) {
        //   await deleteFromImageKit(guard.profile_photo_imagekit_id)
        // }

        // Update with new photo
        const { error } = await supabase
            .from('guards')
            .update({
                profile_photo_url: params.photo_url,
                profile_photo_imagekit_id: params.imagekit_file_id
            })
            .eq('id', params.guard_id)

        if (error) throw error

        revalidatePath('/guard/profile')

        return {
            success: true,
            message: 'Profile photo updated successfully',
            photo_url: params.photo_url
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to update photo'
        }
    }
}

/**
 * Upload guard document (ID cards, certificates, etc.)
 */
export async function uploadGuardDocument(params: {
    guard_id: string
    organization_id: string
    document_type: 'aadhar_card' | 'pan_card' | 'photo_id' | 'address_proof' | 'certificate' | 'other'
    document_url: string
    imagekit_file_id: string
    file_name: string
    notes?: string
}) {
    const supabase = await createClient()

    try {
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) throw new Error('Not authenticated')

        const { data, error } = await supabase
            .from('guard_documents')
            .insert({
                guard_id: params.guard_id,
                organization_id: params.organization_id,
                document_type: params.document_type,
                document_url: params.document_url,
                imagekit_file_id: params.imagekit_file_id,
                file_name: params.file_name,
                uploaded_by: user.id,
                notes: params.notes
            })
            .select()
            .single()

        if (error) throw error

        revalidatePath('/guard/documents')

        return {
            success: true,
            document: data,
            message: 'Document uploaded successfully'
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to upload document'
        }
    }
}

/**
 * Get guard documents
 */
export async function getGuardDocuments(guard_id: string) {
    const supabase = await createClient()

    const { data, error } = await supabase
        .from('guard_documents')
        .select('*')
        .eq('guard_id', guard_id)
        .order('uploaded_at', { ascending: false })

    if (error) throw error

    return data || []
}

/**
 * Get guard profile
 */
export async function getGuardProfile(guard_id: string) {
    const supabase = await createClient()

    const { data, error } = await supabase
        .from('guards')
        .select(`
      *,
      unit:units!primary_unit_id(id, unit_name),
      documents:guard_documents(*)
    `)
        .eq('id', guard_id)
        .single()

    if (error) throw error

    return data
}
