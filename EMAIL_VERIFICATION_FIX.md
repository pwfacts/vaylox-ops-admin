# Supabase Email Verification Fix

## Problem: Not receiving verification emails after signup

### Quick Solutions:

### 1. **Use the Skip Login Button** (Immediate Fix)
   - Click "🚀 Skip Login (Demo Mode)" on the login page
   - This bypasses authentication entirely for development

### 2. **Try the Test Credentials** (If they exist)
   - Email: admin@vaylox.com
   - Password: admin123

### 3. **Disable Email Confirmation in Supabase** (Permanent Fix)
   1. Go to your Supabase Dashboard: https://supabase.com/dashboard
   2. Select your project: `fcpbexqyyzdvbiwplmjt`
   3. Go to **Authentication** > **Settings**
   4. Find **"Enable email confirmations"**
   5. **Turn it OFF** for development
   6. Save changes

### 4. **Alternative: Use Direct Database Insert**
   Run this SQL in your Supabase SQL Editor:
   ```sql
   -- Insert a test admin user directly
   INSERT INTO auth.users (
     id,
     instance_id,
     email,
     encrypted_password,
     email_confirmed_at,
     created_at,
     updated_at,
     confirmed_at,
     role
   ) VALUES (
     gen_random_uuid(),
     '00000000-0000-0000-0000-000000000000',
     'admin@test.com',
     crypt('admin123', gen_salt('bf')),
     now(),
     now(),
     now(),
     now(),
     'authenticated'
   );
   ```

### 5. **Check Email Settings**
   1. Go to **Authentication** > **Settings** > **SMTP Settings**
   2. If no SMTP is configured, emails won't be sent
   3. You can use the default Supabase SMTP or configure your own

### Current Status:
- ✅ Flutter app is running at http://localhost:8080
- ✅ Supabase connection is configured  
- ❌ Email confirmation is likely enabled and blocking signups
- ✅ Skip login button is available as workaround

### Recommended Action:
**Use option #3 above** - disable email confirmations in your Supabase dashboard for the fastest solution.