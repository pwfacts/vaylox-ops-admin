// ============================================
// WORKFORCE SESSION REVOCATION EDGE FUNCTION
// Revoke Supabase sessions from database trigger
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
        const { auth_user_id, profile_id, reason } = await req.json()

        if (!auth_user_id && !profile_id) {
            return new Response(
                JSON.stringify({
                    success: false,
                    error: 'MISSING_PARAMETERS',
                    message: 'auth_user_id or profile_id required',
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

        let targetAuthUserId = auth_user_id

        // If only profile_id provided, get auth user
        if (!targetAuthUserId && profile_id) {
            const { data: profile } = await supabaseAdmin
                .from('workforce_profiles')
                .select('linked_auth_user')
                .eq('id', profile_id)
                .single()

            if (profile?.linked_auth_user) {
                targetAuthUserId = profile.linked_auth_user
            } else {
                return new Response(
                    JSON.stringify({
                        success: false,
                        error: 'NO_AUTH_USER',
                        message: 'No auth user linked to this profile',
                    }),
                    {
                        status: 400,
                        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
                    }
                )
            }
        }

        // METHOD 1: Sign out all sessions for user
        // This invalidates refresh tokens
        const { error: signOutError } = await supabaseAdmin.auth.admin.signOut(targetAuthUserId, 'global')

        if (signOutError) {
            console.error('Sign out error:', signOutError)
            // Continue anyway - may not be critical
        }

        // METHOD 2: Update user metadata to force re-authentication
        // (Optional - adds extra layer)
        const { error: updateError } = await supabaseAdmin.auth.admin.updateUserById(targetAuthUserId, {
            user_metadata: {
                session_revoked_at: new Date().toISOString(),
                revocation_reason: reason || 'SECURITY_EVENT',
            },
        })

        if (updateError) {
            console.error('Update metadata error:', updateError)
        }

        console.log(`Revoked all sessions for user ${targetAuthUserId}. Reason: ${reason}`)

        return new Response(
            JSON.stringify({
                success: true,
                auth_user_id: targetAuthUserId,
                revoked_at: new Date().toISOString(),
                reason: reason || 'SECURITY_EVENT',
            }),
            {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            }
        )
    } catch (error) {
        console.error('Session revocation error:', error)
        return new Response(
            JSON.stringify({
                success: false,
                error: 'SERVER_ERROR',
                message: error.message || 'Failed to revoke sessions',
            }),
            {
                status: 500,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            }
        )
    }
})
