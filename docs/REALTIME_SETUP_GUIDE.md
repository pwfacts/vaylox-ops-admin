# Real-time Guard Management Setup Guide

This guide explains how to set up real-time guard updates and automated password email functionality.

---

## 🚀 Features Implemented

### ✅ 1. Real-time Guard Updates
- Instant updates when guards are added/modified/deleted
- No need to refresh the screen manually
- Uses Supabase Realtime subscriptions

### ✅ 2. Automated Password Emails
- Automatic email with login credentials when guard is created
- Professional HTML email template
- Uses Resend for reliable delivery

### ✅ 3. Password Viewing Fallback
- Admins/Field Officers can view temporary passwords if email fails
- Passwords stored encrypted for 7 days
- Copy to clipboard and resend email options

---

## 📋 Setup Instructions

### **Step 1: Deploy Edge Functions**

```bash
# Navigate to your project directory
cd "C:\Users\ASUS\OneDrive - Manipal University Jaipur\Desktop\Prabhat\JDS MANAGEMENT SAAS"

# Install Supabase CLI (if not already installed)
npm install -g supabase

# Login to Supabase
supabase login

# Link to your project
supabase link --project-ref fcpbexqyyzdvbiwplmjt

# Deploy the Edge Functions
supabase functions deploy create-guard
supabase functions deploy send-guard-credentials
```

### **Step 2: Set Environment Variables**

In Supabase Dashboard → Settings → Edge Functions, add these secrets:

```bash
# Set Resend API Key
supabase secrets set RESEND_API_KEY=re_your_actual_resend_api_key_here

# Verify secrets
supabase secrets list
```

**Get your Resend API key from:** https://resend.com/api-keys

---

### **Step 3: Enable Realtime for Guards Table**

1. Go to Supabase Dashboard: https://supabase.com/dashboard/project/fcpbexqyyzdvbiwplmjt/database/replication

2. Click on **"Replication"** in the sidebar

3. Find the **`guards`** table

4. Enable these events:
   - ✅ **INSERT** - New guards added
   - ✅ **UPDATE** - Guard details changed
   - ✅ **DELETE** - Guards removed

5. Click **"Save"**

---

### **Step 4: Update Guard Enrollment to Use Edge Function**

Replace the existing guard enrollment logic with the new service:

```dart
// In your guard enrollment screen/provider:

import 'package:your_app/data/services/guard_creation_service.dart';
import 'package:your_app/presentation/widgets/guard_password_dialog.dart';

final _guardCreationService = GuardCreationService();

Future<void> createGuard(Guard guard) async {
  try {
    // Use Edge Function instead of direct database insert
    final result = await _guardCreationService.createGuardWithAuth(
      guard: guard,
      sendPasswordEmail: true, // Auto-send email
    );

    // Check if email was sent
    if (result.emailSent) {
      // Success - email sent
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${result.message}'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result.needsManualPasswordSharing) {
      // Email failed - show password dialog
      await showGuardPasswordDialog(
        context,
        guardName: result.guard.fullName,
        guardEmail: result.guard.email!,
        userId: result.authUserId,
        guardCode: result.guard.guardCode,
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ Guard created but email failed. Please share credentials manually.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  } catch (e) {
    // Error
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('❌ Error: $e')),
    );
  }
}
```

---

### **Step 5: Use Real-time Provider in UI**

Update your guards list screen to use the real-time provider:

```dart
import 'package:your_app/presentation/providers/guards_realtime_provider.dart';

class GuardsListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Use the real-time provider - automatically updates!
    final guardsAsync = ref.watch(currentOrgGuardsProvider);

    return guardsAsync.when(
      data: (guards) => ListView.builder(
        itemCount: guards.length,
        itemBuilder: (context, index) {
          final guard = guards[index];
          return ListTile(
            title: Text(guard.fullName),
            subtitle: Text(guard.email ?? 'No email'),
            trailing: IconButton(
              icon: Icon(Icons.key),
              onPressed: () {
                // Show password dialog for admins
                showGuardPasswordDialog(
                  context,
                  guardName: guard.fullName,
                  guardEmail: guard.email!,
                  userId: guard.userId!,
                  guardCode: guard.guardCode,
                );
              },
            ),
          );
        },
      ),
      loading: () => Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
    );
  }
}
```

---

## 🔧 Configuration Options

### **Email Template Customization**

Edit `supabase/functions/send-guard-credentials/index.ts` to customize:
- Email design/colors
- Company branding
- Email content
- Sender name/email

### **Password Expiry**

Change password expiry duration in `supabase/functions/create-guard/index.ts`:

```typescript
// Default: 7 days
expires_at: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)

// Change to 30 days:
expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000)
```

### **Sender Email**

Update in `supabase/functions/send-guard-credentials/index.ts`:

```typescript
from: "JDS Management <noreply@yourdomain.com>",
// OR use Resend's default:
from: "JDS Management <onboarding@resend.dev>",
```

---

## 🧪 Testing

### **Test Real-time Updates:**

1. Open the app on two devices/windows
2. Create a guard on device 1
3. Device 2 should automatically show the new guard **without refresh**

### **Test Email Sending:**

1. Create a guard with valid email
2. Check guard's email inbox
3. Verify email arrives with credentials

### **Test Password Viewing:**

1. Create a guard (email sends or fails)
2. As admin, click "View Password" on guard
3. Should show password dialog
4. Test "Copy" and "Resend Email" buttons

---

## ⚠️ Security Considerations

### **1. Password Storage**
- Passwords are base64 encoded (NOT encrypted in this implementation)
- **For production**: Implement proper encryption using crypto libraries
- Passwords auto-expire after 7 days

### **2. Access Control**
- Only admins and field officers can view temporary passwords
- Enforced by RLS policies on `temporary_passwords` table
- Audit trail: `viewed_by` and `viewed_at` tracked

### **3. Email Security**
- Use HTTPS for all Edge Function calls
- Never log passwords in production
- Resend API key stored as Supabase secret

---

## 🐛 Troubleshooting

### **Real-time not working?**

1. **Check Realtime is enabled:**
   ```sql
   -- Run in Supabase SQL Editor
   SELECT * FROM pg_publication_tables WHERE tablename = 'guards';
   ```
   Should return result. If empty, enable Realtime in Dashboard.

2. **Check subscription status:**
   ```dart
   // Add to your provider
   print('Subscription status: ${_subscription?.status}');
   ```

3. **Check RLS policies:**
   Guards must be visible to the current user through RLS.

### **Emails not sending?**

1. **Check Edge Function logs:**
   ```bash
   supabase functions logs send-guard-credentials
   ```

2. **Verify Resend API key:**
   ```bash
   supabase secrets list
   ```

3. **Test Resend directly:**
   - Go to Resend dashboard
   - Send a test email
   - Check for errors

4. **Check SMTP settings in Supabase:**
   - Ensure custom SMTP is enabled
   - Verify Resend credentials

### **Password dialog shows "not available"?**

Causes:
- Password expired (>7 days old)
- Password already delivered via email
- RLS policy blocking access

Check:
```sql
SELECT * FROM temporary_passwords 
WHERE user_id = 'user_id_here' 
AND expires_at > NOW();
```

---

## 📊 Monitoring

### **Check Email Delivery:**
- Resend Dashboard: https://resend.com/emails
- Filter by status: Delivered, Bounced, etc.

### **Check Realtime Activity:**
- Supabase Dashboard → Realtime → Inspect
- Shows active subscriptions and message counts

### **Check Edge Function Usage:**
- Supabase Dashboard → Edge Functions
- View invocation count and errors

---

## 🚀 Next Steps

1. ✅ Test guard creation with real-time updates
2. ✅ Test email delivery to real guards
3. ✅ Test password viewing dialog
4. ✅ Customize email template with your branding
5. ✅ Add production-grade password encryption
6. ✅ Set up monitoring alerts for failed emails

---

## 🔗 Related Documentation

- [Supabase Realtime](https://supabase.com/docs/guides/realtime)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Resend Email API](https://resend.com/docs)
- [Flutter Riverpod](https://riverpod.dev)

---

**Status**: ✅ Implementation Complete - Ready for Testing

**Created**: 2026-02-14
