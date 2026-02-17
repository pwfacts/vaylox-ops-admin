-- Attendance audit log (immutable)
CREATE TABLE IF NOT EXISTS attendance_audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  attendance_id UUID NOT NULL REFERENCES attendance(id),
  action TEXT NOT NULL, -- 'CREATED', 'APPROVED', 'REJECTED', 'MODIFIED'
  actor_id UUID NOT NULL REFERENCES users(id),
  actor_role TEXT NOT NULL,
  old_values JSONB,
  new_values JSONB,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_attendance ON attendance_audit_log(attendance_id);
CREATE INDEX idx_audit_created ON attendance_audit_log(created_at DESC);

-- Salary audit log
CREATE TABLE IF NOT EXISTS salary_audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  salary_slip_id UUID NOT NULL,
  action TEXT NOT NULL, -- 'GENERATED', 'LOCKED', 'CORRECTION_REQUESTED', 'CORRECTION_APPLIED'
  actor_id UUID NOT NULL REFERENCES users(id),
  actor_role TEXT NOT NULL,
  old_values JSONB,
  new_values JSONB,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_salary_audit_slip ON salary_audit_log(salary_slip_id);

-- CRITICAL: Database-level audit triggers (cannot be bypassed)
-- Attendance approval/rejection trigger
CREATE OR REPLACE FUNCTION log_attendance_approval()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
    INSERT INTO attendance_audit_log (
      attendance_id,
      action,
      actor_id,
      actor_role,
      old_values,
      new_values,
      notes
    ) VALUES (
      NEW.id,
      CASE 
        WHEN NEW.approval_status = 'APPROVED' THEN 'APPROVED'
        WHEN NEW.approval_status = 'REJECTED' THEN 'REJECTED'
        ELSE 'MODIFIED'
      END,
      NEW.approved_by,
      (SELECT role FROM users WHERE id = NEW.approved_by),
      jsonb_build_object('approval_status', OLD.approval_status),
      jsonb_build_object('approval_status', NEW.approval_status),
      NEW.approval_notes
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER attendance_approval_audit
AFTER UPDATE ON attendance
FOR EACH ROW
WHEN (OLD.approval_status IS DISTINCT FROM NEW.approval_status)
EXECUTE FUNCTION log_attendance_approval();

-- Salary slip status change trigger
CREATE OR REPLACE FUNCTION log_salary_status_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status IS DISTINCT FROM NEW.status THEN
    INSERT INTO salary_audit_log (
      salary_slip_id,
      action,
      actor_id,
      actor_role,
      old_values,
      new_values,
      notes
    ) VALUES (
      NEW.id,
      CASE
        WHEN NEW.status = 'LOCKED' THEN 'LOCKED'
        WHEN NEW.status = 'PAID' THEN 'PAID'
        ELSE 'STATUS_CHANGED'
      END,
      NEW.locked_by,
      (SELECT role FROM users WHERE id = NEW.locked_by),
      jsonb_build_object('status', OLD.status),
      jsonb_build_object('status', NEW.status),
      CASE
        WHEN NEW.status = 'LOCKED' THEN 'Payroll locked for ' || NEW.month || '/' || NEW.year
        WHEN NEW.status = 'PAID' THEN 'Payment processed'
        ELSE NULL
      END
    );
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER salary_status_audit
AFTER UPDATE ON salary_slips
FOR EACH ROW
WHEN (OLD.status IS DISTINCT FROM NEW.status)
EXECUTE FUNCTION log_salary_status_change();
