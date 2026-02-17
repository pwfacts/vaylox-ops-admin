# Password Reset Email Troubleshooting Guide

## Issue
Password reset shows "reset link sent" but email is not received.

---

## **Root Causes & Solutions**

### 1. ✅ **Supabase Email Service Configuration**

#### **Check Email Provider Status**
1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt
2. Navigate to **Authentication** → **Email Templates**
3. Check if **SMTP** is configured (Custom SMTP vs Supabase built-in)

#### **Common Issues:**
- ❌ **Free tier limitation**: Supabase free tier has email rate limits
- ❌ **SMTP not configured**: Using default Supabase email (unreliable)
- ❌ **Email provider (Resend) not verified**: Domain verification pending

---

### 2. ✅ **Configure Custom SMTP (RECOMMENDED)**

If you haven't set up custom SMTP, emails may not be delivered reliably:

#### **Option A: Use Resend (Recommended)**
1. Go to https://resend.com and create account
2. Get your API key
3. In Supabase Dashboard:
   - Go to **Project Settings** → **Auth** → **SMTP Settings**
   - Enable Custom SMTP
   - **Host**: `smtp.resend.com`
   - **Port**: `465`
   - **Username**: `resend`
   - **Password**: `YOUR_RESEND_API_KEY`
   - **Sender Email**: `noreply@yourdomain.com` (must be verified)

#### **Option B: Use Gmail SMTP (For Testing)**
- **Host**: `smtp.gmail.com`
- **Port**: `587`
- **Username**: `your-gmail@gmail.com`
- **Password**: App-specific password (not your Gmail password)
- Enable "Less secure app access" or use App Password

---

### 3. ✅ **Email Template Configuration**

1. In Supabase Dashboard → **Authentication** → **Email Templates**
2. Click on **"Reset Password"** template
3. Verify the template is enabled
4. **Check the "From" email address** - must be verified by your SMTP provider

#### **Default Template:**
```html
<h2>Reset Password</h2>
<p>Follow this link to reset your password:</p>
<p><a href="{{ .ConfirmationURL }}">Reset Password</a></p>
```

Make sure `{{ .ConfirmationURL }}` is present!

---

### 4. ✅ **Check Redirect URL Configuration**

In Supabase Dashboard:
1. Go to **Authentication** → **URL Configuration**
2. Add your app's redirect URL to **Redirect URLs** list:
   ```
   io.supabase.jdssaas://reset-password
   ```
3. For web testing, also add:
   ```
   http://localhost:3000/reset-password
   https://yourdomain.com/reset-password
   ```

---

### 5. ✅ **Test Email Delivery**

#### **A. Check Spam/Junk Folder**
- Password reset emails often go to spam
- Check all folders including Promotions, Updates, Social

#### **B. Test with Different Email Providers**
Try with:
- ✅ Gmail
- ✅ Outlook/Hotmail
- ✅ Yahoo
- ❌ Some corporate emails block external SMTP

#### **C. Check Supabase Logs**
1. Go to Supabase Dashboard → **Logs** → **Auth Logs**
2. Filter by:
   - Event type: `user_recovery_requested`
   - Time: Last 1 hour
3. Look for errors in the logs

---

### 6. ✅ **Verify Email Rate Limits**

**Supabase Free Tier Limits:**
- **Built-in Email Service**: 3 emails per hour, 30 per day
- **Custom SMTP**: Unlimited (based on your SMTP provider)

If you hit rate limits, you'll see:
```
Rate limit exceeded
```

**Solution**: Configure custom SMTP

---

### 7. ✅ **Code-Level Checks**

#### **Updated Code (Already Fixed)**
```dart
Future<void> resetPassword(String email) async {
  try {
    await _client.auth.resetPasswordForEmail(
      email,
      redirectTo: 'io.supabase.jdssaas://reset-password',
    );
  } catch (e) {
    throw Exception('Failed to send password reset email: ${e.toString()}');
  }
}
```

#### **Test the Error Handling**
The code now throws exceptions if email fails. Check your UI screen for error messages.

---

## **Immediate Action Steps**

### **Step 1: Verify Email in Supabase Logs**
```bash
1. Open: https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/logs/auth-logs
2. Filter: Event type = "user_recovery_requested"
3. Check if email send succeeded or failed
```

### **Step 2: Configure Custom SMTP (If Not Done)**
```bash
1. Create Resend account: https://resend.com
2. Get API key
3. Configure in Supabase SMTP settings
4. Verify sender domain
```

### **Step 3: Test Password Reset**
```dart
// In your login screen, when user clicks "Forgot Password":
try {
  await AuthService().resetPassword('test@example.com');
  // Show success message
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Password reset email sent! Check your inbox and spam folder.')),
  );
} catch (e) {
  // Show error details
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Error: $e')),
  );
}
```

---

## **Common Error Messages & Solutions**

| Error | Cause | Solution |
|-------|-------|----------|
| "Invalid email" | Email format wrong | Verify email format |
| "Rate limit exceeded" | Too many requests | Wait or configure custom SMTP |
| "SMTP connection failed" | SMTP settings wrong | Verify SMTP credentials |
| "User not found" | Email not registered | User must sign up first |
| No error but no email | Templates disabled or spam | Check templates + spam folder |

---

## **Quick Fix Checklist**

- [ ] SMTP is configured (not using Supabase default)
- [ ] Sender email is verified in SMTP provider
- [ ] Email templates are enabled
- [ ] Redirect URL is added to allowed list
- [ ] Tested with Gmail (check spam folder)
- [ ] Checked Supabase auth logs for errors
- [ ] No rate limit hit (< 3 emails/hour if using default)
- [ ] Code includes redirectTo parameter ✅ (Fixed)

---

## **Testing Script**

Use this in Supabase SQL Editor to verify user exists:

```sql
-- Check if user with email exists
SELECT email, email_confirmed_at, created_at 
FROM auth.users 
WHERE email = 'your-test-email@example.com';
```

If user doesn't exist, you need to sign them up first before resetting password!

---

## **Next Steps**

1. **Check Supabase Auth Logs** (most important!)
2. **Configure Custom SMTP** if not already done
3. **Test with Gmail** and check spam folder
4. **Verify email exists** in Supabase auth.users table

---

## **Support Resources**

- Supabase Auth Docs: https://supabase.com/docs/guides/auth
- Resend Docs: https://resend.com/docs
- Email Template Guide: https://supabase.com/docs/guides/auth/auth-email-templates
