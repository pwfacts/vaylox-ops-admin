'use server'

import { createClient } from '@/lib/supabase'
import { revalidatePath } from 'next/cache'

// ============================================
// ORGANIZATION SIGNUP (Self-Serve)
// ============================================

export async function signupOrganization(formData: {
    // Organization details
    organizationName: string
    slug: string

    // Admin user details
    adminEmail: string
    adminPassword: string
    adminName: string

    // Subscription
    plan?: 'starter' | 'professional' | 'enterprise'
}) {
    const supabase = await createClient()

    try {
        // 1️⃣ Check if slug is available
        const { data: existingOrg } = await supabase
            .from('organizations')
            .select('id')
            .eq('slug', formData.slug.toLowerCase())
            .maybeSingle()

        if (existingOrg) {
            throw new Error('Organization slug already taken')
        }

        // 2️⃣ Create auth user
        const { data: authData, error: authError } = await supabase.auth.signUp({
            email: formData.adminEmail,
            password: formData.adminPassword,
            options: {
                data: {
                    full_name: formData.adminName
                }
            }
        })

        if (authError || !authData.user) {
            throw authError || new Error('Failed to create user')
        }

        // 3️⃣ Create organization
        const guardLimit = formData.plan === 'enterprise' ? 500 :
            formData.plan === 'professional' ? 200 : 50

        const { data: org, error: orgError } = await supabase
            .from('organizations')
            .insert({
                name: formData.organizationName,
                slug: formData.slug.toLowerCase().replace(/\s+/g, '-'),
                plan: formData.plan || 'starter',
                guard_limit: guardLimit,
                subscription_status: 'trial',
                trial_ends_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString()
            })
            .select()
            .single()

        if (orgError) {
            throw orgError
        }

        // 4️⃣ Link user to organization
        const { error: linkError } = await supabase
            .from('organization_users')
            .insert({
                organization_id: org.id,
                user_id: authData.user.id,
                email: formData.adminEmail,
                role: 'admin'
            })

        if (linkError) {
            throw linkError
        }

        return {
            success: true,
            message: 'Organization created successfully! Please check your email to verify your account.',
            organization: org,
            userId: authData.user.id
        }
    } catch (error: any) {
        return {
            success: false,
            error: error.message || 'Failed to create organization'
        }
    }
}

// ============================================
// LOGIN
// ============================================

export async function login(email: string, password: string) {
    const supabase = await createClient()

    const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password
    })

    if (error) {
        return { success: false, error: error.message }
    }

    revalidatePath('/', 'layout')

    return { success: true, user: data.user }
}

// ============================================
// LOGOUT
// ============================================

export async function logout() {
    const supabase = await createClient()

    await supabase.auth.signOut()

    revalidatePath('/', 'layout')
}

// ============================================
// ADD PLATFORM ADMIN (Manual - for initial setup)
// ============================================

export async function addPlatformAdmin(email: string) {
    const supabase = await createClient()

    // Get user by email
    const { data: users } = await supabase.auth.admin.listUsers()
    const user = users?.users.find(u => u.email === email)

    if (!user) {
        throw new Error('User not found')
    }

    // Add to platform_admins
    const { error } = await supabase
        .from('platform_admins')
        .insert({
            user_id: user.id,
            email: email
        })

    if (error) throw error

    return { success: true }
}
