import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
};

interface CreateGuardRequest {
    guardData: {
        full_name: string;
        email: string;
        phone: string;
        organization_id: string;
        guard_code?: string;
        assigned_unit_id?: string;
        // ... other guard fields
    };
    sendPasswordEmail?: boolean;
}

Deno.serve(async (req) => {
    // Handle CORS preflight
    if (req.method === "OPTIONS") {
        return new Response(null, { headers: corsHeaders });
    }

    try {
        // Initialize Supabase client with SERVICE ROLE for admin operations
        const supabaseAdmin = createClient(
            Deno.env.get("SUPABASE_URL") ?? "",
            Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
            {
                auth: {
                    autoRefreshToken: false,
                    persistSession: false,
                },
            }
        );

        // Get the authorization header
        const authHeader = req.headers.get("Authorization");
        if (!authHeader) {
            throw new Error("Missing authorization header");
        }

        // Verify the user making the request
        const token = authHeader.replace("Bearer ", "");
        const {
            data: { user },
            error: authError,
        } = await supabaseAdmin.auth.getUser(token);

        if (authError || !user) {
            throw new Error("Unauthorized");
        }

        // Parse request body
        const { guardData, sendPasswordEmail = true }: CreateGuardRequest =
            await req.json();

        if (!guardData.email || !guardData.full_name) {
            throw new Error("Email and full name are required");
        }

        // Generate a random password
        const randomPassword = generateSecurePassword();

        // Step 1: Create auth user
        const {
            data: authUser,
            error: createAuthError,
        } = await supabaseAdmin.auth.admin.createUser({
            email: guardData.email,
            password: randomPassword,
            email_confirm: true, // Auto-confirm email
            user_metadata: {
                full_name: guardData.full_name,
                role: "guard",
            },
        });

        if (createAuthError) {
            throw new Error(`Failed to create auth user: ${createAuthError.message}`);
        }

        // Step 2: Create guard record
        const { data: guard, error: guardError } = await supabaseAdmin
            .from("guards")
            .insert({
                ...guardData,
                user_id: authUser.user.id,
                status: "active",
            })
            .select()
            .single();

        if (guardError) {
            // Rollback: Delete the auth user if guard creation fails
            await supabaseAdmin.auth.admin.deleteUser(authUser.user.id);
            throw new Error(`Failed to create guard: ${guardError.message}`);
        }

        // Step 3: Store temporary password for admin viewing (encrypted)
        await supabaseAdmin.from("temporary_passwords").insert({
            user_id: authUser.user.id,
            encrypted_password: btoa(randomPassword), // Simple encoding, use crypto in production
            created_by: user.id,
            expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(), // 7 days
        });

        // Step 4: Send password email if enabled
        let emailSent = false;
        let emailError = null;

        if (sendPasswordEmail) {
            try {
                // Send email using Resend via Supabase Auth
                const { error: emailSendError } = await supabaseAdmin.auth.admin
                    .generateLink({
                        type: "magiclink",
                        email: guardData.email,
                    });

                if (!emailSendError) {
                    // Also send a custom email with credentials via separate email function
                    const emailResponse = await fetch(
                        `${Deno.env.get("SUPABASE_URL")}/functions/v1/send-guard-credentials`,
                        {
                            method: "POST",
                            headers: {
                                "Content-Type": "application/json",
                                Authorization: `Bearer ${Deno.env.get("SUPABASE_ANON_KEY")}`,
                            },
                            body: JSON.stringify({
                                email: guardData.email,
                                fullName: guardData.full_name,
                                password: randomPassword,
                                guardCode: guard.guard_code,
                            }),
                        }
                    );

                    emailSent = emailResponse.ok;
                    if (!emailResponse.ok) {
                        emailError = await emailResponse.text();
                    }
                } else {
                    emailError = emailSendError.message;
                }
            } catch (err) {
                console.error("Email sending failed:", err);
                emailError = err.message;
            }
        }

        // Return response
        return new Response(
            JSON.stringify({
                success: true,
                data: {
                    guard: guard,
                    authUserId: authUser.user.id,
                    emailSent: emailSent,
                    emailError: emailError,
                    // Include password in response for admin to share if email fails
                    temporaryPassword: emailSent ? null : randomPassword,
                },
                message: emailSent
                    ? "Guard created successfully. Credentials sent via email."
                    : "Guard created successfully. Email failed - please share password manually.",
            }),
            {
                status: 200,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    } catch (error) {
        console.error("Error creating guard:", error);
        return new Response(
            JSON.stringify({
                success: false,
                error: error.message,
            }),
            {
                status: 400,
                headers: { ...corsHeaders, "Content-Type": "application/json" },
            }
        );
    }
});

function generateSecurePassword(length = 12): string {
    const charset =
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*";
    let password = "";
    const array = new Uint8Array(length);
    crypto.getRandomValues(array);
    for (let i = 0; i < length; i++) {
        password += charset[array[i] % charset.length];
    }
    return password;
}
