# SMTP Configuration Steps for Supabase + Resend

## ⚠️ CRITICAL ISSUE FOUND
Your Supabase is NOT sending emails to Resend, even though SMTP might be "configured".

---

## 🔧 Fix Instructions (Step-by-Step)

### **Step 1: Enable Custom SMTP in Supabase**

1. **Open Supabase Project Settings:**
   ```
   https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/settings/auth
   ```

2. **Scroll to "SMTP Settings" section**

3. **Enable Custom SMTP:**
   - Look for toggle switch: **"Enable Custom SMTP"**
   - **Turn it ON** (should be green/blue)
   - If already ON, turn it OFF then ON again to refresh

4. **Fill in SMTP Configuration:**

   ```
   SMTP Provider Name: Resend
   SMTP Host: smtp.resend.com
   SMTP Port: 465
   SMTP User: resend
   SMTP Password: [YOUR_RESEND_API_KEY]
   SMTP Sender Email: onboarding@resend.dev
   SMTP Sender Name: JDS Management
   Enable TLS: YES (checked)
   ```

   **Important:** Use `onboarding@resend.dev` for testing (it's Resend's verified domain)

5. **Click "Save"**

---

### **Step 2: Get Resend API Key**

If you don't have your Resend API key:

1. Go to: https://resend.com/api-keys
2. Click "Create API Key"
3. Name: `Supabase-SMTP`
4. Permission: **Full Access**
5. Copy the key (starts with `re_...`)
6. **Save it somewhere** - you can't view it again!

---

### **Step 3: Verify Email Templates are Enabled**

1. Go to: https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/auth/templates

2. Click on **"Reset Password"** template

3. **Check these:**
   - [ ] Template is **Enabled** (toggle switch ON)
   - [ ] Subject line exists
   - [ ] Template contains `{{ .ConfirmationURL }}`
   - [ ] "From" email matches SMTP sender (`onboarding@resend.dev`)

4. If anything is wrong, fix it and **Save**

---

### **Step 4: Test Password Reset**

After configuring SMTP:

1. **Wait 1-2 minutes** for settings to propagate
2. **Try password reset again** in your app
3. **Check Resend dashboard** (refresh page): https://resend.com/emails
4. **Check your email** (including spam)

---

### **Step 5: Verify in Supabase Logs**

After testing, check logs:

1. Go to: https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/logs/auth-logs
2. Filter: Last 1 hour
3. Look for `/recover` requests
4. Check for any SMTP errors

**What to look for:**
- ✅ "request completed" with status 200 = Good
- ❌ "SMTP connection failed" = Bad SMTP config
- ❌ "Invalid sender email" = Wrong email in template

---

## 🐛 Common Issues & Fixes

### **Issue 1: "Enable Custom SMTP" is greyed out**
**Solution:** Your Supabase plan might not support custom SMTP. Check your plan.

### **Issue 2: "SMTP connection failed"**
**Causes:**
- Wrong API key
- Wrong port (use 465, not 587)
- TLS not enabled

**Solution:** 
- Regenerate Resend API key
- Use port 465
- Enable TLS checkbox

### **Issue 3: Still no emails in Resend**
**Solution:**
1. Turn OFF custom SMTP
2. Save
3. Turn ON custom SMTP
4. Re-enter all details
5. Save
6. Wait 2 minutes
7. Test again

### **Issue 4: "Invalid sender email"**
**Solution:**
- Use `onboarding@resend.dev` for testing
- OR verify your own domain in Resend first

---

## 📋 Checklist

Before testing, verify:

- [ ] Custom SMTP is **enabled** in Supabase
- [ ] SMTP Host = `smtp.resend.com`
- [ ] SMTP Port = `465`
- [ ] SMTP User = `resend`
- [ ] SMTP Password = valid Resend API key (starts with `re_`)
- [ ] Sender Email = `onboarding@resend.dev`
- [ ] TLS is **enabled**
- [ ] Password reset template is **enabled**
- [ ] Template has `{{ .ConfirmationURL }}`
- [ ] Waited 1-2 minutes after saving

---

## 🧪 Testing Steps

1. Open your app
2. Click "Forgot Password"
3. Enter: `ankitsingh589@gmail.com`
4. Click Submit
5. **Immediately check:**
   - Resend dashboard (https://resend.com/emails)
   - Supabase logs (https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/logs/auth-logs)
   - Your email inbox + spam

---

## 🎯 Expected Result

**After proper configuration:**

1. **In Resend Dashboard:**
   - New email should appear under "Emails"
   - Status: "Delivered" or "Bounced"
   - To: `ankitsingh589@gmail.com`
   - Subject: "Reset your password"

2. **In Email Inbox:**
   - Email from `onboarding@resend.dev`
   - Subject: "Reset your password"
   - Contains reset link

3. **In Supabase Logs:**
   - `/recover` request with status 200
   - No SMTP errors

---

## 🆘 If Still Not Working

If emails still don't appear in Resend after following all steps:

1. **Screenshot your SMTP settings** in Supabase (hide API key)
2. **Check Supabase auth logs** for specific error messages
3. **Verify Resend API key** is correct by creating a test email via Resend dashboard
4. **Contact Supabase support** - there might be a platform issue

---

## 📝 Alternative: Test SMTP Directly

You can test if SMTP is working by sending a test email via Supabase:

```sql
-- Run in Supabase SQL Editor
SELECT auth.send_magic_link('ankitsingh589@gmail.com');
```

This will trigger an email. Check Resend dashboard immediately.

---

## ⚡ Quick Fix Script

If you want to verify SMTP programmatically, here's a test:

```dart
// Add to your app for testing
Future<void> testPasswordReset() async {
  try {
    final response = await Supabase.instance.client.auth.resetPasswordForEmail(
      'ankitsingh589@gmail.com',
      redirectTo: 'io.supabase.jdssaas://reset-password',
    );
    print('✅ Password reset triggered');
    print('Now check Resend dashboard: https://resend.com/emails');
  } catch (e) {
    print('❌ Error: $e');
  }
}
```

---

**Remember:** The key indicator is **Resend dashboard must show the email** when SMTP is properly configured!
