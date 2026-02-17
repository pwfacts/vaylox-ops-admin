// ============================================
// WORKFORCE LOGIN EDGE FUNCTION (HARDENED)
// Enhanced with session revocation and device trust
// ============================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const {
            employee_code,
            password,
            pin,
            device_fingerprint,
            device_name,
            device_type,
            device_os,
            device_model
        } = await req.json()

        if (!employee_code || (!password && !pin)) {
            return new Response(
                JSON.stringify({
                    success: false,
                    error: 'MISSING_CREDENTIALS',
                    message: 'Employee code and password/PIN required',
                }),
                {
                    status: 400,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                }
            )
        }

        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
            {
                auth: {
                    autoRefreshToken: false,
                    persistSession: false,
                },
            }
        )

        const clientIP = req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || null
        const userAgent = req.headers.get('user-agent') || null

        // STEP 1: Verify business identity
        const { data: loginResult, error: loginError } = await supabaseAdmin.rpc('workforce_login', {
            p_employee_code: employee_code,
            p_password: password || null,
            p_pin: pin || null,
            p_device_fingerprint: device_fingerprint || null,
            p_device_name: device_name || null,
            p_device_type: device_type || null,
            p_device_os: device_os || null,
            p_device_model: device_model || null,
            p_ip_address: clientIP,
            p_user_agent: userAgent,
        })

        if (loginError || !loginResult || !loginResult.success) {
            console.error('Login verification failed:', loginError || loginResult)
            return new Response(
                JSON.stringify(loginResult || { success: false, error: 'LOGIN_FAILED' }),
                {
                    status: 401,
                    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                }
            )
        }

        const profile = loginResult.profile
        const deterministicEmail = loginResult.deterministic_email

        // STEP 2: ENFORCE SINGLE AUTH USER PER PROFILE
        let authUserId = profile.linked_auth_user

        if (!authUserId) {
            // No linked auth user - create one with deterministic email
            const tempPassword = crypto.randomUUID()

            // First, check if user with this email already exists
            const { data: existingUsers } = await supabaseAdmin.auth.admin.listUsers()
            const existingUser = existingUsers?.users.find((u) => u.email === deterministicEmail)

            if (existingUser) {
                // Reuse existing auth user
                authUserId = existingUser.id
                console.log(`Reusing existing auth user: ${authUserId}`)
            } else {
                // Create new auth user
                const { data: authData, error: authError } = await supabaseAdmin.auth.admin.createUser({
                    email: deterministicEmail,
                    password: tempPassword,
                    email_confirm: true,
                    user_metadata: {
                        employee_code: employee_code,
                        role: profile.role,
                        full_name: profile.full_name,
                        organization_id: profile.organization_id,
                    },
                })

                if (authError) {
                    throw new Error('Failed to create auth user: ' + authError.message)
                }

                authUserId = authData.user.id
                console.log(`Created new auth user: ${authUserId}`)
            }

            // Link workforce profile to auth user
            const { error: linkError } = await supabaseAdmin.rpc('link_workforce_profile_to_auth_user', {
                p_profile_id: profile.id,
                p_auth_user_id: authUserId,
            })

            if (linkError) {
                console.error('Failed to link profile:', linkError)
                throw new Error('Failed to link profile')
            }
        } else {
            // AUTH USER ALREADY LINKED - ALWAYS REUSE
            console.log(`Reusing linked auth user: ${authUserId}`)
        }

        // STEP 3: Create session
        const { data: session, error: sessionError } = await supabaseAdmin.auth.admin.createSession({
            user_id: authUserId,
        })

        if (sessionError || !session) {
            throw new Error('Failed to create session: ' + sessionError?.message)
        }

        // STEP 4: Return session to client
        return new Response(
            JSON.stringify({
                success: true,
                session: {
                    access_token: session.access_token,
                    refresh_token: session.refresh_token,
                    expires_in: session.expires_in,
                    expires_at: session.expires_at,
                },
                user: {
                    id: authUserId,
                    employee_code: profile.employee_code,
                    role: profile.role,
                    full_name: profile.full_name,
                    organization_id: profile.organization_id,
                },
                must_change_password: profile.must_change_password,
                must_change_pin: profile.must_change_pin,
                device_trusted: loginResult.device_trusted || false,
                auth_method: loginResult.auth_method,
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            }
        )
    } catch (error) {
        console.error('Workforce login error:', error)
        return new Response(
            JSON.stringify({
                success: false,
                error: 'SERVER_ERROR',
                message: error.message || 'An unexpected error occurred',
            }),
            {
                status: 500,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            }
        )
    }
})
