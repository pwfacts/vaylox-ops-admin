-- ============================================
-- ATTENDANCE OPERATIONAL CAPTURE
-- Convert blocking validation to deferred resolution
-- ============================================

-- Rule: NEVER block supervisor from marking attendance
-- Instead: Capture with exception, require admin resolution later

-- ========================================
-- 1. ATTENDANCE STATUS COLUMN
-- ========================================

-- Add validation status to attendance
ALTER TABLE attendance 
  ADD COLUMN IF NOT EXISTS validation_status TEXT DEFAULT 'VALID_FOR_PAYROLL' 
    CHECK (validation_status IN ('VALID_FOR_PAYROLL', 'OPERATIONAL_ONLY', 'RESOLVED'));

CREATE INDEX idx_attendance_validation_status ON attendance(validation_status);

COMMENT ON COLUMN attendance.validation_status IS 
'VALID_FOR_PAYROLL: Normal attendance, included in payroll
OPERATIONAL_ONLY: Has validation issues, excluded from payroll until admin resolves
RESOLVED: Was exceptional, now resolved and valid';

-- ========================================
-- 2. ATTENDANCE EXCEPTIONS TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS attendance_exceptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Links
  attendance_id UUID NOT NULL REFERENCES attendance(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  shift_instance_id UUID REFERENCES shift_instances(id),
  
  -- Exception details
  exception_type TEXT NOT NULL CHECK (exception_type IN (
    'PAYROLL_PERIOD_NOT_AVAILABLE',
    'PERIOD_FINALIZED',
    'OWNERSHIP_INVALID',
    'REPLACED_SHIFT',
    'DUPLICATE_ATTENDANCE',
    'OTHER'
  )),
  
  exception_message TEXT NOT NULL,
  exception_details JSONB,
  
  -- Context
  attendance_date DATE NOT NULL,
  shift_start_date DATE,
  attempted_period_id UUID REFERENCES payroll_periods(id),
  
  -- Resolution
  resolution_status TEXT DEFAULT 'PENDING' CHECK (resolution_status IN (
    'PENDING',      -- Awaiting admin review
    'RESOLVED',     -- Admin approved, converted to valid
    'REJECTED',     -- Admin rejected, attendance invalid
    'DUPLICATED'    -- Admin found duplicate, merged
  )),
  
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES users(id),
  resolution_note TEXT,
  
  -- Admin override
  override_applied BOOLEAN DEFAULT false,
  override_reason TEXT,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  supervisor_notified BOOLEAN DEFAULT false,
  admin_notified BOOLEAN DEFAULT false
);

CREATE INDEX idx_attendance_exceptions_attendance ON attendance_exceptions(attendance_id);
CREATE INDEX idx_attendance_exceptions_guard ON attendance_exceptions(guard_id);
CREATE INDEX idx_attendance_exceptions_org ON attendance_exceptions(organization_id);
CREATE INDEX idx_attendance_exceptions_status ON attendance_exceptions(resolution_status);
CREATE INDEX idx_attendance_exceptions_type ON attendance_exceptions(exception_type);
CREATE INDEX idx_attendance_exceptions_date ON attendance_exceptions(attendance_date);

COMMENT ON TABLE attendance_exceptions IS 
'Captures validation failures without blocking supervisor operations - requires admin resolution';

-- ========================================
-- 3. OPERATIONAL CAPTURE TRIGGER
-- ========================================

-- REPLACE blocking trigger with capture trigger
DROP TRIGGER IF EXISTS trg_assign_attendance_period_strict ON attendance;
DROP FUNCTION IF EXISTS assign_attendance_to_period_strict();

CREATE OR REPLACE FUNCTION assign_attendance_with_capture()
RETURNS TRIGGER AS $$
DECLARE
  v_period_id UUID;
  v_period_status TEXT;
  v_lookup_date DATE;
  v_exception_type TEXT;
  v_exception_message TEXT;
  v_exception_details JSONB;
BEGIN
  -- Use shift_start_date if available, fallback to attendance_date
  v_lookup_date := COALESCE(NEW.shift_start_date, NEW.attendance_date);
  
  -- Default to valid
  NEW.validation_status := 'VALID_FOR_PAYROLL';
  
  -- ========================================
  -- VALIDATION 1: PAYROLL PERIOD EXISTS
  -- ========================================
  
  SELECT id, status INTO v_period_id, v_period_status
  FROM payroll_periods
  WHERE organization_id = NEW.organization_id
    AND v_lookup_date BETWEEN from_date AND to_date
  LIMIT 1;
  
  IF v_period_id IS NULL THEN
    -- Exception: No period exists
    NEW.validation_status := 'OPERATIONAL_ONLY';
    NEW.payroll_period_id := NULL;
    
    v_exception_type := 'PAYROLL_PERIOD_NOT_AVAILABLE';
    v_exception_message := format('No payroll period exists for date %s', v_lookup_date);
    v_exception_details := jsonb_build_object(
      'lookup_date', v_lookup_date,
      'attendance_date', NEW.attendance_date,
      'shift_start_date', NEW.shift_start_date
    );
    
    -- Create exception record (after INSERT)
    -- Will be handled by AFTER INSERT trigger
    
    RETURN NEW;
  END IF;
  
  -- ========================================
  -- VALIDATION 2: PERIOD IS OPEN
  -- ========================================
  
  IF v_period_status != 'OPEN' THEN
    -- Exception: Period finalized
    NEW.validation_status := 'OPERATIONAL_ONLY';
    NEW.payroll_period_id := v_period_id;
    
    v_exception_type := 'PERIOD_FINALIZED';
    v_exception_message := format('Period is %s (not OPEN) for date %s', v_period_status, v_lookup_date);
    v_exception_details := jsonb_build_object(
      'period_id', v_period_id,
      'period_status', v_period_status,
      'lookup_date', v_lookup_date
    );
    
    RETURN NEW;
  END IF;
  
  -- ========================================
  -- VALIDATION PASSED
  -- ========================================
  
  NEW.payroll_period_id := v_period_id;
  NEW.validation_status := 'VALID_FOR_PAYROLL';
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assign_attendance_with_capture
  BEFORE INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION assign_attendance_with_capture();

COMMENT ON FUNCTION assign_attendance_with_capture IS 
'OPERATIONAL CAPTURE: Accepts attendance with exceptions instead of blocking';

-- ========================================
-- 4. EXCEPTION RECORD CREATION
-- ========================================

CREATE OR REPLACE FUNCTION create_attendance_exception()
RETURNS TRIGGER AS $$
DECLARE
  v_exception_type TEXT;
  v_exception_message TEXT;
  v_exception_details JSONB;
  v_period_id UUID;
  v_period_status TEXT;
  v_lookup_date DATE;
BEGIN
  -- Only process OPERATIONAL_ONLY status
  IF NEW.validation_status != 'OPERATIONAL_ONLY' THEN
    RETURN NEW;
  END IF;
  
  -- Determine exception type
  v_lookup_date := COALESCE(NEW.shift_start_date, NEW.attendance_date);
  
  SELECT id, status INTO v_period_id, v_period_status
  FROM payroll_periods
  WHERE organization_id = NEW.organization_id
    AND v_lookup_date BETWEEN from_date AND to_date
  LIMIT 1;
  
  IF v_period_id IS NULL THEN
    v_exception_type := 'PAYROLL_PERIOD_NOT_AVAILABLE';
    v_exception_message := format('No payroll period exists for %s', v_lookup_date);
  ELSIF v_period_status != 'OPEN' THEN
    v_exception_type := 'PERIOD_FINALIZED';
    v_exception_message := format('Period status is %s for %s', v_period_status, v_lookup_date);
  ELSE
    v_exception_type := 'OTHER';
    v_exception_message := 'Validation failed';
  END IF;
  
  v_exception_details := jsonb_build_object(
    'attendance_date', NEW.attendance_date,
    'shift_start_date', NEW.shift_start_date,
    'period_id', v_period_id,
    'period_status', v_period_status,
    'lookup_date', v_lookup_date
  );
  
  -- Create exception
  INSERT INTO attendance_exceptions (
    attendance_id,
    organization_id,
    guard_id,
    shift_instance_id,
    exception_type,
    exception_message,
    exception_details,
    attendance_date,
    shift_start_date,
    attempted_period_id,
    resolution_status
  )
  VALUES (
    NEW.id,
    NEW.organization_id,
    NEW.guard_id,
    NEW.shift_instance_id,
    v_exception_type,
    v_exception_message,
    v_exception_details,
    NEW.attendance_date,
    NEW.shift_start_date,
    v_period_id,
    'PENDING'
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_create_attendance_exception
  AFTER INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION create_attendance_exception();

COMMENT ON FUNCTION create_attendance_exception IS 
'Creates exception record when attendance is marked OPERATIONAL_ONLY';

-- ========================================
-- 5. ADMIN RESOLUTION FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION resolve_attendance_exception(
  p_exception_id UUID,
  p_admin_user_id UUID,
  p_resolution_action TEXT,  -- 'APPROVE', 'REJECT', 'OVERRIDE'
  p_resolution_note TEXT,
  p_override_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_exception attendance_exceptions;
  v_attendance attendance;
  v_admin_role TEXT;
BEGIN
  -- Get exception
  SELECT * INTO v_exception FROM attendance_exceptions WHERE id = p_exception_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EXCEPTION_NOT_FOUND');
  END IF;
  
  IF v_exception.resolution_status != 'PENDING' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_RESOLVED',
      'current_status', v_exception.resolution_status
    );
  END IF;
  
  -- Verify admin role
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_user_id;
  
  IF v_admin_role NOT IN ('ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERMISSION_DENIED');
  END IF;
  
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = v_exception.attendance_id;
  
  -- ========================================
  -- RESOLUTION ACTIONS
  -- ========================================
  
  IF p_resolution_action = 'APPROVE' THEN
    -- Admin approves - convert to valid for payroll
    UPDATE attendance
    SET 
      validation_status = 'RESOLVED',
      updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'RESOLVED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'action', 'APPROVED',
      'attendance_id', v_exception.attendance_id,
      'new_status', 'RESOLVED'
    );
    
  ELSIF p_resolution_action = 'REJECT' THEN
    -- Admin rejects - mark as invalid
    UPDATE attendance
    SET 
      validation_status = 'OPERATIONAL_ONLY',
      updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'REJECTED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'action', 'REJECTED',
      'attendance_id', v_exception.attendance_id,
      'message', 'Attendance marked invalid - excluded from payroll'
    );
    
  ELSIF p_resolution_action = 'OVERRIDE' THEN
    -- Admin override - convert to valid with override flag
    IF p_override_reason IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'OVERRIDE_REASON_REQUIRED');
    END IF;
    
    UPDATE attendance
    SET 
      validation_status = 'RESOLVED',
      updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'RESOLVED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note,
      override_applied = true,
      override_reason = p_override_reason
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'action', 'OVERRIDE_APPROVED',
      'attendance_id', v_exception.attendance_id,
      'new_status', 'RESOLVED',
      'override_applied', true
    );
    
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ACTION');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_attendance_exception IS 
'ADMIN ONLY: Resolves attendance exception - APPROVE, REJECT, or OVERRIDE';

-- ========================================
-- 6. PAYROLL EXCLUSION FILTER
-- ========================================

-- Update work unit aggregation to exclude OPERATIONAL_ONLY
CREATE OR REPLACE FUNCTION aggregate_work_units_by_period_safe(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_present_count DECIMAL;
  v_auto_present_count DECIMAL;
  v_replacement_count DECIMAL;
  v_ot_count DECIMAL;
  v_shift_ids UUID[];
  v_units_created INTEGER := 0;
  v_excluded_count INTEGER := 0;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Must be finalized
  IF v_period.status NOT IN ('ATTENDANCE_FINALIZED', 'GENERATED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ATTENDANCE_NOT_FINALIZED'
    );
  END IF;
  
  -- Count excluded attendance (for reporting)
  SELECT COUNT(*) INTO v_excluded_count
  FROM attendance
  WHERE payroll_period_id = p_period_id
    AND validation_status = 'OPERATIONAL_ONLY';
  
  -- Loop through each guard
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')  -- EXCLUDE OPERATIONAL_ONLY
      AND EXISTS (
        SELECT 1 FROM shift_instances si
        WHERE si.id = a.shift_instance_id
          AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      )
  LOOP
    -- Count present days (CONFIRMED only, VALID attendance only)
    SELECT COUNT(DISTINCT si.shift_date) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')  -- EXCLUDE OPERATIONAL_ONLY
      AND si.status = 'CONFIRMED'
      AND si.auto_confirm_reason IS NULL;
    
    -- Count auto-present days
    SELECT COUNT(DISTINCT si.shift_date) INTO v_auto_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')  -- EXCLUDE OPERATIONAL_ONLY
      AND si.status = 'AUTO_CONFIRMED';
    
    -- Replacement days
    SELECT COUNT(DISTINCT si.shift_date) INTO v_replacement_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN guard_replacements gr ON gr.replacement_profile_id = (
      SELECT id FROM workforce_profiles WHERE linked_auth_user = (
        SELECT id FROM guards WHERE id = v_guard_id LIMIT 1
      )
    )
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')  -- EXCLUDE OPERATIONAL_ONLY
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- OT days (future)
    v_ot_count := 0;
    
    -- Collect shift IDs
    SELECT array_agg(DISTINCT si.id) INTO v_shift_ids
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')  -- EXCLUDE OPERATIONAL_ONLY
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- Insert work unit
    INSERT INTO payroll_work_units (
      payroll_period_id,
      guard_id,
      organization_id,
      present_days,
      auto_present_days,
      replacement_days,
      ot_days,
      included_shift_instances,
      aggregation_status
    )
    VALUES (
      p_period_id,
      v_guard_id,
      v_period.organization_id,
      COALESCE(v_present_count, 0),
      COALESCE(v_auto_present_count, 0),
      COALESCE(v_replacement_count, 0),
      COALESCE(v_ot_count, 0),
      v_shift_ids,
      'DRAFT'
    )
    ON CONFLICT (payroll_period_id, guard_id)
    DO UPDATE SET
      present_days = EXCLUDED.present_days,
      auto_present_days = EXCLUDED.auto_present_days,
      replacement_days = EXCLUDED.replacement_days,
      ot_days = EXCLUDED.ot_days,
      included_shift_instances = EXCLUDED.included_shift_instances,
      aggregated_at = NOW(),
      updated_at = NOW();
    
    v_units_created := v_units_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'work_units_created', v_units_created,
    'excluded_attendance_count', v_excluded_count,
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_by_period_safe IS 
'SAFE AGGREGATION: Excludes OPERATIONAL_ONLY attendance from payroll calculations';

-- ========================================
-- 7. EXCEPTION DASHBOARD VIEW
-- ========================================

CREATE OR REPLACE VIEW attendance_exceptions_dashboard AS
SELECT 
  ae.id AS exception_id,
  ae.exception_type,
  ae.exception_message,
  ae.resolution_status,
  ae.attendance_date,
  ae.created_at AS exception_created_at,
  
  -- Guard info
  g.full_name AS guard_name,
  g.id AS guard_id,
  
  -- Organization
  o.name AS organization_name,
  o.id AS organization_id,
  
  -- Period info
  pp.from_date AS period_from,
  pp.to_date AS period_to,
  pp.status AS period_status,
  
  -- Attendance info
  a.id AS attendance_id,
  a.validation_status,
  a.attendance_date AS actual_attendance_date,
  
  -- Resolution
  ae.resolved_at,
  u.email AS resolved_by_email,
  ae.resolution_note
FROM attendance_exceptions ae
JOIN attendance a ON a.id = ae.attendance_id
JOIN guards g ON g.id = ae.guard_id
JOIN organizations o ON o.id = ae.organization_id
LEFT JOIN payroll_periods pp ON pp.id = ae.attempted_period_id
LEFT JOIN users u ON u.id = ae.resolved_by
ORDER BY ae.created_at DESC;

COMMENT ON VIEW attendance_exceptions_dashboard IS 
'Admin dashboard for reviewing and resolving attendance exceptions';
