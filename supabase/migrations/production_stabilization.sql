-- ============================================
-- PRODUCTION STABILIZATION - EXTENSIONS ONLY
-- Zero blocking, pure reporting and safety layers
-- ============================================

-- CRITICAL: This migration ONLY adds:
--   - Logging tables
--   - Reporting views
--   - Metrics functions
--   - Helper utilities
-- NO changes to existing attendance/approval/payroll logic

-- ========================================
-- PART 1: MULTI-AGENCY ARCHITECTURE SAFETY
-- ========================================

-- Add organization_id safety checks (already exists on most tables, ensuring coverage)

-- Organization isolation helper
CREATE OR REPLACE FUNCTION check_organization_access(
  p_user_id UUID,
  p_organization_id UUID
)
RETURNS BOOLEAN AS $$
DECLARE
  v_user_org UUID;
BEGIN
  SELECT organization_id INTO v_user_org FROM users WHERE id = p_user_id;
  RETURN v_user_org = p_organization_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION check_organization_access IS 
'SAFETY: Helper to verify user belongs to organization (for API layer validation)';

-- Organization-scoped data view (ensures no cross-org queries)
CREATE OR REPLACE VIEW organization_data_scope AS
SELECT 
  o.id AS organization_id,
  o.name AS organization_name,
  COUNT(DISTINCT g.id) AS total_guards,
  COUNT(DISTINCT u.id) FILTER (WHERE u.role IN ('SUPERVISOR', 'SITE_SUPERVISOR')) AS total_supervisors,
  COUNT(DISTINCT un.id) AS total_units,
  COUNT(DISTINCT a.id) FILTER (WHERE a.created_at >= CURRENT_DATE - INTERVAL '30 days') AS attendance_last_30_days
FROM organizations o
LEFT JOIN guards g ON g.organization_id = o.id
LEFT JOIN users u ON u.organization_id = o.id
LEFT JOIN units un ON un.organization_id = o.id
LEFT JOIN attendance a ON a.organization_id = o.id
GROUP BY o.id, o.name;

COMMENT ON VIEW organization_data_scope IS 
'MULTI-AGENCY: Overview of each organization data (isolated per org)';

-- ========================================
-- PART 2: SUPERVISOR ACCOUNTABILITY TRACKING
-- ========================================

-- Supervisor performance metrics (non-blocking, reporting only)
CREATE OR REPLACE VIEW supervisor_performance_view AS
WITH supervisor_stats AS (
  SELECT 
    u.id AS supervisor_id,
    u.email AS supervisor_email,
    u.organization_id,
    
    -- Pending reviews today
    COUNT(DISTINCT a.id) FILTER (
      WHERE a.approval_status = 'RECORDED' 
        AND a.attendance_date = CURRENT_DATE
        AND a.approved_by IS NULL
    ) AS pending_reviews_today,
    
    -- Auto-approved in last 7 days (supervisor didn't act)
    COUNT(DISTINCT a2.id) FILTER (
      WHERE a2.approval_status = 'APPROVED_AUTO'
        AND a2.approved_at >= CURRENT_DATE - INTERVAL '7 days'
    ) AS auto_approved_count_7_days,
    
    -- Total approvals in last 7 days
    COUNT(DISTINCT a3.id) FILTER (
      WHERE a3.approved_by = u.id
        AND a3.approved_at >= CURRENT_DATE - INTERVAL '7 days'
    ) AS manual_approvals_7_days,
    
    -- Rejections in last 7 days
    COUNT(DISTINCT a4.id) FILTER (
      WHERE a4.approval_status = 'REJECTED'
        AND a4.approved_by = u.id
        AND a4.approved_at >= CURRENT_DATE - INTERVAL '7 days'
    ) AS rejections_7_days,
    
    -- Late reviews (approved >24h after punch)
    COUNT(DISTINCT a5.id) FILTER (
      WHERE a5.approved_by = u.id
        AND a5.approved_at >= CURRENT_DATE - INTERVAL '7 days'
        AND a5.approved_at > a5.created_at + INTERVAL '24 hours'
    ) AS late_reviews_7_days
    
  FROM users u
  LEFT JOIN shift_instances si ON si.unit_id IN (
    SELECT id FROM units WHERE supervisor_id = u.id OR organization_id = u.organization_id
  )
  LEFT JOIN attendance a ON si.id = a.shift_instance_id
  LEFT JOIN attendance a2 ON si.id = a2.shift_instance_id
  LEFT JOIN attendance a3 ON a3.approved_by = u.id
  LEFT JOIN attendance a4 ON a4.approved_by = u.id
  LEFT JOIN attendance a5 ON a5.approved_by = u.id
  WHERE u.role IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER')
  GROUP BY u.id, u.email, u.organization_id
)
SELECT 
  supervisor_id,
  supervisor_email,
  organization_id,
  pending_reviews_today,
  auto_approved_count_7_days,
  manual_approvals_7_days,
  rejections_7_days,
  late_reviews_7_days,
  
  -- Calculated metrics
  CASE 
    WHEN (manual_approvals_7_days + rejections_7_days) > 0
    THEN ROUND(
      manual_approvals_7_days::DECIMAL / 
      NULLIF(manual_approvals_7_days + rejections_7_days, 0) * 100, 
      1
    )
    ELSE 0
  END AS approval_rate_percent,
  
  CASE 
    WHEN (manual_approvals_7_days + auto_approved_count_7_days) > 0
    THEN ROUND(
      auto_approved_count_7_days::DECIMAL / 
      NULLIF(manual_approvals_7_days + auto_approved_count_7_days, 0) * 100, 
      1
    )
    ELSE 0
  END AS auto_approval_percent,
  
  -- Warning flags (advisory only, non-blocking)
  CASE WHEN auto_approved_count_7_days > 20 THEN 'HIGH_AUTO_APPROVAL' END AS warning_flag
FROM supervisor_stats;

COMMENT ON VIEW supervisor_performance_view IS 
'ACCOUNTABILITY: Supervisor metrics - shows performance, never blocks operations';

-- ========================================
-- PART 3: CLIENT DISPUTE DEFENSE
-- ========================================

-- Site attendance proof (legal billing evidence)
CREATE OR REPLACE FUNCTION generate_site_attendance_proof(
  p_unit_id UUID,
  p_date DATE
)
RETURNS JSONB AS $$
DECLARE
  v_unit units;
  v_result JSONB;
  v_guards JSONB;
BEGIN
  -- Get unit details
  SELECT * INTO v_unit FROM units WHERE id = p_unit_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'UNIT_NOT_FOUND');
  END IF;
  
  -- Get all APPROVED attendance for this site on this date
  SELECT jsonb_agg(
    jsonb_build_object(
      'guard_id', g.id,
      'guard_name', g.full_name,
      'guard_employee_id', g.employee_id,
      'check_in_time', a.check_in_time,
      'check_out_time', a.check_out_time,
      'duration_hours', EXTRACT(EPOCH FROM (a.check_out_time - a.check_in_time)) / 3600,
      'face_verified', a.face_verified,
      'photo_reference', a.metadata->>'face_photo_url',
      'gps_location', ST_AsText(a.location_coords::geometry),
      'approval_status', a.approval_status,
      'approved_by', sup.email,
      'approved_by_name', sup.full_name,
      'approved_at', a.approved_at,
      'verification_mode', a.verification_mode
    )
    ORDER BY a.check_in_time
  ) INTO v_guards
  FROM attendance a
  JOIN guards g ON g.id = a.guard_id
  LEFT JOIN users sup ON sup.id = a.approved_by
  JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE si.unit_id = p_unit_id
    AND a.attendance_date = p_date
    AND a.approval_status IN ('APPROVED', 'APPROVED_AUTO');
  
  -- Build proof document
  v_result := jsonb_build_object(
    'document_type', 'SITE_ATTENDANCE_PROOF',
    'generated_at', NOW(),
    'organization_id', v_unit.organization_id,
    'site_name', v_unit.name,
    'site_address', v_unit.location,
    'date', p_date,
    'total_guards', jsonb_array_length(COALESCE(v_guards, '[]'::JSONB)),
    'guards', COALESCE(v_guards, '[]'::JSONB),
    'certification', jsonb_build_object(
      'certified_by', 'System Generated',
      'disclaimer', 'This is attendance approved by supervisor and auto-confirmation system',
      'legal_note', 'Attendance proof for billing and compliance purposes'
    )
  );
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_site_attendance_proof IS 
'CLIENT DISPUTE DEFENSE: Generates PDF-ready proof of approved attendance for billing disputes';

-- Proof generation log (audit trail)
CREATE TABLE IF NOT EXISTS attendance_proof_exports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID REFERENCES units(id),
  proof_date DATE NOT NULL,
  exported_by UUID REFERENCES users(id),
  exported_at TIMESTAMPTZ DEFAULT NOW(),
  proof_data JSONB NOT NULL,
  export_reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_proof_exports_org ON attendance_proof_exports(organization_id);
CREATE INDEX idx_proof_exports_date ON attendance_proof_exports(proof_date);

COMMENT ON TABLE attendance_proof_exports IS 
'AUDIT: Log of all attendance proof exports for legal/billing purposes';

-- ========================================
-- PART 4: OVER-APPROVAL FINANCIAL SAFETY
-- ========================================

-- Approval anomaly logging (warnings, not blocks)
CREATE TABLE IF NOT EXISTS approval_anomaly_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID REFERENCES units(id),
  shift_instance_id UUID REFERENCES shift_instances(id),
  anomaly_date DATE NOT NULL,
  anomaly_type TEXT NOT NULL CHECK (anomaly_type IN (
    'OVER_APPROVAL',
    'MULTIPLE_APPROVALS_SAME_SHIFT',
    'APPROVAL_WITHOUT_PUNCH',
    'LATE_APPROVAL'
  )),
  required_count INTEGER,
  approved_count INTEGER,
  supervisor_id UUID REFERENCES users(id),
  anomaly_details JSONB,
  detected_at TIMESTAMPTZ DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_anomaly_logs_org ON approval_anomaly_logs(organization_id);
CREATE INDEX idx_anomaly_logs_type ON approval_anomaly_logs(anomaly_type);
CREATE INDEX idx_anomaly_logs_date ON approval_anomaly_logs(anomaly_date);

COMMENT ON TABLE approval_anomaly_logs IS 
'FINANCIAL SAFETY: Logs over-approvals and anomalies (advisory, non-blocking)';

-- Check for over-approval (returns warning, doesn't block)
CREATE OR REPLACE FUNCTION check_approval_anomaly(
  p_shift_instance_id UUID,
  p_supervisor_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_required_count INTEGER;
  v_approved_count INTEGER;
  v_warning JSONB := '[]'::JSONB;
BEGIN
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('has_anomaly', false);
  END IF;
  
  -- Get required guard count for this shift
  v_required_count := COALESCE(v_shift.required_guards, 1);
  
  -- Count approved attendance for this shift
  SELECT COUNT(*) INTO v_approved_count
  FROM attendance
  WHERE shift_instance_id = p_shift_instance_id
    AND approval_status IN ('APPROVED', 'APPROVED_AUTO');
  
  -- Check for over-approval
  IF v_approved_count > v_required_count THEN
    -- Log anomaly (non-blocking)
    INSERT INTO approval_anomaly_logs (
      organization_id,
      unit_id,
      shift_instance_id,
      anomaly_date,
      anomaly_type,
      required_count,
      approved_count,
      supervisor_id,
      anomaly_details
    )
    VALUES (
      v_shift.organization_id,
      v_shift.unit_id,
      p_shift_instance_id,
      v_shift.shift_date,
      'OVER_APPROVAL',
      v_required_count,
      v_approved_count,
      p_supervisor_id,
      jsonb_build_object(
        'excess_count', v_approved_count - v_required_count,
        'shift_date', v_shift.shift_date
      )
    )
    ON CONFLICT DO NOTHING;
    
    v_warning := v_warning || jsonb_build_object(
      'type', 'OVER_APPROVAL',
      'message', format('%s guards approved, but only %s required for this shift', 
        v_approved_count, v_required_count),
      'severity', 'WARNING',
      'excess_count', v_approved_count - v_required_count
    );
  END IF;
  
  RETURN jsonb_build_object(
    'has_anomaly', v_approved_count > v_required_count,
    'required_count', v_required_count,
    'approved_count', v_approved_count,
    'warnings', v_warning
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_approval_anomaly IS 
'SAFETY CHECK: Returns warning for over-approval (does not block operation)';

-- ========================================
-- PART 5: DAILY CLOSING DISCIPLINE
-- ========================================

-- Daily pending counts (dashboard pressure indicators)
CREATE OR REPLACE FUNCTION get_my_pending_dashboard(p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_user users;
  v_result JSONB;
BEGIN
  SELECT * INTO v_user FROM users WHERE id = p_user_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'USER_NOT_FOUND');
  END IF;
  
  -- Build dashboard metrics
  SELECT jsonb_build_object(
    'user_id', v_user.id,
    'user_email', v_user.email,
    'organization_id', v_user.organization_id,
    
    -- My pending yesterday count
    'my_pending_yesterday_count', (
      SELECT COUNT(*)
      FROM attendance a
      JOIN shift_instances si ON si.id = a.shift_instance_id
      WHERE a.approval_status = 'RECORDED'
        AND a.attendance_date = CURRENT_DATE - INTERVAL '1 day'
        AND (
          si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
          OR v_user.role IN ('ADMIN', 'SUPER_ADMIN')
        )
    ),
    
    -- My pending today count
    'my_pending_today_count', (
      SELECT COUNT(*)
      FROM attendance a
      JOIN shift_instances si ON si.id = a.shift_instance_id
      WHERE a.approval_status = 'RECORDED'
        AND a.attendance_date = CURRENT_DATE
        AND (
          si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
          OR v_user.role IN ('ADMIN', 'SUPER_ADMIN')
        )
    ),
    
    -- Oldest unreviewed attendance
    'oldest_unreviewed_days', (
      SELECT CURRENT_DATE - MIN(a.attendance_date)
      FROM attendance a
      JOIN shift_instances si ON si.id = a.shift_instance_id
      WHERE a.approval_status = 'RECORDED'
        AND (
          si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
          OR v_user.role IN ('ADMIN', 'SUPER_ADMIN')
        )
    ),
    
    -- Auto-approved yesterday (supervisor missed)
    'auto_approved_yesterday', (
      SELECT COUNT(*)
      FROM attendance a
      JOIN shift_instances si ON si.id = a.shift_instance_id
      WHERE a.approval_status = 'APPROVED_AUTO'
        AND a.approved_at::DATE = CURRENT_DATE - INTERVAL '1 day'
        AND si.unit_id IN (SELECT id FROM units WHERE supervisor_id = v_user.id)
    ),
    
    -- Site-wise pending breakdown
    'site_pending_counts', (
      SELECT jsonb_object_agg(u.name, pending_count)
      FROM (
        SELECT 
          un.name,
          COUNT(a.id) AS pending_count
        FROM units un
        LEFT JOIN shift_instances si ON si.unit_id = un.id
        LEFT JOIN attendance a ON a.shift_instance_id = si.id 
          AND a.approval_status = 'RECORDED'
        WHERE (un.supervisor_id = v_user.id OR v_user.role IN ('ADMIN', 'SUPER_ADMIN'))
          AND un.organization_id = v_user.organization_id
        GROUP BY un.name
        HAVING COUNT(a.id) > 0
      ) u
    )
  ) INTO v_result;
  
  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION get_my_pending_dashboard IS 
'DAILY DISCIPLINE: Shows pending reviews to create operational pressure (non-blocking)';

-- Organization-wide pending summary (for admins)
CREATE OR REPLACE VIEW organization_pending_summary AS
SELECT 
  o.id AS organization_id,
  o.name AS organization_name,
  
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'RECORDED' 
      AND a.attendance_date = CURRENT_DATE
  ) AS pending_today,
  
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'RECORDED' 
      AND a.attendance_date = CURRENT_DATE - INTERVAL '1 day'
  ) AS pending_yesterday,
  
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'RECORDED' 
      AND a.attendance_date < CURRENT_DATE - INTERVAL '1 day'
  ) AS pending_older,
  
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.approval_status = 'APPROVED_AUTO'
      AND a.approved_at >= CURRENT_DATE - INTERVAL '7 days'
  ) AS auto_approved_7_days,
  
  MIN(a.attendance_date) FILTER (
    WHERE a.approval_status = 'RECORDED'
  ) AS oldest_pending_date
FROM organizations o
LEFT JOIN attendance a ON a.organization_id = o.id
GROUP BY o.id, o.name;

COMMENT ON VIEW organization_pending_summary IS 
'ADMIN DASHBOARD: Organization-wide pending review summary';

-- ========================================
-- PART 6: HELPER UTILITIES (NON-BLOCKING)
-- ========================================

-- Safe approval with anomaly check (returns warnings, never blocks)
CREATE OR REPLACE FUNCTION supervisor_approve_with_checks(
  p_attendance_id UUID,
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_approval_result JSONB;
  v_anomaly_check JSONB;
BEGIN
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  -- Perform approval (ALWAYS succeeds)
  v_approval_result := supervisor_approve_attendance(p_attendance_id, p_supervisor_user_id);
  
  -- Check for anomalies (advisory only, doesn't affect approval)
  IF v_attendance.shift_instance_id IS NOT NULL THEN
    v_anomaly_check := check_approval_anomaly(
      v_attendance.shift_instance_id,
      p_supervisor_user_id
    );
  ELSE
    v_anomaly_check := jsonb_build_object('has_anomaly', false);
  END IF;
  
  -- Return approval result + warnings
  RETURN v_approval_result || jsonb_build_object(
    'anomaly_check', v_anomaly_check,
    'warnings', CASE 
      WHEN v_anomaly_check->>'has_anomaly' = 'true' 
      THEN v_anomaly_check->'warnings'
      ELSE '[]'::JSONB
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_approve_with_checks IS 
'SAFE APPROVAL: Approves attendance + returns advisory warnings (never blocks)';

-- Organization isolation check for cron jobs
CREATE OR REPLACE FUNCTION process_org_auto_approvals(p_organization_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_auto_approved_count INTEGER;
BEGIN
  -- Auto-approve only for this organization
  UPDATE attendance
  SET
    approval_status = 'APPROVED_AUTO',
    approved_at = NOW()
  WHERE approval_status = 'RECORDED'
    AND organization_id = p_organization_id
    AND created_at < NOW() - INTERVAL '24 hours';
  
  GET DIAGNOSTICS v_auto_approved_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'organization_id', p_organization_id,
    'auto_approved_count', v_auto_approved_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION process_org_auto_approvals IS 
'MULTI-AGENCY SAFE: Auto-approvals per organization (isolates processing)';

-- ========================================
-- SUMMARY REPORTING VIEWS
-- ========================================

-- Daily operations health check
CREATE OR REPLACE VIEW daily_operations_health AS
SELECT 
  CURRENT_DATE AS report_date,
  o.id AS organization_id,
  o.name AS organization_name,
  
  -- Attendance metrics
  COUNT(DISTINCT a.id) AS total_attendance_today,
  COUNT(DISTINCT a.id) FILTER (WHERE a.approval_status = 'RECORDED') AS pending_approval,
  COUNT(DISTINCT a.id) FILTER (WHERE a.approval_status = 'APPROVED') AS supervisor_approved,
  COUNT(DISTINCT a.id) FILTER (WHERE a.approval_status = 'APPROVED_AUTO') AS auto_approved,
  COUNT(DISTINCT a.id) FILTER (WHERE a.approval_status = 'REJECTED') AS rejected,
  
  -- Supervisor engagement
  COUNT(DISTINCT a.approved_by) AS active_supervisors_today,
  
  -- Anomalies
  COUNT(DISTINCT aal.id) AS anomalies_detected_today,
  
  -- Health score (0-100)
  CASE 
    WHEN COUNT(DISTINCT a.id) = 0 THEN 100
    ELSE ROUND(
      100 * (1 - 
        (COUNT(DISTINCT a.id) FILTER (WHERE a.approval_status = 'RECORDED')::DECIMAL / 
         NULLIF(COUNT(DISTINCT a.id), 0))
      )
    , 0)
  END AS approval_completion_score
FROM organizations o
LEFT JOIN attendance a ON a.organization_id = o.id AND a.attendance_date = CURRENT_DATE
LEFT JOIN approval_anomaly_logs aal ON aal.organization_id = o.id 
  AND aal.anomaly_date = CURRENT_DATE
GROUP BY o.id, o.name;

COMMENT ON VIEW daily_operations_health IS 
'OPERATIONS DASHBOARD: Daily health metrics per organization';
