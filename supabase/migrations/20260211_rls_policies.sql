-- Enable RLS on ALL tables
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE areas ENABLE ROW LEVEL SECURITY;
ALTER TABLE units ENABLE ROW LEVEL SECURITY;
ALTER TABLE guards ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_slips ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE field_officer_units ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE salary_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE correction_requests ENABLE ROW LEVEL SECURITY;

-- Set company context function
CREATE OR REPLACE FUNCTION set_company_context(cid UUID)
RETURNS void AS $$
BEGIN
  PERFORM set_config('app.company_id', cid::text, false);
END;
$$ LANGUAGE plpgsql;

-- Get user role function
CREATE OR REPLACE FUNCTION get_user_role(uid UUID)
RETURNS TEXT AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role INTO user_role FROM users WHERE id = uid;
  RETURN user_role;
END;
$$ LANGUAGE plpgsql;

-- Helper function to get current user role
CREATE OR REPLACE FUNCTION get_current_user_role()
RETURNS TEXT AS $$
DECLARE
  user_role TEXT;
BEGIN
  SELECT role INTO user_role FROM users WHERE id = auth.uid();
  RETURN COALESCE(user_role, 'guest');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Guards table policies (role-aware composition)
CREATE POLICY guards_access ON guards
  FOR ALL USING (
    company_id = current_setting('app.company_id', true)::UUID
    AND (
      get_current_user_role() IN ('admin', 'accountant')
      OR (
        get_current_user_role() = 'field_officer'
        AND EXISTS (
          SELECT 1 FROM field_officer_units fou
          WHERE fou.user_id = auth.uid()
          AND fou.unit_id = guards.assigned_unit_id
        )
      )
      OR (
        get_current_user_role() = 'supervisor'
        AND EXISTS (
          SELECT 1 FROM units u
          WHERE u.id = guards.assigned_unit_id
          AND u.supervisor_id = auth.uid()
        )
      )
    )
  );

-- Attendance table policies (role-aware composition)
CREATE POLICY attendance_access ON attendance
  FOR ALL USING (
    company_id = current_setting('app.company_id', true)::UUID
    AND (
      get_current_user_role() IN ('admin', 'accountant')
      OR (
        get_current_user_role() = 'field_officer'
        AND EXISTS (
          SELECT 1 FROM field_officer_units fou
          WHERE fou.user_id = auth.uid()
          AND fou.unit_id = attendance.unit_id
        )
      )
      OR (
        get_current_user_role() = 'supervisor'
        AND EXISTS (
          SELECT 1 FROM units u
          WHERE u.id = attendance.unit_id
          AND u.supervisor_id = auth.uid()
        )
      )
    )
  );

-- Salary slips policies
CREATE POLICY salary_company_isolation ON salary_slips
  FOR ALL USING (company_id = current_setting('app.company_id', true)::UUID);

-- Audit logs (read-only for everyone, insert-only via triggers)
CREATE POLICY audit_read_only ON attendance_audit_log
  FOR SELECT USING (true);

CREATE POLICY audit_insert_only ON attendance_audit_log
  FOR INSERT WITH CHECK (true);

-- Similar for salary_audit_log
CREATE POLICY salary_audit_read_only ON salary_audit_log
  FOR SELECT USING (true);

CREATE POLICY salary_audit_insert_only ON salary_audit_log
  FOR INSERT WITH CHECK (true);
