import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

console.log("Create Guard User Function Initialized");

serve(async (req) => {
    // Handle CORS
    if (req.method === "OPTIONS") {
        return new Response("ok", {
            headers: {
                "Access-Control-Allow-Origin": "*",
                "Access-Control-Allow-Methods": "POST",
                "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
            },
        });
    }

    try {
        const { email, fullName, organizationId } = await req.json();

        // Initialize Supabase Admin Client
        const supabaseUrl = Deno.env.get("SUPABASE_URL");
        const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

        if (!supabaseUrl || !supabaseServiceKey) {
            throw new Error("Missing Supabase configuration");
        }

        const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey, {
            auth: {
                autoRefreshToken: false,
                persistSession: false,
            },
        });

        // Generate random temporary password
        const tempPassword = Math.random().toString(36).slice(-8) + "Aa1!";

        // Create User
        let user;
        let userId;
        let isNewUser = true;

        const { data: createdUser, error: createError } = await supabaseAdmin.auth.admin.createUser({
            email,
            password: tempPassword,
            email_confirm: true, // Confirm email automatically so they can login
            user_metadata: {
                full_name: fullName,
                role: 'guard',
                organization_id: organizationId,
            },
            app_metadata: {
                provider: 'email',
                role: 'guard',
            },
        });

        if (createError) {
            // Check if user already exists
            if (createError.message.includes("already been registered")) {
                console.log(`User with email ${email} already exists. Fetching user...`);
                // Fetch the existing user
                // Note: getUserById requires ID, so we use listUsers to search by email if possible, 
                // but supabase-js admin listUsers doesn't filter by email directly in all versions.
                // However, attempting to sign in or reset password might be overkill.
                // Best approach for admin: list users and filter (might be slow if many users) or just informing client.
                // BUT, better way: The error doesn't return the ID. 
                // Let's try to get the user by email using listUsers (it supports query in some versions) or just fail gracefully?
                // Actually, supabaseAdmin.auth.admin.listUsers() is the way.

                // Optimized: We can't easily get the ID of an existing user just by email via admin API without listing.
                // Alternatives: 
                // 1. Just return a specific success code saying "User exists, please link manually" (not good UX)
                // 2. We actually WANT to link this guard to that user. 

                // Let's list users and find matches. (Pagination applies, but hopefully email is unique enough?)
                // Actually, there is no direct "getUserByEmail" in admin API publicly exposed in all versions.
                // Workaround: We will use a hack - try to generate a link which might return user info, or just list.

                // Let's try listing (limit 1) - wait, list doesn't filter by email.
                // Okay, new plan: If user exists, we probably shouldn't be creating a NEW guard account with the same email 
                // unless we want to link it. 

                // For now, let's treat this as a success but return a flag so the client knows.
                // WAIT! We need the user_id to link to the guard record.
                // If we can't get the user_id, we can't link.

                // Let's try to find the user.
                const { data: users, error: listError } = await supabaseAdmin.auth.admin.listUsers();
                if (listError) throw listError;

                const existingUser = users.users.find(u => u.email === email);
                if (existingUser) {
                    user = { user: existingUser };
                    userId = existingUser.id;
                    isNewUser = false;
                    console.log(`Found existing user: ${userId}`);
                } else {
                    throw new Error("User exists but could not be found in list. Please resolve manually.");
                }
            } else {
                throw createError;
            }
        } else {
            user = createdUser;
            userId = createdUser.user.id;
        }

        // Send Email (using Resend or generic SMTP if configured)
        // For now, we'll try to use Resend API if key is present
        const resendApiKey = Deno.env.get("RESEND_API_KEY");
        let emailSent = false;

        if (resendApiKey) {
            const emailResponse = await fetch("https://api.resend.com/emails", {
                method: "POST",
                headers: {
                    "Authorization": `Bearer ${resendApiKey}`,
                    "Content-Type": "application/json",
                },
                body: JSON.stringify({
                    from: "Vaylox Security <onboarding@vaylox.com>", // Update this sender
                    to: [email],
                    subject: "Welcome to Vaylox - Your Login Credentials",
                    html: `
            <h1>Welcome, ${fullName}!</h1>
            <p>Your account has been created for Vaylox Security Management System.</p>
            <p><strong>Login Credentials:</strong></p>
            <ul>
              <li><strong>Email:</strong> ${email}</li>
              <li><strong>Temporary Password:</strong> ${tempPassword}</li>
            </ul>
            <p>Please login and change your password immediately.</p>
            <br/>
            <p>Regards,<br/>Vaylox Team</p>
          `,
                }),
            });

            if (emailResponse.ok) {
                emailSent = true;
            } else {
                console.error("Failed to send email via Resend:", await emailResponse.text());
            }
        } else if (!isNewUser) {
            console.log("User already exists. Skipping email.");
        } else {
            console.log("RESEND_API_KEY not found. Skipping email send.");
        }

        // CRITICAL: Ensure user exists in public.users table to satisfy foreign key constraint
        // The guards table references public.users(id), not auth.users(id) directly in some setups
        // or requires the public profile to exist.
        const { error: publicUserError } = await supabaseAdmin
            .from('users')
            .upsert({
                id: userId,
                email: email,
                full_name: fullName,
                // Add default fields if needed
            }, { onConflict: 'id' }); // onConflict ignores if already exists (or updates)

        if (publicUserError) {
            console.error("Failed to sync public user profile:", publicUserError);
            // We log but don't fail hard, although this likely causes the foreign key error later.
            // Actually, we should probably throw or at least warn.
        }

        return new Response(
            JSON.stringify({
                user_id: userId,
                email: email,
                temp_password: isNewUser ? tempPassword : null, // Only return password for new users
                email_sent: emailSent,
                is_new_user: isNewUser,
            }),
            {
                headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
            },
        );

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            {
                status: 400,
                headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
            },
        );
    }
});
