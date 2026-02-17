import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface SendCredentialsRequest {
  email: string;
  fullName: string;
  password: string;
  guardCode?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const { email, fullName, password, guardCode }: SendCredentialsRequest =
      await req.json();

    // Get Resend API key from environment
    const resendApiKey = Deno.env.get("RESEND_API_KEY");

    if (!resendApiKey) {
      throw new Error("RESEND_API_KEY not configured");
    }

    // Send email using Resend
    const emailResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${resendApiKey}`,
      },
      body: JSON.stringify({
        from: "JDS Management <onboarding@resend.dev>", // Update with your verified domain
        to: [email],
        subject: "Welcome to JDS Guard Management - Your Login Credentials",
        html: generateEmailTemplate(fullName, email, password, guardCode),
      }),
    });

    if (!emailResponse.ok) {
      const errorText = await emailResponse.text();
      throw new Error(`Resend API error: ${errorText}`);
    }

    const emailData = await emailResponse.json();

    return new Response(
      JSON.stringify({
        success: true,
        emailId: emailData.id,
        message: "Credentials sent successfully",
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Email sending error:", error);
    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});

function generateEmailTemplate(
  fullName: string,
  email: string,
  password: string,
  guardCode?: string
): string {
  return `
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Welcome to JDS Management</title>
</head>
<body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
  <div style="background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); padding: 30px; text-align: center; border-radius: 10px 10px 0 0;">
    <h1 style="color: white; margin: 0;">Welcome to JDS Management</h1>
  </div>
  
  <div style="background: #f9f9f9; padding: 30px; border-radius: 0 0 10px 10px;">
    <h2 style="color: #667eea;">Hello ${fullName}!</h2>
    
    <p>Your guard account has been successfully created. You can now access the JDS Guard Management mobile app with the following credentials:</p>
    
    <div style="background: white; padding: 20px; border-radius: 8px; margin: 20px 0; border-left: 4px solid #667eea;">
      ${guardCode ? `<p><strong>Guard Code:</strong> <code style="background: #e8eaf6; padding: 4px 8px; border-radius: 4px; font-size: 16px;">${guardCode}</code></p>` : ""}
      <p><strong>Email:</strong> <code style="background: #e8eaf6; padding: 4px 8px; border-radius: 4px;">${email}</code></p>
      <p><strong>Temporary Password:</strong> <code style="background: #e8eaf6; padding: 4px 8px; border-radius: 4px; color: #d32f2f; font-size: 16px;">${password}</code></p>
    </div>
    
    <div style="background: #fff3cd; border-left: 4px solid #ffc107; padding: 15px; margin: 20px 0; border-radius: 4px;">
      <p style="margin: 0;"><strong>⚠️ Important Security Notice:</strong></p>
      <p style="margin: 10px 0 0 0;">Please change this temporary password after your first login for security reasons.</p>
    </div>
    
    <h3 style="color: #667eea;">Getting Started:</h3>
    <ol style="padding-left: 20px;">
      <li>Download the <strong>JDS Guard App</strong> from the Play Store</li>
      <li>Open the app and select <strong>"Guard Login"</strong></li>
      <li>Enter your email and temporary password</li>
      <li>Complete the setup wizard to change your password</li>
      <li>Set up face recognition for quick attendance marking</li>
    </ol>
    
    <div style="margin-top: 30px; padding-top: 20px; border-top: 1px solid #ddd;">
      <p style="font-size: 14px; color: #666;">
        Need help? Contact your supervisor or field officer.<br>
        <strong>Support:</strong> support@jdsmanagement.com
      </p>
    </div>
  </div>
  
  <div style="text-align: center; margin-top: 20px; color: #999; font-size: 12px;">
    <p>This is an automated email. Please do not reply.</p>
    <p>&copy; ${new Date().getFullYear()} JDS SafeGuard and Management Pvt. Ltd. All rights reserved.</p>
  </div>
</body>
</html>
  `;
}
