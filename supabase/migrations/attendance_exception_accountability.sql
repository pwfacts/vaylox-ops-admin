-- ============================================
-- ATTENDANCE EXCEPTION ACCOUNTABILITY
-- Escalation and deadline enforcement (non-blocking)
-- ============================================

-- Rule: Enforce accountability, NOT block salary
-- Unresolved exceptions included in payroll but FLAGGED

-- ========================================
-- 1. ADD ACCOUNTABILITY COLUMNS
-- ========================================

ALTER TABLE attendance_exceptions
  ADD COLUMN IF NOT EXISTS assigned_to_user_id UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS escalation_level TEXT DEFAULT 'SUPERVISOR' 
    CHECK (escalation_level IN ('SUPERVISOR', 'FIELD_OFFICER', 'ADMIN', 'PAYROLL_RISK')),
  ADD COLUMN IF NOT EXISTS due_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS escalated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS risk_flag BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_escalation_at TIMESTAMPTZ;

CREATE INDEX idx_attendance_exceptions_assigned_to ON attendance_exceptions(assigned_to_user_id);
CREATE INDEX idx_attendance_exceptions_escalation ON attendance_exceptions(escalation_level);
CREATE INDEX idx_attendance_exceptions_due_at ON attendance_exceptions(due_at);
CREATE INDEX idx_attendance_exceptions_risk_flag ON attendance_exceptions(risk_flag);

COMMENT ON COLUMN attendance_exceptions.escalation_level IS 
'0-24h: SUPERVISOR, 24-48h: FIELD_OFFICER, 48-72h: ADMIN, >72h: PAYROLL_RISK';

COMMENT ON COLUMN attendance_exceptions.risk_flag IS 
'TRUE if unresolved >72h - included in payroll but flagged on payslip';

-- ========================================
-- 2. NOTIFICATION EVENTS TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS notification_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Event details
  event_type TEXT NOT NULL CHECK (event_type IN (
    'EXCEPTION_CREATED',
    'EXCEPTION_ESCALATED',
    'EXCEPTION_RISK_FLAG',
    'EXCEPTION_RESOLVED',
    'PAYROLL_RISK_SUMMARY'
  )),
  
  -- Target
  recipient_user_id UUID REFERENCES users(id),
  recipient_role TEXT,
  
  -- Reference
  reference_id UUID,
  reference_type TEXT CHECK (reference_type IN (
    'ATTENDANCE_EXCEPTION',
    'PAYROLL_PERIOD',
    'GUARD',
    'ORGANIZATION'
  )),
  
  -- Message
  title TEXT NOT NULL,
  message TEXT NOT NULL,
  severity TEXT CHECK (severity IN ('INFO', 'WARNING', 'URGENT', 'CRITICAL')),
  
  -- Payload
  metadata JSONB,
  
  -- Status
  read_at TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_notification_events_recipient ON notification_events(recipient_user_id);
CREATE INDEX idx_notification_events_type ON notification_events(event_type);
CREATE INDEX idx_notification_events_read ON notification_events(read_at) WHERE read_at IS NULL;
CREATE INDEX idx_notification_events_created ON notification_events(created_at DESC);

COMMENT ON TABLE notification_events IS 
'Internal notification events for accountability enforcement - no external integrations';

-- ========================================
-- 3. AUTO-ASSIGN ON EXCEPTION CREATION
-- ========================================

CREATE OR REPLACE FUNCTION auto_assign_exception()
RETURNS TRIGGER AS $$
DECLARE
  v_supervisor_id UUID;
BEGIN
  -- Only process new exceptions
  IF NEW.resolution_status != 'PENDING' THEN
    RETURN NEW;
  END IF;
  
  -- Find site supervisor (logic depends on org structure)
  -- For now, assign to any supervisor in organization
  SELECT id INTO v_supervisor_id
  FROM users
  WHERE organization_id = NEW.organization_id
    AND role IN ('SUPERVISOR', 'SITE_SUPERVISOR')
  LIMIT 1;
  
  -- Set initial assignment
  NEW.assigned_to_user_id := v_supervisor_id;
  NEW.escalation_level := 'SUPERVISOR';
  NEW.due_at := NOW() + INTERVAL '24 hours';
  NEW.risk_flag := false;
  
  -- Create notification event
  INSERT INTO notification_events (
    event_type,
    recipient_user_id,
    reference_id,
    reference_type,
    title,
    message,
    severity,
    metadata
  )
  VALUES (
    'EXCEPTION_CREATED',
    v_supervisor_id,
    NEW.id,
    'ATTENDANCE_EXCEPTION',
    'New Attendance Exception',
    format('Exception for %s on %s - Due in 24 hours', 
      (SELECT full_name FROM guards WHERE id = NEW.guard_id),
      NEW.attendance_date
    ),
    'WARNING',
    jsonb_build_object(
      'exception_type', NEW.exception_type,
      'guard_id', NEW.guard_id,
      'attendance_date', NEW.attendance_date,
      'due_at', NEW.due_at
    )
  );
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_assign_exception
  BEFORE INSERT ON attendance_exceptions
  FOR EACH ROW
  WHEN (NEW.resolution_status = 'PENDING')
  EXECUTE FUNCTION auto_assign_exception();

COMMENT ON FUNCTION auto_assign_exception IS 
'Auto-assigns new exception to supervisor with 24h deadline';

-- ========================================
-- 4. EXCEPTION ESCALATION PROCESSOR
-- ========================================

CREATE OR REPLACE FUNCTION process_unresolved_attendance_exceptions()
RETURNS JSONB AS $$
DECLARE
  v_exception RECORD;
  v_new_assignee UUID;
  v_new_level TEXT;
  v_escalated_count INTEGER := 0;
  v_risk_flagged_count INTEGER := 0;
  v_hours_overdue NUMERIC;
BEGIN
  -- Process all PENDING exceptions
  FOR v_exception IN
    SELECT * FROM attendance_exceptions
    WHERE resolution_status = 'PENDING'
      AND due_at < NOW()
    ORDER BY created_at
  LOOP
    -- Calculate hours overdue
    v_hours_overdue := EXTRACT(EPOCH FROM (NOW() - v_exception.created_at)) / 3600;
    
    -- ========================================
    -- ESCALATION LEVELS
    -- ========================================
    
    IF v_hours_overdue > 72 THEN
      -- >72 hours: PAYROLL_RISK
      IF v_exception.escalation_level != 'PAYROLL_RISK' THEN
        -- Find admin
        SELECT id INTO v_new_assignee
        FROM users
        WHERE organization_id = v_exception.organization_id
          AND role IN ('ADMIN', 'SUPER_ADMIN')
        ORDER BY created_at
        LIMIT 1;
        
        v_new_level := 'PAYROLL_RISK';
        
        UPDATE attendance_exceptions
        SET
          escalation_level = v_new_level,
          assigned_to_user_id = v_new_assignee,
          escalated_at = NOW(),
          last_escalation_at = NOW(),
          risk_flag = true  -- CRITICAL: Flag for payroll
        WHERE id = v_exception.id;
        
        -- Notification
        INSERT INTO notification_events (
          event_type,
          recipient_user_id,
          reference_id,
          reference_type,
          title,
          message,
          severity,
          metadata
        )
        VALUES (
          'EXCEPTION_RISK_FLAG',
          v_new_assignee,
          v_exception.id,
          'ATTENDANCE_EXCEPTION',
          'CRITICAL: Attendance Exception Past 72h',
          format('Exception for %s (%s) unresolved for %s hours - PAYROLL RISK',
            (SELECT full_name FROM guards WHERE id = v_exception.guard_id),
            v_exception.attendance_date,
            ROUND(v_hours_overdue, 1)
          ),
          'CRITICAL',
          jsonb_build_object(
            'hours_overdue', v_hours_overdue,
            'exception_type', v_exception.exception_type,
            'guard_id', v_exception.guard_id
          )
        );
        
        v_risk_flagged_count := v_risk_flagged_count + 1;
      END IF;
      
    ELSIF v_hours_overdue > 48 THEN
      -- 48-72 hours: ADMIN
      IF v_exception.escalation_level NOT IN ('ADMIN', 'PAYROLL_RISK') THEN
        -- Find admin
        SELECT id INTO v_new_assignee
        FROM users
        WHERE organization_id = v_exception.organization_id
          AND role IN ('ADMIN', 'SUPER_ADMIN')
        ORDER BY created_at
        LIMIT 1;
        
        v_new_level := 'ADMIN';
        
        UPDATE attendance_exceptions
        SET
          escalation_level = v_new_level,
          assigned_to_user_id = v_new_assignee,
          escalated_at = NOW(),
          last_escalation_at = NOW(),
          due_at = NOW() + INTERVAL '24 hours'
        WHERE id = v_exception.id;
        
        -- Notification
        INSERT INTO notification_events (
          event_type,
          recipient_user_id,
          reference_id,
          reference_type,
          title,
          message,
          severity,
          metadata
        )
        VALUES (
          'EXCEPTION_ESCALATED',
          v_new_assignee,
          v_exception.id,
          'ATTENDANCE_EXCEPTION',
          'URGENT: Exception Escalated to Admin',
          format('Exception for %s (%s) escalated after 48h',
            (SELECT full_name FROM guards WHERE id = v_exception.guard_id),
            v_exception.attendance_date
          ),
          'URGENT',
          jsonb_build_object(
            'hours_overdue', v_hours_overdue,
            'from_level', v_exception.escalation_level,
            'to_level', v_new_level
          )
        );
        
        v_escalated_count := v_escalated_count + 1;
      END IF;
      
    ELSIF v_hours_overdue > 24 THEN
      -- 24-48 hours: FIELD_OFFICER
      IF v_exception.escalation_level = 'SUPERVISOR' THEN
        -- Find field officer
        SELECT id INTO v_new_assignee
        FROM users
        WHERE organization_id = v_exception.organization_id
          AND role IN ('FIELD_OFFICER', 'MANAGER')
        ORDER BY created_at
        LIMIT 1;
        
        v_new_level := 'FIELD_OFFICER';
        
        UPDATE attendance_exceptions
        SET
          escalation_level = v_new_level,
          assigned_to_user_id = COALESCE(v_new_assignee, assigned_to_user_id),
          escalated_at = NOW(),
          last_escalation_at = NOW(),
          due_at = NOW() + INTERVAL '24 hours'
        WHERE id = v_exception.id;
        
        -- Notification
        INSERT INTO notification_events (
          event_type,
          recipient_user_id,
          reference_id,
          reference_type,
          title,
          message,
          severity,
          metadata
        )
        VALUES (
          'EXCEPTION_ESCALATED',
          COALESCE(v_new_assignee, v_exception.assigned_to_user_id),
          v_exception.id,
          'ATTENDANCE_EXCEPTION',
          'Exception Escalated to Field Officer',
          format('Exception for %s (%s) escalated after 24h',
            (SELECT full_name FROM guards WHERE id = v_exception.guard_id),
            v_exception.attendance_date
          ),
          'WARNING',
          jsonb_build_object(
            'hours_overdue', v_hours_overdue,
            'from_level', 'SUPERVISOR',
            'to_level', v_new_level
          )
        );
        
        v_escalated_count := v_escalated_count + 1;
      END IF;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'escalated_count', v_escalated_count,
    'risk_flagged_count', v_risk_flagged_count,
    'processed_at', NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION process_unresolved_attendance_exceptions IS 
'CRON JOB: Escalates unresolved exceptions - SUPERVISOR → FIELD_OFFICER → ADMIN → PAYROLL_RISK';

-- ========================================
-- 5. PAYROLL RISK SUMMARY
-- ========================================

CREATE OR REPLACE VIEW payroll_risk_summary AS
SELECT 
  pp.id AS payroll_period_id,
  pp.from_date,
  pp.to_date,
  pp.organization_id,
  o.name AS organization_name,
  
  -- Exception counts
  COUNT(DISTINCT ae.id) AS total_exceptions,
  COUNT(DISTINCT ae.id) FILTER (WHERE ae.resolution_status = 'PENDING') AS pending_exceptions,
  COUNT(DISTINCT ae.id) FILTER (WHERE ae.risk_flag = true) AS risk_flagged_exceptions,
  
  -- Affected guards count
  COUNT(DISTINCT ae.guard_id) AS affected_guards_count,
  
  -- Escalation breakdown
  COUNT(*) FILTER (WHERE ae.escalation_level = 'SUPERVISOR') AS supervisor_level,
  COUNT(*) FILTER (WHERE ae.escalation_level = 'FIELD_OFFICER') AS field_officer_level,
  COUNT(*) FILTER (WHERE ae.escalation_level = 'ADMIN') AS admin_level,
  COUNT(*) FILTER (WHERE ae.escalation_level = 'PAYROLL_RISK') AS payroll_risk_level,
  
  -- Oldest unresolved
  MIN(ae.created_at) FILTER (WHERE ae.resolution_status = 'PENDING') AS oldest_unresolved_at
FROM payroll_periods pp
JOIN organizations o ON o.id = pp.organization_id
LEFT JOIN attendance_exceptions ae ON ae.attempted_period_id = pp.id
GROUP BY pp.id, pp.from_date, pp.to_date, pp.organization_id, o.name;

COMMENT ON VIEW payroll_risk_summary IS 
'Payroll risk summary - shows unresolved exceptions per period';

-- ========================================
-- 6. GUARD PAYROLL RISK FLAG
-- ========================================

CREATE OR REPLACE VIEW guard_payroll_risk_status AS
SELECT 
  pc.id AS calculation_id,
  pc.payroll_period_id,
  pc.guard_id,
  g.full_name AS guard_name,
  
  -- Payroll amounts
  pc.net_pay,
  
  -- Risk flag
  EXISTS (
    SELECT 1 FROM attendance_exceptions ae
    WHERE ae.guard_id = pc.guard_id
      AND ae.attempted_period_id = pc.payroll_period_id
      AND ae.resolution_status = 'PENDING'
      AND ae.risk_flag = true
  ) AS has_payroll_risk,
  
  -- Exception details
  (
    SELECT COUNT(*) FROM attendance_exceptions ae
    WHERE ae.guard_id = pc.guard_id
      AND ae.attempted_period_id = pc.payroll_period_id
      AND ae.resolution_status = 'PENDING'
  ) AS unresolved_exceptions_count,
  
  (
    SELECT json_agg(
      json_build_object(
        'exception_type', ae.exception_type,
        'exception_message', ae.exception_message,
        'created_at', ae.created_at,
        'escalation_level', ae.escalation_level
      )
    )
    FROM attendance_exceptions ae
    WHERE ae.guard_id = pc.guard_id
      AND ae.attempted_period_id = pc.payroll_period_id
      AND ae.resolution_status = 'PENDING'
  ) AS exception_details
FROM payroll_calculations pc
JOIN guards g ON g.id = pc.guard_id;

COMMENT ON VIEW guard_payroll_risk_status IS 
'Per-guard payroll risk status - used for payslip warnings';

-- ========================================
-- 7. PAYROLL GENERATION WITH RISK FLAGS
-- ========================================

CREATE OR REPLACE FUNCTION generate_payroll_with_risk_check(
  p_period_id UUID,
  p_org_id UUID,
  p_generated_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_result JSONB;
  v_risk_count INTEGER;
  v_affected_guards INTEGER;
BEGIN
  -- Generate payroll normally (includes all valid attendance)
  v_result := generate_payroll_calculations_v2(p_period_id, p_org_id, p_generated_by);
  
  -- Count risk-flagged guards
  SELECT 
    COUNT(DISTINCT ae.guard_id)
  INTO v_affected_guards
  FROM attendance_exceptions ae
  WHERE ae.attempted_period_id = p_period_id
    AND ae.resolution_status = 'PENDING'
    AND ae.risk_flag = true;
  
  -- Count risk flags
  SELECT 
    COUNT(*)
  INTO v_risk_count
  FROM attendance_exceptions ae
  WHERE ae.attempted_period_id = p_period_id
    AND ae.resolution_status = 'PENDING'
    AND ae.risk_flag = true;
  
  -- Add risk info to result
  v_result := v_result || jsonb_build_object(
    'payroll_risk_warning', v_risk_count > 0,
    'risk_flagged_exceptions', v_risk_count,
    'affected_guards_count', v_affected_guards,
    'warning_message', 
      CASE 
        WHEN v_risk_count > 0 THEN 
          format('%s guards paid with %s unresolved attendance issues', 
            v_affected_guards, v_risk_count)
        ELSE NULL
      END
  );
  
  -- Create notification for admin if risks exist
  IF v_risk_count > 0 THEN
    INSERT INTO notification_events (
      event_type,
      recipient_user_id,
      reference_id,
      reference_type,
      title,
      message,
      severity,
      metadata
    )
    VALUES (
      'PAYROLL_RISK_SUMMARY',
      p_generated_by,
      p_period_id,
      'PAYROLL_PERIOD',
      'Payroll Generated with Risk Flags',
      format('%s guards paid with %s unresolved attendance issues',
        v_affected_guards, v_risk_count
      ),
      'CRITICAL',
      jsonb_build_object(
        'period_id', p_period_id,
        'risk_count', v_risk_count,
        'affected_guards', v_affected_guards
      )
    );
  END IF;
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_payroll_with_risk_check IS 
'Generates payroll with risk flag reporting - does NOT block, only warns';

-- ========================================
-- 8. PAYSLIP RISK WARNING
-- ========================================

CREATE OR REPLACE FUNCTION get_payslip_with_warnings(
  p_calculation_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_calculation payroll_calculations;
  v_exceptions JSONB;
  v_risk_flag BOOLEAN;
BEGIN
  -- Get calculation
  SELECT * INTO v_calculation FROM payroll_calculations WHERE id = p_calculation_id;
  
  -- Check for risk flags
  SELECT 
    COUNT(*) > 0,
    json_agg(
      json_build_object(
        'type', exception_type,
        'message', exception_message,
        'date', attendance_date,
        'level', escalation_level
      )
    )
  INTO v_risk_flag, v_exceptions
  FROM attendance_exceptions
  WHERE guard_id = v_calculation.guard_id
    AND attempted_period_id = v_calculation.payroll_period_id
    AND resolution_status = 'PENDING';
  
  RETURN jsonb_build_object(
    'calculation_id', p_calculation_id,
    'guard_id', v_calculation.guard_id,
    'net_pay', v_calculation.net_pay,
    'has_warnings', v_risk_flag,
    'warning_message', 
      CASE WHEN v_risk_flag THEN 
        'This payslip includes attendance with unresolved exceptions. Contact admin for details.'
      ELSE NULL END,
    'exceptions', v_exceptions,
    'payroll_period_id', v_calculation.payroll_period_id
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_payslip_with_warnings IS 
'Generates payslip with risk warnings - salary paid but flagged';
