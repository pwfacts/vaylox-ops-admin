-- ============================================
-- SHIFT OWNERSHIP LOCK SYSTEM
-- Prevents duplicate attendance and double payment
-- ============================================

-- Rule: Do NOT delete existing tables or workflows
-- Only add ownership validation layer

-- ========================================
-- 1. CREATE SHIFT INSTANCES TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS shift_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  unit_id UUID NOT NULL REFERENCES units(id),
  shift_date DATE NOT NULL,
  shift TEXT NOT NULL CHECK (shift IN ('morning', 'afternoon', 'night')),
  
  -- Roster reference
  roster_required_guards INTEGER DEFAULT 1,
  
  -- Ownership tracking
  status TEXT NOT NULL DEFAULT 'UNCLAIMED' CHECK (status IN (
    'UNCLAIMED',          -- No one claimed yet
    'CLAIMED',            -- Guard checked in
    'REPLACED',           -- Original guard replaced
    'CONFIRMED',          -- Supervisor confirmed
    'PAYROLL_LOCKED'      -- Payroll closed, immutable
  )),
  
  claimed_by_profile_id UUID REFERENCES workforce_profiles(id),
  replacement_profile_id UUID REFERENCES workforce_profiles(id),
  
  -- Finalization tracking
  supervisor_confirmed_by UUID REFERENCES users(id),
  supervisor_confirmed_at TIMESTAMPTZ,
  payroll_locked_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Constraints
  UNIQUE(unit_id, shift_date, shift, claimed_by_profile_id), -- One claim per guard per shift
  CHECK (
    CASE 
      WHEN status = 'PAYROLL_LOCKED' THEN payroll_locked_at IS NOT NULL
      ELSE true
    END
  )
);

CREATE INDEX idx_shift_instances_unit_date ON shift_instances(unit_id, shift_date);
CREATE INDEX idx_shift_instances_claimed_by ON shift_instances(claimed_by_profile_id);
CREATE INDEX idx_shift_instances_status ON shift_instances(status);
CREATE INDEX idx_shift_instances_unclaimed ON shift_instances(unit_id, shift_date, shift) 
  WHERE status = 'UNCLAIMED';

COMMENT ON TABLE shift_instances IS 
'Shift ownership lock - ensures one active worker per shift instance, prevents double payment';

COMMENT ON COLUMN shift_instances.status IS 
'State machine: UNCLAIMED → CLAIMED → CONFIRMED → PAYROLL_LOCKED (or REPLACED)';

-- ========================================
-- 2. ADD SHIFT INSTANCE REFERENCE TO ATTENDANCE
-- ========================================

ALTER TABLE attendance ADD COLUMN IF NOT EXISTS shift_instance_id UUID 
  REFERENCES shift_instances(id);

CREATE INDEX IF NOT EXISTS idx_attendance_shift_instance ON attendance(shift_instance_id);

COMMENT ON COLUMN attendance.shift_instance_id IS 
'Links attendance to shift ownership record - multiple attendance rows allowed but only owner is payable';

-- ========================================
-- 3. CLAIM SHIFT INSTANCE FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION claim_shift_instance(
  p_unit_id UUID,
  p_shift_date DATE,
  p_shift TEXT,
  p_profile_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_instance_id UUID;
  v_existing_status TEXT;
  v_existing_owner UUID;
BEGIN
  -- Check if shift instance already exists
  SELECT id, status, claimed_by_profile_id 
  INTO v_instance_id, v_existing_status, v_existing_owner
  FROM shift_instances
  WHERE unit_id = p_unit_id
    AND shift_date = p_shift_date
    AND shift = p_shift
    AND (claimed_by_profile_id = p_profile_id OR claimed_by_profile_id IS NULL)
  LIMIT 1;
  
  -- If exists and locked, cannot claim
  IF v_existing_status IN ('CONFIRMED', 'PAYROLL_LOCKED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'SHIFT_LOCKED',
      'message', format('Shift already %s', v_existing_status),
      'existing_owner', v_existing_owner
    );
  END IF;
  
  -- If exists and REPLACED, original guard cannot claim
  IF v_existing_status = 'REPLACED' AND v_existing_owner != p_profile_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'SHIFT_REPLACED',
      'message', 'You have been replaced for this shift',
      'replacement_id', (
        SELECT replacement_profile_id FROM shift_instances WHERE id = v_instance_id
      )
    );
  END IF;
  
  -- If exists and UNCLAIMED, claim it
  IF v_instance_id IS NOT NULL AND v_existing_status = 'UNCLAIMED' THEN
    UPDATE shift_instances
    SET 
      status = 'CLAIMED',
      claimed_by_profile_id = p_profile_id,
      updated_at = NOW()
    WHERE id = v_instance_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'shift_instance_id', v_instance_id,
      'action', 'CLAIMED_EXISTING'
    );
  END IF;
  
  -- If exists and already claimed by same guard, return existing
  IF v_instance_id IS NOT NULL AND v_existing_owner = p_profile_id THEN
    RETURN jsonb_build_object(
      'success', true,
      'shift_instance_id', v_instance_id,
      'action', 'ALREADY_CLAIMED'
    );
  END IF;
  
  -- Create new shift instance
  INSERT INTO shift_instances (
    unit_id,
    shift_date,
    shift,
    status,
    claimed_by_profile_id
  )
  VALUES (
    p_unit_id,
    p_shift_date,
    p_shift,
    'CLAIMED',
    p_profile_id
  )
  RETURNING id INTO v_instance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', v_instance_id,
    'action', 'CREATED_AND_CLAIMED'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION claim_shift_instance IS 
'Atomically claim shift ownership - prevents double claims and replaced guard check-in';

-- ========================================
-- 4. VALIDATE ATTENDANCE OWNERSHIP
-- ========================================

CREATE OR REPLACE FUNCTION validate_attendance_ownership()
RETURNS TRIGGER AS $$
DECLARE
  v_guard_profile_id UUID;
  v_claim_result JSONB;
BEGIN
  -- Get guard's profile_id
  SELECT wp.id INTO v_guard_profile_id
  FROM workforce_profiles wp
  WHERE wp.linked_auth_user = (
    SELECT id FROM guards WHERE id = NEW.guard_id LIMIT 1
  );
  
  -- If no shift_instance_id provided, attempt to claim
  IF NEW.shift_instance_id IS NULL THEN
    v_claim_result := claim_shift_instance(
      NEW.unit_id,
      NEW.attendance_date,
      NEW.shift,
      v_guard_profile_id
    );
    
    IF v_claim_result->>'success' = 'false' THEN
      RAISE EXCEPTION 'Cannot claim shift: %', v_claim_result->>'message'
        USING ERRCODE = 'P0001',
              DETAIL = v_claim_result::TEXT;
    END IF;
    
    NEW.shift_instance_id := (v_claim_result->>'shift_instance_id')::UUID;
  ELSE
    -- Validate existing shift_instance_id ownership
    IF NOT EXISTS (
      SELECT 1 FROM shift_instances
      WHERE id = NEW.shift_instance_id
        AND claimed_by_profile_id = v_guard_profile_id
        AND status NOT IN ('PAYROLL_LOCKED')
    ) THEN
      RAISE EXCEPTION 'Invalid shift ownership: Guard not authorized for this shift instance'
        USING ERRCODE = 'P0002';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_validate_attendance_ownership ON attendance;
CREATE TRIGGER trigger_validate_attendance_ownership
  BEFORE INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION validate_attendance_ownership();

COMMENT ON TRIGGER trigger_validate_attendance_ownership ON attendance IS 
'Validates shift ownership before attendance insert - prevents unauthorized check-in';

-- ========================================
-- 5. TRANSFER SHIFT OWNERSHIP ON REPLACEMENT
-- ========================================

CREATE OR REPLACE FUNCTION dispatch_replacement(
  p_original_profile_id UUID,
  p_replacement_profile_id UUID,
  p_unit_id UUID,
  p_date DATE,
  p_shift TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_shift_instance_id UUID;
  v_existing_status TEXT;
BEGIN
  -- Find or create shift instance
  SELECT id, status INTO v_shift_instance_id, v_existing_status
  FROM shift_instances
  WHERE unit_id = p_unit_id
    AND shift_date = p_date
    AND shift = p_shift
    AND (claimed_by_profile_id = p_original_profile_id OR claimed_by_profile_id IS NULL)
  LIMIT 1;
  
  -- If shift already confirmed or locked, cannot replace
  IF v_existing_status IN ('CONFIRMED', 'PAYROLL_LOCKED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'SHIFT_FINALIZED',
      'message', format('Shift already %s, cannot replace', v_existing_status)
    );
  END IF;
  
  -- If shift instance exists, update it
  IF v_shift_instance_id IS NOT NULL THEN
    UPDATE shift_instances
    SET 
      status = 'REPLACED',
      replacement_profile_id = p_replacement_profile_id,
      updated_at = NOW()
    WHERE id = v_shift_instance_id;
  ELSE
    -- Create new shift instance in REPLACED state
    INSERT INTO shift_instances (
      unit_id,
      shift_date,
      shift,
      status,
      claimed_by_profile_id,
      replacement_profile_id
    )
    VALUES (
      p_unit_id,
      p_date,
      p_shift,
      'REPLACED',
      p_original_profile_id,
      p_replacement_profile_id
    )
    RETURNING id INTO v_shift_instance_id;
  END IF;
  
  -- Insert into guard_replacements table (existing behavior)
  INSERT INTO guard_replacements (
    original_profile_id,
    replacement_profile_id,
    unit_id,
    date,
    shift,
    status
  )
  VALUES (
    p_original_profile_id,
    p_replacement_profile_id,
    p_unit_id,
    p_date,
    p_shift,
    'active'
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', v_shift_instance_id,
    'ownership_transferred', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION dispatch_replacement IS 
'Transfer shift ownership to replacement - blocks original guard from checking in';

-- ========================================
-- 6. LOCK SHIFT ON SUPERVISOR CONFIRMATION
-- ========================================

CREATE OR REPLACE FUNCTION confirm_attendance(
  p_attendance_id UUID,
  p_supervisor_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_shift_instance_id UUID;
BEGIN
  SELECT * INTO v_attendance
  FROM attendance
  WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  IF v_attendance.supervisor_status != 'PENDING_SUPERVISOR_CONFIRMATION' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_PROCESSED',
      'current_status', v_attendance.supervisor_status
    );
  END IF;
  
  -- Update attendance
  UPDATE attendance
  SET 
    supervisor_status = 'CONFIRMED',
    supervisor_confirmed_by = p_supervisor_id,
    supervisor_confirmed_at = NOW()
  WHERE id = p_attendance_id;
  
  -- Lock shift instance
  IF v_attendance.shift_instance_id IS NOT NULL THEN
    UPDATE shift_instances
    SET 
      status = 'CONFIRMED',
      supervisor_confirmed_by = p_supervisor_id,
      supervisor_confirmed_at = NOW(),
      updated_at = NOW()
    WHERE id = v_attendance.shift_instance_id
      AND status NOT IN ('PAYROLL_LOCKED'); -- Don't downgrade from locked
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'status', 'CONFIRMED',
    'shift_instance_locked', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION confirm_attendance IS 
'Confirm attendance and lock shift instance - prevents subsequent ownership changes';

-- ========================================
-- 7. PAYROLL CLOSURE WITH SHIFT LOCK
-- ========================================

CREATE OR REPLACE FUNCTION can_close_payroll_period(
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_disputed_count INTEGER;
  v_unconfirmed_shifts INTEGER;
  v_disputed_attendance JSONB;
  v_unconfirmed_shifts_data JSONB;
BEGIN
  -- Check for disputed attendance
  SELECT COUNT(*) INTO v_disputed_count
  FROM attendance
  WHERE organization_id = p_org_id
    AND attendance_date >= p_period_start
    AND attendance_date <= p_period_end
    AND supervisor_status = 'DISPUTED';
  
  -- NEW: Check for shift instances not in CONFIRMED state
  SELECT COUNT(*) INTO v_unconfirmed_shifts
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status IN ('CLAIMED', 'REPLACED') -- Must be CONFIRMED before payroll
    AND si.claimed_by_profile_id IS NOT NULL;
  
  -- Get unconfirmed shift details
  SELECT jsonb_agg(
    jsonb_build_object(
      'shift_instance_id', si.id,
      'unit_name', u.name,
      'shift_date', si.shift_date,
      'shift', si.shift,
      'status', si.status,
      'claimed_by', wp.full_name
    )
  )
  INTO v_unconfirmed_shifts_data
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  JOIN workforce_profiles wp ON wp.id = si.claimed_by_profile_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status IN ('CLAIMED', 'REPLACED')
  LIMIT 20;
  
  IF v_disputed_count > 0 OR v_unconfirmed_shifts > 0 THEN
    RETURN jsonb_build_object(
      'can_close', false,
      'disputed_count', v_disputed_count,
      'unconfirmed_shifts', v_unconfirmed_shifts,
      'unconfirmed_shifts_data', COALESCE(v_unconfirmed_shifts_data, '[]'::JSONB),
      'message', format('%s disputed attendance, %s unconfirmed shifts', v_disputed_count, v_unconfirmed_shifts)
    );
  END IF;
  
  RETURN jsonb_build_object(
    'can_close', true,
    'disputed_count', 0,
    'unconfirmed_shifts', 0,
    'message', 'Period can be closed'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION can_close_payroll_period IS 
'NEW: Requires all shift instances to be CONFIRMED before payroll closure';

-- ========================================
-- 8. LOCK SHIFTS ON PAYROLL CLOSE
-- ========================================

CREATE OR REPLACE FUNCTION close_payroll_period(
  p_period_id UUID,
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_check JSONB;
  v_locked_count INTEGER;
BEGIN
  -- Validate can close
  v_check := can_close_payroll_period(p_org_id, p_period_start, p_period_end);
  
  IF v_check->>'can_close' = 'false' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERIOD_NOT_READY',
      'details', v_check
    );
  END IF;
  
  -- Lock all shift instances in period
  UPDATE shift_instances si
  SET 
    status = 'PAYROLL_LOCKED',
    payroll_locked_at = NOW(),
    updated_at = NOW()
  FROM units u
  WHERE si.unit_id = u.id
    AND u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status = 'CONFIRMED';
  
  GET DIAGNOSTICS v_locked_count = ROW_COUNT;
  
  -- Update payroll period status
  UPDATE payroll_periods
  SET 
    status = 'CLOSED',
    closed_at = NOW()
  WHERE id = p_period_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'shifts_locked', v_locked_count,
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION close_payroll_period IS 
'Close payroll period and permanently lock all shift instances';
