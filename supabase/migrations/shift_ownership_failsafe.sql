-- ============================================
-- SHIFT OWNERSHIP FAILSAFE RESOLUTION
-- Prevents operational deadlocks while maintaining payment correctness
-- ============================================

-- Rule: Do NOT remove ownership lock
-- Rule: Do NOT allow double payment
-- Only add failsafe mechanisms

-- ========================================
-- 1. SCHEMA CHANGES
-- ========================================

-- Update shift_instances status enum
ALTER TABLE shift_instances DROP CONSTRAINT IF EXISTS shift_instances_status_check;
ALTER TABLE shift_instances ADD CONSTRAINT shift_instances_status_check 
  CHECK (status IN (
    'UNCLAIMED',
    'CLAIMED',
    'REPLACED',
    'CONFIRMED',
    'AUTO_CONFIRMED',  -- NEW: Auto-confirmed after 24h
    'PAYROLL_LOCKED'
  ));

-- Add auto-confirmation tracking
ALTER TABLE shift_instances ADD COLUMN IF NOT EXISTS auto_confirm_reason TEXT;
ALTER TABLE shift_instances ADD COLUMN IF NOT EXISTS accountable_role TEXT;

COMMENT ON COLUMN shift_instances.auto_confirm_reason IS 
'Reason for auto-confirmation: "Supervisor inactive", "System timeout", etc.';

COMMENT ON COLUMN shift_instances.accountable_role IS 
'Who is accountable for non-confirmation: SUPERVISOR, ADMIN, SYSTEM';

-- ========================================
-- 2. LATE ARRIVAL DISPUTES TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS late_arrival_disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Attempted punch details
  guard_id UUID NOT NULL REFERENCES guards(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  shift_date DATE NOT NULL,
  shift TEXT NOT NULL,
  
  -- Rejection context
  attempted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  rejection_reason TEXT NOT NULL,
  shift_instance_id UUID REFERENCES shift_instances(id),
  shift_instance_status TEXT, -- Status at rejection time
  
  -- Metadata
  device_timestamp TIMESTAMPTZ,
  device_fingerprint TEXT,
  last_known_location JSONB,
  
  -- Resolution
  resolution_status TEXT DEFAULT 'PENDING' CHECK (resolution_status IN (
    'PENDING',          -- Awaiting supervisor review
    'APPROVED',         -- Supervisor approved late arrival
    'REJECTED',         -- Supervisor rejected claim
    'TIMEOUT'           -- No action taken
  )),
  resolved_by UUID REFERENCES users(id),
  resolved_at TIMESTAMPTZ,
  resolution_note TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_late_arrival_disputes_guard ON late_arrival_disputes(guard_id);
CREATE INDEX idx_late_arrival_disputes_unit_date ON late_arrival_disputes(unit_id, shift_date);
CREATE INDEX idx_late_arrival_disputes_status ON late_arrival_disputes(resolution_status);
CREATE INDEX idx_late_arrival_disputes_pending ON late_arrival_disputes(unit_id, shift_date, resolution_status) 
  WHERE resolution_status = 'PENDING';

COMMENT ON TABLE late_arrival_disputes IS 
'Stores rejected attendance attempts - prevents wage dispute evidence loss';

-- ========================================
-- 3. MODIFIED ATTENDANCE VALIDATION TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION validate_attendance_ownership()
RETURNS TRIGGER AS $$
DECLARE
  v_guard_profile_id UUID;
  v_claim_result JSONB;
  v_shift_instance shift_instances;
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
      -- NEW: Log rejection to late_arrival_disputes
      INSERT INTO late_arrival_disputes (
        guard_id,
        unit_id,
        shift_date,
        shift,
        attempted_at,
        rejection_reason,
        shift_instance_id,
        shift_instance_status,
        device_timestamp,
        last_known_location
      )
      VALUES (
        NEW.guard_id,
        NEW.unit_id,
        NEW.attendance_date,
        NEW.shift,
        NOW(),
        v_claim_result->>'error' || ': ' || v_claim_result->>'message',
        (v_claim_result->>'shift_instance_id')::UUID,
        (
          SELECT status FROM shift_instances 
          WHERE id = (v_claim_result->>'shift_instance_id')::UUID
        ),
        NEW.device_timestamp,
        NEW.last_known_location
      );
      
      RAISE EXCEPTION 'Cannot claim shift: % (logged to late_arrival_disputes)', v_claim_result->>'message'
        USING ERRCODE = 'P0001',
              DETAIL = v_claim_result::TEXT;
    END IF;
    
    NEW.shift_instance_id := (v_claim_result->>'shift_instance_id')::UUID;
  ELSE
    -- Validate existing shift_instance_id ownership
    SELECT * INTO v_shift_instance
    FROM shift_instances
    WHERE id = NEW.shift_instance_id;
    
    IF NOT FOUND OR v_shift_instance.claimed_by_profile_id != v_guard_profile_id THEN
      -- Log rejection
      INSERT INTO late_arrival_disputes (
        guard_id,
        unit_id,
        shift_date,
        shift,
        attempted_at,
        rejection_reason,
        shift_instance_id,
        shift_instance_status
      )
      VALUES (
        NEW.guard_id,
        NEW.unit_id,
        NEW.attendance_date,
        NEW.shift,
        NOW(),
        'Invalid shift ownership: Guard not authorized',
        NEW.shift_instance_id,
        v_shift_instance.status
      );
      
      RAISE EXCEPTION 'Invalid shift ownership: Guard not authorized for this shift instance (logged to late_arrival_disputes)'
        USING ERRCODE = 'P0002';
    END IF;
    
    IF v_shift_instance.status = 'PAYROLL_LOCKED' THEN
      RAISE EXCEPTION 'Shift already payroll locked - cannot modify'
        USING ERRCODE = 'P0003';
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION validate_attendance_ownership IS 
'Validates ownership and logs rejections to late_arrival_disputes';

-- ========================================
-- 4. AUTO-CONFIRMATION WORKER
-- ========================================

CREATE OR REPLACE FUNCTION auto_confirm_stale_shifts()
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_auto_confirmed_count INTEGER := 0;
BEGIN
  -- Find shifts CLAIMED for >24 hours without confirmation
  FOR v_shift IN
    SELECT * FROM shift_instances
    WHERE status = 'CLAIMED'
      AND created_at < NOW() - INTERVAL '24 hours'
      AND supervisor_confirmed_at IS NULL
  LOOP
    -- Auto-confirm shift
    UPDATE shift_instances
    SET 
      status = 'AUTO_CONFIRMED',
      auto_confirm_reason = 'Supervisor inactive - auto-confirmed after 24 hours',
      accountable_role = 'SUPERVISOR',
      updated_at = NOW()
    WHERE id = v_shift.id;
    
    v_auto_confirmed_count := v_auto_confirmed_count + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'auto_confirmed_count', v_auto_confirmed_count,
    'processed_at', NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_confirm_stale_shifts IS 
'Auto-confirm shifts CLAIMED for >24h - prevents operational deadlock from supervisor inactivity';

-- ========================================
-- 5. UPDATED PAYROLL CLOSURE
-- ========================================

CREATE OR REPLACE FUNCTION can_close_payroll_period(
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_disputed_count INTEGER;
  v_blocking_shifts INTEGER;
  v_auto_confirmed_count INTEGER;
  v_blocking_shifts_data JSONB;
BEGIN
  -- Check for disputed attendance
  SELECT COUNT(*) INTO v_disputed_count
  FROM attendance
  WHERE organization_id = p_org_id
    AND attendance_date >= p_period_start
    AND attendance_date <= p_period_end
    AND supervisor_status = 'DISPUTED';
  
  -- NEW: Only CLAIMED and REPLACED block (not AUTO_CONFIRMED)
  SELECT COUNT(*) INTO v_blocking_shifts
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status IN ('CLAIMED', 'REPLACED') -- AUTO_CONFIRMED allowed
    AND si.claimed_by_profile_id IS NOT NULL;
  
  -- Count auto-confirmed shifts (informational)
  SELECT COUNT(*) INTO v_auto_confirmed_count
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status = 'AUTO_CONFIRMED';
  
  -- Get blocking shift details
  SELECT jsonb_agg(
    jsonb_build_object(
      'shift_instance_id', si.id,
      'unit_name', u.name,
      'shift_date', si.shift_date,
      'shift', si.shift,
      'status', si.status,
      'claimed_by', wp.full_name,
      'hours_pending', EXTRACT(HOUR FROM (NOW() - si.created_at))::INTEGER
    )
  )
  INTO v_blocking_shifts_data
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  JOIN workforce_profiles wp ON wp.id = si.claimed_by_profile_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status IN ('CLAIMED', 'REPLACED')
  LIMIT 20;
  
  IF v_disputed_count > 0 OR v_blocking_shifts > 0 THEN
    RETURN jsonb_build_object(
      'can_close', false,
      'disputed_count', v_disputed_count,
      'blocking_shifts', v_blocking_shifts,
      'auto_confirmed_count', v_auto_confirmed_count,
      'blocking_shifts_data', COALESCE(v_blocking_shifts_data, '[]'::JSONB),
      'message', format('%s disputed attendance, %s unconfirmed shifts (AUTO_CONFIRMED allowed)', 
        v_disputed_count, v_blocking_shifts)
    );
  END IF;
  
  RETURN jsonb_build_object(
    'can_close', true,
    'disputed_count', 0,
    'blocking_shifts', 0,
    'auto_confirmed_count', v_auto_confirmed_count,
    'message', format('Period can be closed (%s shifts auto-confirmed)', v_auto_confirmed_count)
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION can_close_payroll_period IS 
'NEW: Allows AUTO_CONFIRMED shifts - only DISPUTED and unconfirmed CLAIMED/REPLACED block';

-- ========================================
-- 6. UPDATED PAYROLL CLOSE FUNCTION
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
  v_auto_confirmed_count INTEGER;
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
  
  -- Lock CONFIRMED and AUTO_CONFIRMED shift instances
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
    AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED'); -- NEW: Include auto-confirmed
  
  GET DIAGNOSTICS v_locked_count = ROW_COUNT;
  
  -- Count auto-confirmed
  SELECT COUNT(*) INTO v_auto_confirmed_count
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  WHERE u.organization_id = p_org_id
    AND si.shift_date >= p_period_start
    AND si.shift_date <= p_period_end
    AND si.status = 'PAYROLL_LOCKED'
    AND si.auto_confirm_reason IS NOT NULL;
  
  -- Update payroll period status
  UPDATE payroll_periods
  SET 
    status = 'CLOSED',
    closed_at = NOW()
  WHERE id = p_period_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'shifts_locked', v_locked_count,
    'auto_confirmed_shifts', v_auto_confirmed_count,
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION close_payroll_period IS 
'Close payroll and lock CONFIRMED + AUTO_CONFIRMED shifts';

-- ========================================
-- 7. DISPUTE RESOLUTION HELPER
-- ========================================

CREATE OR REPLACE FUNCTION resolve_late_arrival_dispute(
  p_dispute_id UUID,
  p_action TEXT, -- 'APPROVED', 'REJECTED'
  p_resolver_id UUID,
  p_note TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_dispute late_arrival_disputes;
  v_attendance_id UUID;
BEGIN
  -- Get dispute
  SELECT * INTO v_dispute
  FROM late_arrival_disputes
  WHERE id = p_dispute_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'DISPUTE_NOT_FOUND');
  END IF;
  
  IF v_dispute.resolution_status != 'PENDING' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_RESOLVED',
      'current_status', v_dispute.resolution_status
    );
  END IF;
  
  -- Update dispute status
  UPDATE late_arrival_disputes
  SET 
    resolution_status = p_action,
    resolved_by = p_resolver_id,
    resolved_at = NOW(),
    resolution_note = p_note
  WHERE id = p_dispute_id;
  
  -- If approved, create manual attendance
  IF p_action = 'APPROVED' THEN
    INSERT INTO attendance (
      guard_id,
      unit_id,
      attendance_date,
      shift,
      check_in_time,
      verification_mode,
      supervisor_status,
      supervisor_confirmed_by
    )
    VALUES (
      v_dispute.guard_id,
      v_dispute.unit_id,
      v_dispute.shift_date,
      v_dispute.shift,
      v_dispute.attempted_at,
      'MANUAL_OVERRIDE',
      'CONFIRMED',
      p_resolver_id
    )
    RETURNING id INTO v_attendance_id;
    
    RETURN jsonb_build_object(
      'success', true,
      'action', p_action,
      'attendance_created', v_attendance_id
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'action', p_action
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_late_arrival_dispute IS 
'Resolve late arrival dispute - if approved, creates manual attendance';
