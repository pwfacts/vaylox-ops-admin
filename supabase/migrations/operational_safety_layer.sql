-- ============================================
-- OPERATIONAL SAFETY LAYER (NON-BLOCKING)
-- Pure additions - zero modifications to existing logic
-- ============================================

-- STRICT COMPLIANCE:
-- ✅ LAW 1: Never blocks operations
-- ✅ LAW 2: No existing table/function modifications
-- ✅ LAW 3: Only additive objects
-- ✅ LAW 4: Influences behavior without preventing work
-- ✅ LAW 5: DB-level tenant isolation
-- ✅ LAW 6: Automatic operation (no dashboard dependency)

-- ========================================
-- PART 1: DAILY CLOSURE PRESSURE
-- ========================================

-- Supervisor daily acknowledgements (awareness gate)
CREATE TABLE IF NOT EXISTS supervisor_daily_acknowledgements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  supervisor_id UUID NOT NULL REFERENCES users(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  work_date DATE NOT NULL,
  pending_count_at_login INTEGER NOT NULL DEFAULT 0,
  acknowledged_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(supervisor_id, work_date)
);

CREATE INDEX idx_super_ack_supervisor ON supervisor_daily_acknowledgements(supervisor_id);
CREATE INDEX idx_super_ack_org ON supervisor_daily_acknowledgements(organization_id);
CREATE INDEX idx_super_ack_date ON supervisor_daily_acknowledgements(work_date);

COMMENT ON TABLE supervisor_daily_acknowledgements IS 
'DISCIPLINE: Logs supervisor daily acknowledgement of pending reviews (non-blocking)';

-- Get supervisor operational status (returns awareness metrics)
CREATE OR REPLACE FUNCTION get_supervisor_operational_status(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user users;
  v_yesterday_pending INTEGER;
  v_today_pending INTEGER;
  v_oldest_pending_days INTEGER;
  v_acknowledged_today BOOLEAN;
  v_requires_acknowledgement BOOLEAN;
BEGIN
  -- Get user details
  SELECT * INTO v_user FROM users WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;
  
  -- Count yesterday pending
  SELECT COUNT(*) INTO v_yesterday_pending
  FROM attendance a
  LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE a.approval_status = 'RECORDED'
    AND a.attendance_date = CURRENT_DATE - INTERVAL '1 day'
    AND a.organization_id = v_user.organization_id
    AND (
      v_user.role IN ('ADMIN', 'SUPER_ADMIN')
      OR si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
    );
  
  -- Count today pending
  SELECT COUNT(*) INTO v_today_pending
  FROM attendance a
  LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE a.approval_status = 'RECORDED'
    AND a.attendance_date = CURRENT_DATE
    AND a.organization_id = v_user.organization_id
    AND (
      v_user.role IN ('ADMIN', 'SUPER_ADMIN')
      OR si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
    );
  
  -- Find oldest pending
  SELECT CURRENT_DATE - MIN(a.attendance_date) INTO v_oldest_pending_days
  FROM attendance a
  LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE a.approval_status = 'RECORDED'
    AND a.organization_id = v_user.organization_id
    AND (
      v_user.role IN ('ADMIN', 'SUPER_ADMIN')
      OR si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
    );
  
  -- Check if acknowledged today
  SELECT EXISTS(
    SELECT 1 FROM supervisor_daily_acknowledgements
    WHERE supervisor_id = p_user_id
      AND work_date = CURRENT_DATE
  ) INTO v_acknowledged_today;
  
  -- Requires acknowledgement if yesterday has pending and not acknowledged today
  v_requires_acknowledgement := v_yesterday_pending > 0 AND NOT v_acknowledged_today;
  
  RETURN jsonb_build_object(
    'success', true,
    'supervisor_id', p_user_id,
    'organization_id', v_user.organization_id,
    'yesterday_pending_count', v_yesterday_pending,
    'today_pending_count', v_today_pending,
    'oldest_pending_days', COALESCE(v_oldest_pending_days, 0),
    'requires_acknowledgement', v_requires_acknowledgement,
    'acknowledged_today', v_acknowledged_today,
    'warning_message', CASE 
      WHEN v_requires_acknowledgement THEN 
        format('%s attendance from yesterday still pending review', v_yesterday_pending)
      ELSE NULL
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_supervisor_operational_status IS 
'AWARENESS: Returns pending metrics, requires acknowledgement if yesterday has pending (non-blocking)';

-- Record supervisor acknowledgement
CREATE OR REPLACE FUNCTION supervisor_acknowledge_pending(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user users;
  v_pending_count INTEGER;
BEGIN
  SELECT * INTO v_user FROM users WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;
  
  -- Count current pending
  SELECT COUNT(*) INTO v_pending_count
  FROM attendance a
  LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE a.approval_status = 'RECORDED'
    AND a.organization_id = v_user.organization_id
    AND (
      v_user.role IN ('ADMIN', 'SUPER_ADMIN')
      OR si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
    );
  
  -- Record acknowledgement
  INSERT INTO supervisor_daily_acknowledgements (
    supervisor_id,
    organization_id,
    work_date,
    pending_count_at_login
  )
  VALUES (
    p_user_id,
    v_user.organization_id,
    CURRENT_DATE,
    v_pending_count
  )
  ON CONFLICT (supervisor_id, work_date)
  DO UPDATE SET
    acknowledged_at = NOW(),
    pending_count_at_login = EXCLUDED.pending_count_at_login;
  
  RETURN jsonb_build_object(
    'success', true,
    'acknowledged', true,
    'pending_count', v_pending_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_acknowledge_pending IS 
'ACKNOWLEDGEMENT: Records supervisor daily acknowledgement (non-blocking, awareness only)';

-- Supervisor attention required (automatic monitoring)
CREATE OR REPLACE VIEW supervisor_attention_required_view AS
SELECT 
  u.id AS supervisor_id,
  u.email AS supervisor_email,
  u.organization_id,
  
  -- Pending metrics
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'RECORDED' 
      AND a.attendance_date < CURRENT_DATE - INTERVAL '2 days'
  ) AS pending_older_than_2_days,
  
  MIN(a.attendance_date) FILTER (
    WHERE a.approval_status = 'RECORDED'
  ) AS oldest_pending_date,
  
  CURRENT_DATE - MIN(a.attendance_date) FILTER (
    WHERE a.approval_status = 'RECORDED'
  ) AS days_ignoring_reviews,
  
  -- Last acknowledgement
  MAX(sda.acknowledged_at) AS last_acknowledgement_at,
  CURRENT_DATE - MAX(sda.work_date) AS days_since_last_acknowledgement,
  
  -- Flags
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'RECORDED' 
      AND a.attendance_date < CURRENT_DATE - INTERVAL '2 days'
  ) > 0 AS attention_required
FROM users u
LEFT JOIN units un ON un.supervisor_id = u.id
LEFT JOIN shift_instances si ON si.unit_id = un.id
LEFT JOIN attendance a ON a.shift_instance_id = si.id
LEFT JOIN supervisor_daily_acknowledgements sda ON sda.supervisor_id = u.id
WHERE u.role IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER')
GROUP BY u.id, u.email, u.organization_id
HAVING COUNT(DISTINCT a.id) FILTER (
  WHERE a.approval_status = 'RECORDED' 
    AND a.attendance_date < CURRENT_DATE - INTERVAL '2 days'
) > 0;

COMMENT ON VIEW supervisor_attention_required_view IS 
'MONITORING: Supervisors ignoring reviews >2 days (automatic alerting source)';

-- ========================================
-- PART 2: HARD TENANT ISOLATION
-- ========================================

-- Current user organization (session-based tenant isolation)
CREATE OR REPLACE FUNCTION current_user_organization_id()
RETURNS UUID AS $$
DECLARE
  v_user_id UUID;
  v_org_id UUID;
BEGIN
  -- Get user from session (assumes auth.uid() available in Supabase)
  v_user_id := auth.uid();
  
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No authenticated user';
  END IF;
  
  SELECT organization_id INTO v_org_id FROM users WHERE id = v_user_id;
  
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'User has no organization';
  END IF;
  
  RETURN v_org_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION current_user_organization_id IS 
'TENANT ISOLATION: Returns current user organization (enforced at DB level)';

-- Safe attendance view (tenant-isolated)
CREATE OR REPLACE VIEW safe_attendance_view AS
SELECT 
  a.*
FROM attendance a
WHERE a.organization_id = current_user_organization_id();

COMMENT ON VIEW safe_attendance_view IS 
'TENANT SAFE: Attendance filtered by current user organization (DB-enforced isolation)';

-- Safe shift view (tenant-isolated)
CREATE OR REPLACE VIEW safe_shift_view AS
SELECT 
  si.*
FROM shift_instances si
WHERE si.organization_id = current_user_organization_id();

COMMENT ON VIEW safe_shift_view IS 
'TENANT SAFE: Shifts filtered by current user organization (DB-enforced isolation)';

-- Safe payroll view (tenant-isolated)
CREATE OR REPLACE VIEW safe_payroll_view AS
SELECT 
  pp.*
FROM payroll_periods pp
WHERE pp.organization_id = current_user_organization_id();

COMMENT ON VIEW safe_payroll_view IS 
'TENANT SAFE: Payroll filtered by current user organization (DB-enforced isolation)';

-- ========================================
-- PART 3: SITE COVERAGE REALITY CHECK
-- ========================================

-- Site daily coverage analysis (fraud/mistake detection)
CREATE TABLE IF NOT EXISTS site_daily_coverage_analysis (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  analysis_date DATE NOT NULL,
  required_guard_count INTEGER NOT NULL DEFAULT 1,
  approved_guard_count INTEGER NOT NULL DEFAULT 0,
  coverage_hours DECIMAL(10,2),
  overcoverage_flag BOOLEAN DEFAULT false,
  undercoverage_flag BOOLEAN DEFAULT false,
  approved_guard_ids UUID[],
  analysis_details JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(organization_id, unit_id, analysis_date)
);

CREATE INDEX idx_coverage_org ON site_daily_coverage_analysis(organization_id);
CREATE INDEX idx_coverage_unit ON site_daily_coverage_analysis(unit_id);
CREATE INDEX idx_coverage_date ON site_daily_coverage_analysis(analysis_date);
CREATE INDEX idx_coverage_flags ON site_daily_coverage_analysis(overcoverage_flag, undercoverage_flag);

COMMENT ON TABLE site_daily_coverage_analysis IS 
'COVERAGE CHECK: Detects over/under staffing based on approved attendance (non-blocking)';

-- Analyze daily site coverage
CREATE OR REPLACE FUNCTION analyze_daily_site_coverage(
  p_unit_id UUID,
  p_date DATE
)
RETURNS JSONB AS $$
DECLARE
  v_unit units;
  v_required_count INTEGER;
  v_approved_count INTEGER;
  v_approved_guards UUID[];
  v_total_hours DECIMAL;
  v_overcoverage BOOLEAN;
  v_undercoverage BOOLEAN;
BEGIN
  -- Get unit
  SELECT * INTO v_unit FROM units WHERE id = p_unit_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNIT_NOT_FOUND');
  END IF;
  
  -- Get required guard count from shifts
  SELECT COALESCE(SUM(required_guards), 1) INTO v_required_count
  FROM shift_instances
  WHERE unit_id = p_unit_id
    AND shift_date = p_date;
  
  -- Count approved attendance
  SELECT 
    COUNT(DISTINCT a.guard_id),
    array_agg(DISTINCT a.guard_id),
    SUM(EXTRACT(EPOCH FROM (a.check_out_time - a.check_in_time)) / 3600)
  INTO v_approved_count, v_approved_guards, v_total_hours
  FROM attendance a
  JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE si.unit_id = p_unit_id
    AND a.attendance_date = p_date
    AND a.approval_status IN ('APPROVED', 'APPROVED_AUTO');
  
  -- Determine flags
  v_overcoverage := v_approved_count > v_required_count;
  v_undercoverage := v_approved_count < v_required_count AND v_approved_count > 0;
  
  -- Store analysis
  INSERT INTO site_daily_coverage_analysis (
    organization_id,
    unit_id,
    analysis_date,
    required_guard_count,
    approved_guard_count,
    coverage_hours,
    overcoverage_flag,
    undercoverage_flag,
    approved_guard_ids,
    analysis_details
  )
  VALUES (
    v_unit.organization_id,
    p_unit_id,
    p_date,
    v_required_count,
    COALESCE(v_approved_count, 0),
    v_total_hours,
    v_overcoverage,
    v_undercoverage,
    v_approved_guards,
    jsonb_build_object(
      'excess_guards', GREATEST(v_approved_count - v_required_count, 0),
      'missing_guards', GREATEST(v_required_count - v_approved_count, 0)
    )
  )
  ON CONFLICT (organization_id, unit_id, analysis_date)
  DO UPDATE SET
    approved_guard_count = EXCLUDED.approved_guard_count,
    coverage_hours = EXCLUDED.coverage_hours,
    overcoverage_flag = EXCLUDED.overcoverage_flag,
    undercoverage_flag = EXCLUDED.undercoverage_flag,
    approved_guard_ids = EXCLUDED.approved_guard_ids,
    analysis_details = EXCLUDED.analysis_details,
    created_at = NOW();
  
  RETURN jsonb_build_object(
    'success', true,
    'unit_id', p_unit_id,
    'date', p_date,
    'required_count', v_required_count,
    'approved_count', COALESCE(v_approved_count, 0),
    'overcoverage', v_overcoverage,
    'undercoverage', v_undercoverage
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION analyze_daily_site_coverage IS 
'ANALYSIS: Compares approved vs required guards per site (non-blocking detection)';

-- Coverage risk dashboard (repeated overcoverage detection)
CREATE OR REPLACE VIEW coverage_risk_dashboard AS
WITH recent_coverage AS (
  SELECT 
    organization_id,
    unit_id,
    analysis_date,
    required_guard_count,
    approved_guard_count,
    overcoverage_flag,
    analysis_details
  FROM site_daily_coverage_analysis
  WHERE analysis_date >= CURRENT_DATE - INTERVAL '7 days'
)
SELECT 
  rc.organization_id,
  rc.unit_id,
  u.name AS unit_name,
  
  -- Metrics
  COUNT(*) FILTER (WHERE overcoverage_flag = true) AS overcoverage_days_7d,
  SUM((analysis_details->>'excess_guards')::INTEGER) AS total_excess_guards_7d,
  ARRAY_AGG(analysis_date ORDER BY analysis_date DESC) FILTER (WHERE overcoverage_flag = true) AS overcoverage_dates,
  
  -- Risk flag
  COUNT(*) FILTER (WHERE overcoverage_flag = true) >= 3 AS repeated_overcoverage_risk,
  
  -- Details
  AVG(approved_guard_count) AS avg_approved_guards,
  AVG(required_guard_count) AS avg_required_guards
FROM recent_coverage rc
JOIN units u ON u.id = rc.unit_id
GROUP BY rc.organization_id, rc.unit_id, u.name
HAVING COUNT(*) FILTER (WHERE overcoverage_flag = true) >= 3;

COMMENT ON VIEW coverage_risk_dashboard IS 
'RISK DETECTION: Sites with repeated overcoverage (3+ days in 7) - automatic fraud detection';

-- ========================================
-- PART 4: AUTO RISK ESCALATION
-- ========================================

-- Operational risk events (automatic logging)
CREATE TABLE IF NOT EXISTS operational_risk_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  risk_type TEXT NOT NULL CHECK (risk_type IN (
    'SUPERVISOR_IGNORING_REVIEWS',
    'EXCESSIVE_AUTO_APPROVALS',
    'REPEATED_OVERCOVERAGE',
    'APPROVAL_WITHOUT_PUNCH',
    'ATTENDANCE_GAP'
  )),
  severity TEXT NOT NULL CHECK (severity IN ('LOW', 'MEDIUM', 'HIGH', 'CRITICAL')),
  related_entity_type TEXT,
  related_entity_id UUID,
  risk_details JSONB,
  detected_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_risk_events_org ON operational_risk_events(organization_id);
CREATE INDEX idx_risk_events_type ON operational_risk_events(risk_type);
CREATE INDEX idx_risk_events_severity ON operational_risk_events(severity);
CREATE INDEX idx_risk_events_detected ON operational_risk_events(detected_at);

COMMENT ON TABLE operational_risk_events IS 
'AUTOMATIC RISK LOG: System-generated risk events (no manual review needed)';

-- Auto-detect supervisor ignoring reviews
CREATE OR REPLACE FUNCTION auto_detect_supervisor_risks()
RETURNS JSONB AS $$
DECLARE
  v_supervisor RECORD;
  v_events_created INTEGER := 0;
BEGIN
  -- Detect supervisors ignoring reviews >48h
  FOR v_supervisor IN
    SELECT 
      u.id AS supervisor_id,
      u.organization_id,
      COUNT(DISTINCT a.id) AS pending_count,
      MIN(a.attendance_date) AS oldest_pending_date,
      CURRENT_DATE - MIN(a.attendance_date) AS days_pending
    FROM users u
    LEFT JOIN units un ON un.supervisor_id = u.id
    LEFT JOIN shift_instances si ON si.unit_id = un.id
    LEFT JOIN attendance a ON a.shift_instance_id = si.id
    WHERE u.role IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER')
      AND a.approval_status = 'RECORDED'
      AND a.attendance_date < CURRENT_DATE - INTERVAL '2 days'
    GROUP BY u.id, u.organization_id
    HAVING COUNT(DISTINCT a.id) > 0
  LOOP
    -- Create risk event
    INSERT INTO operational_risk_events (
      organization_id,
      risk_type,
      severity,
      related_entity_type,
      related_entity_id,
      risk_details
    )
    VALUES (
      v_supervisor.organization_id,
      'SUPERVISOR_IGNORING_REVIEWS',
      CASE 
        WHEN v_supervisor.days_pending > 7 THEN 'CRITICAL'
        WHEN v_supervisor.days_pending > 5 THEN 'HIGH'
        WHEN v_supervisor.days_pending > 3 THEN 'MEDIUM'
        ELSE 'LOW'
      END,
      'SUPERVISOR',
      v_supervisor.supervisor_id,
      jsonb_build_object(
        'pending_count', v_supervisor.pending_count,
        'oldest_pending_date', v_supervisor.oldest_pending_date,
        'days_pending', v_supervisor.days_pending
      )
    )
    ON CONFLICT DO NOTHING;
    
    v_events_created := v_events_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'events_created', v_events_created,
    'risk_type', 'SUPERVISOR_IGNORING_REVIEWS'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_detect_supervisor_risks IS 
'AUTO DETECTION: Creates risk events for supervisors ignoring reviews >48h';

-- Auto-detect excessive auto-approvals
CREATE OR REPLACE FUNCTION auto_detect_auto_approval_risks()
RETURNS JSONB AS $$
DECLARE
  v_org RECORD;
  v_events_created INTEGER := 0;
  v_threshold INTEGER := 20;
BEGIN
  -- Detect organizations with excessive auto-approvals
  FOR v_org IN
    SELECT 
      organization_id,
      COUNT(*) AS auto_approval_count_7d
    FROM attendance
    WHERE approval_status = 'APPROVED_AUTO'
      AND approved_at >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY organization_id
    HAVING COUNT(*) > v_threshold
  LOOP
    INSERT INTO operational_risk_events (
      organization_id,
      risk_type,
      severity,
      related_entity_type,
      risk_details
    )
    VALUES (
      v_org.organization_id,
      'EXCESSIVE_AUTO_APPROVALS',
      CASE 
        WHEN v_org.auto_approval_count_7d > 100 THEN 'CRITICAL'
        WHEN v_org.auto_approval_count_7d > 50 THEN 'HIGH'
        ELSE 'MEDIUM'
      END,
      'ORGANIZATION',
      jsonb_build_object(
        'auto_approval_count_7d', v_org.auto_approval_count_7d,
        'threshold', v_threshold
      )
    )
    ON CONFLICT DO NOTHING;
    
    v_events_created := v_events_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'events_created', v_events_created,
    'risk_type', 'EXCESSIVE_AUTO_APPROVALS'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_detect_auto_approval_risks IS 
'AUTO DETECTION: Creates risk events for excessive auto-approvals';

-- Auto-detect repeated overcoverage
CREATE OR REPLACE FUNCTION auto_detect_coverage_risks()
RETURNS JSONB AS $$
DECLARE
  v_site RECORD;
  v_events_created INTEGER := 0;
BEGIN
  -- Detect sites with repeated overcoverage
  FOR v_site IN
    SELECT * FROM coverage_risk_dashboard
  LOOP
    INSERT INTO operational_risk_events (
      organization_id,
      risk_type,
      severity,
      related_entity_type,
      related_entity_id,
      risk_details
    )
    VALUES (
      v_site.organization_id,
      'REPEATED_OVERCOVERAGE',
      CASE 
        WHEN v_site.overcoverage_days_7d >= 5 THEN 'HIGH'
        ELSE 'MEDIUM'
      END,
      'UNIT',
      v_site.unit_id,
      jsonb_build_object(
        'unit_name', v_site.unit_name,
        'overcoverage_days_7d', v_site.overcoverage_days_7d,
        'total_excess_guards_7d', v_site.total_excess_guards_7d,
        'overcoverage_dates', v_site.overcoverage_dates
      )
    )
    ON CONFLICT DO NOTHING;
    
    v_events_created := v_events_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'events_created', v_events_created,
    'risk_type', 'REPEATED_OVERCOVERAGE'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_detect_coverage_risks IS 
'AUTO DETECTION: Creates risk events for repeated site overcoverage';

-- Master risk detection (runs all checks)
CREATE OR REPLACE FUNCTION run_automatic_risk_detection()
RETURNS JSONB AS $$
DECLARE
  v_supervisor_risks JSONB;
  v_auto_approval_risks JSONB;
  v_coverage_risks JSONB;
BEGIN
  v_supervisor_risks := auto_detect_supervisor_risks();
  v_auto_approval_risks := auto_detect_auto_approval_risks();
  v_coverage_risks := auto_detect_coverage_risks();
  
  RETURN jsonb_build_object(
    'success', true,
    'timestamp', NOW(),
    'supervisor_risks', v_supervisor_risks,
    'auto_approval_risks', v_auto_approval_risks,
    'coverage_risks', v_coverage_risks
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION run_automatic_risk_detection IS 
'MASTER AUTO DETECTION: Runs all risk detection checks (schedule via cron)';

-- Cron job for automatic risk detection (runs daily)
-- SELECT cron.schedule('auto-risk-detection', '0 1 * * *', $$SELECT run_automatic_risk_detection()$$);
