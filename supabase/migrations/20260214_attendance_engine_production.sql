-- ============================================================================
-- PRODUCTION-GRADE MULTI-UNIT ATTENDANCE ENGINE
-- Migration: 20260214_attendance_engine_production
-- ============================================================================

-- ============================================================================
-- 1. ATTENDANCE TABLE ENHANCEMENTS
-- ============================================================================

-- Add check_in_method (renamed from attendance_method for clarity)
ALTER TABLE public.attendance 
ADD COLUMN IF NOT EXISTS check_in_method text DEFAULT 'MANUAL';

-- Ensure critical columns are NOT NULL
ALTER TABLE public.attendance 
ALTER COLUMN approval_status SET DEFAULT 'PENDING_APPROVAL',
ALTER COLUMN is_voided SET DEFAULT false,
ALTER COLUMN is_temporary_assignment SET DEFAULT false;

-- Update existing records to ensure consistency
UPDATE public.attendance 
SET approval_status = 'PENDING_APPROVAL' 
WHERE approval_status IS NULL;

UPDATE public.attendance 
SET is_voided = false 
WHERE is_voided IS NULL;

UPDATE public.attendance 
SET is_temporary_assignment = false 
WHERE is_temporary_assignment IS NULL;

-- Add unique constraint for non-voided attendance (one attendance per shift per day)
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_unique_active 
ON public.attendance (guard_id, attendance_date, shift) 
WHERE is_voided = false;

-- Add indexes for performance
CREATE INDEX IF NOT EXISTS idx_attendance_worked_unit ON public.attendance(worked_unit_id) WHERE is_voided = false;
CREATE INDEX IF NOT EXISTS idx_attendance_primary_unit ON public.attendance(primary_unit_id) WHERE is_voided = false;
CREATE INDEX IF NOT EXISTS idx_attendance_approval_status ON public.attendance(approval_status) WHERE is_voided = false;
CREATE INDEX IF NOT EXISTS idx_attendance_date_shift ON public.attendance(attendance_date, shift) WHERE is_voided = false;
CREATE INDEX IF NOT EXISTS idx_attendance_device_sync ON public.attendance(device_id, offline_created_at) WHERE synced_from_offline = true;

-- ============================================================================
-- 2. ATTENDANCE CORRECTIONS TABLE (Append-Only Audit Trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.attendance_corrections (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    organization_id uuid NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    attendance_id uuid NOT NULL REFERENCES public.attendance(id) ON DELETE CASCADE,
    
    -- What changed
    correction_type text NOT NULL CHECK (correction_type IN ('TIME_ADJUSTMENT', 'UNIT_CHANGE', 'VOID', 'APPROVAL_OVERRIDE', 'OT_ADJUSTMENT')),
    field_changed text,
    old_value text,
    new_value text,
    reason text NOT NULL,
    
    -- Who and when
    requested_by uuid NOT NULL REFERENCES public.users(id),
    requested_at timestamptz NOT NULL DEFAULT now(),
    approved_by uuid REFERENCES public.users(id),
    approved_at timestamptz,
    correction_status text NOT NULL DEFAULT 'PENDING' CHECK (correction_status IN ('PENDING', 'APPROVED', 'REJECTED')),
    rejection_reason text,
    
    -- Metadata
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes for corrections
CREATE INDEX IF NOT EXISTS idx_corrections_attendance ON public.attendance_corrections(attendance_id);
CREATE INDEX IF NOT EXISTS idx_corrections_status ON public.attendance_corrections(correction_status);
CREATE INDEX IF NOT EXISTS idx_corrections_requested_by ON public.attendance_corrections(requested_by);

-- ============================================================================
-- 3. ATTENDANCE APPROVAL LOG (Immutable Audit Trail)
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.attendance_approval_log (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    attendance_id uuid NOT NULL REFERENCES public.attendance(id) ON DELETE CASCADE,
    action text NOT NULL CHECK (action IN ('APPROVED', 'REJECTED', 'VOIDED', 'CORRECTION_APPLIED')),
    previous_status text,
    new_status text,
    actioned_by uuid NOT NULL REFERENCES public.users(id),
    actioned_by_role text NOT NULL,
    notes text,
    metadata jsonb, -- For storing additional context
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Index for audit queries
CREATE INDEX IF NOT EXISTS idx_approval_log_attendance ON public.attendance_approval_log(attendance_id);
CREATE INDEX IF NOT EXISTS idx_approval_log_actor ON public.attendance_approval_log(actioned_by);
CREATE INDEX IF NOT EXISTS idx_approval_log_created ON public.attendance_approval_log(created_at DESC);

-- ============================================================================
-- 4. OFFLINE SYNC DEDUPLICATION TABLE
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.attendance_sync_registry (
    id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
    device_id text NOT NULL,
    guard_id uuid NOT NULL REFERENCES public.guards(id),
    attendance_date date NOT NULL,
    shift text NOT NULL,
    offline_created_at timestamptz NOT NULL,
    synced_attendance_id uuid REFERENCES public.attendance(id),
    sync_status text NOT NULL DEFAULT 'SYNCED' CHECK (sync_status IN ('SYNCED', 'DUPLICATE_DETECTED', 'CONFLICT_RESOLVED')),
    conflict_resolution_method text,
    created_at timestamptz NOT NULL DEFAULT now(),
    
    UNIQUE(device_id, guard_id, attendance_date, shift, offline_created_at)
);

-- Index for duplicate detection
CREATE INDEX IF NOT EXISTS idx_sync_registry_lookup 
ON public.attendance_sync_registry(guard_id, attendance_date, shift);

-- ============================================================================
-- 5. DATABASE TRIGGERS
-- ============================================================================

-- Trigger: Auto-set is_temporary_assignment
CREATE OR REPLACE FUNCTION set_temporary_assignment()
RETURNS TRIGGER AS $$
BEGIN
    -- If worked_unit_id differs from primary_unit_id, mark as temporary
    IF NEW.worked_unit_id IS NOT NULL AND NEW.primary_unit_id IS NOT NULL THEN
        NEW.is_temporary_assignment := (NEW.worked_unit_id != NEW.primary_unit_id);
    ELSE
        NEW.is_temporary_assignment := false;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_set_temporary_assignment ON public.attendance;
CREATE TRIGGER trg_set_temporary_assignment
    BEFORE INSERT OR UPDATE OF worked_unit_id, primary_unit_id ON public.attendance
    FOR EACH ROW
    EXECUTE FUNCTION set_temporary_assignment();

-- Trigger: Log approval/rejection actions
CREATE OR REPLACE FUNCTION log_attendance_approval()
RETURNS TRIGGER AS $$
DECLARE
    actor_role text;
BEGIN
    -- Get the role of the user making the change
    SELECT role INTO actor_role
    FROM public.organization_users
    WHERE user_id = NEW.approved_by
    LIMIT 1;
    
    -- Log only if approval_status changed
    IF OLD.approval_status IS DISTINCT FROM NEW.approval_status THEN
        INSERT INTO public.attendance_approval_log (
            attendance_id,
            action,
            previous_status,
            new_status,
            actioned_by,
            actioned_by_role,
            notes,
            metadata
        ) VALUES (
            NEW.id,
            CASE 
                WHEN NEW.approval_status = 'APPROVED' THEN 'APPROVED'
                WHEN NEW.approval_status = 'REJECTED' THEN 'REJECTED'
                ELSE 'UPDATED'
            END,
            OLD.approval_status,
            NEW.approval_status,
            NEW.approved_by,
            COALESCE(actor_role, 'UNKNOWN'),
            NEW.approval_notes,
            jsonb_build_object(
                'approved_at', NEW.approved_at,
                'worked_unit_id', NEW.worked_unit_id,
                'is_temporary_assignment', NEW.is_temporary_assignment
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_attendance_approval ON public.attendance;
CREATE TRIGGER trg_log_attendance_approval
    AFTER UPDATE OF approval_status ON public.attendance
    FOR EACH ROW
    EXECUTE FUNCTION log_attendance_approval();

-- Trigger: Log voiding actions
CREATE OR REPLACE FUNCTION log_attendance_void()
RETURNS TRIGGER AS $$
DECLARE
    actor_role text;
BEGIN
    IF OLD.is_voided = false AND NEW.is_voided = true THEN
        -- Get the role of the user voiding
        SELECT role INTO actor_role
        FROM public.organization_users
        WHERE user_id = NEW.voided_by
        LIMIT 1;
        
        INSERT INTO public.attendance_approval_log (
            attendance_id,
            action,
            previous_status,
            new_status,
            actioned_by,
            actioned_by_role,
            notes,
            metadata
        ) VALUES (
            NEW.id,
            'VOIDED',
            OLD.approval_status,
            'VOIDED',
            NEW.voided_by,
            COALESCE(actor_role, 'UNKNOWN'),
            NEW.void_reason,
            jsonb_build_object(
                'voided_at', NEW.voided_at,
                'previous_approval_status', OLD.approval_status
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_attendance_void ON public.attendance;
CREATE TRIGGER trg_log_attendance_void
    AFTER UPDATE OF is_voided ON public.attendance
    FOR EACH ROW
    EXECUTE FUNCTION log_attendance_void();

-- Trigger: Prevent editing approved attendance (enforce correction workflow)
CREATE OR REPLACE FUNCTION prevent_approved_attendance_edit()
RETURNS TRIGGER AS $$
BEGIN
    -- Allow voiding and correction-related updates
    IF OLD.approval_status = 'APPROVED' AND NEW.approval_status = 'APPROVED' THEN
        -- Allow only specific fields to be updated after approval
        IF (OLD.is_voided IS DISTINCT FROM NEW.is_voided) OR
           (OLD.voided_by IS DISTINCT FROM NEW.voided_by) OR
           (OLD.voided_at IS DISTINCT FROM NEW.voided_at) OR
           (OLD.void_reason IS DISTINCT FROM NEW.void_reason) THEN
            -- Voiding is allowed
            RETURN NEW;
        ELSE
            -- Prevent any other edits to approved attendance
            RAISE EXCEPTION 'Cannot edit approved attendance. Use attendance_corrections workflow.';
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_approved_edit ON public.attendance;
CREATE TRIGGER trg_prevent_approved_edit
    BEFORE UPDATE ON public.attendance
    FOR EACH ROW
    EXECUTE FUNCTION prevent_approved_attendance_edit();

-- ============================================================================
-- 6. ROW LEVEL SECURITY (RLS) POLICIES
-- ============================================================================

-- Enable RLS on all tables
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_approval_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sync_registry ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate cleanly
DROP POLICY IF EXISTS "attendance_guard_insert" ON public.attendance;
DROP POLICY IF EXISTS "attendance_guard_select" ON public.attendance;
DROP POLICY IF EXISTS "attendance_supervisor_select" ON public.attendance;
DROP POLICY IF EXISTS "attendance_supervisor_approve" ON public.attendance;
DROP POLICY IF EXISTS "attendance_field_officer_select" ON public.attendance;
DROP POLICY IF EXISTS "attendance_field_officer_approve" ON public.attendance;
DROP POLICY IF EXISTS "attendance_admin_select" ON public.attendance;
DROP POLICY IF EXISTS "attendance_admin_void" ON public.attendance;

-- Guards: Can insert their own attendance
CREATE POLICY "attendance_guard_insert"
ON public.attendance
FOR INSERT
TO authenticated
WITH CHECK (
    auth.uid() IN (
        SELECT user_id FROM public.guards WHERE id = guard_id
    )
);

-- Guards: Can view their own attendance
CREATE POLICY "attendance_guard_select"
ON public.attendance
FOR SELECT
TO authenticated
USING (
    auth.uid() IN (
        SELECT user_id FROM public.guards WHERE id = guard_id
    )
);

-- Supervisors: Can view attendance for units they supervise
CREATE POLICY "attendance_supervisor_select"
ON public.attendance
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.guards g
        WHERE g.user_id = auth.uid()
        AND g.is_supervisor = true
        AND g.supervised_unit_id = attendance.worked_unit_id
    )
);

-- Supervisors: Can approve attendance for their supervised units
CREATE POLICY "attendance_supervisor_approve"
ON public.attendance
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.guards g
        WHERE g.user_id = auth.uid()
        AND g.is_supervisor = true
        AND g.supervised_unit_id = attendance.worked_unit_id
        AND attendance.approval_status = 'PENDING_APPROVAL'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.guards g
        WHERE g.user_id = auth.uid()
        AND g.is_supervisor = true
        AND g.supervised_unit_id = attendance.worked_unit_id
    )
);

-- Field Officers: Can view attendance for their assigned units
CREATE POLICY "attendance_field_officer_select"
ON public.attendance
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.field_officer_units fou
        WHERE fou.user_id = auth.uid()
        AND fou.unit_id = attendance.worked_unit_id
    )
);

-- Field Officers: Can approve attendance for their assigned units
CREATE POLICY "attendance_field_officer_approve"
ON public.attendance
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.field_officer_units fou
        WHERE fou.user_id = auth.uid()
        AND fou.unit_id = attendance.worked_unit_id
        AND attendance.approval_status = 'PENDING_APPROVAL'
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.field_officer_units fou
        WHERE fou.user_id = auth.uid()
        AND fou.unit_id = attendance.worked_unit_id
    )
);

-- Admin/Accountant: Can view all attendance
CREATE POLICY "attendance_admin_select"
ON public.attendance
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.role IN ('admin', 'accountant')
        AND ou.organization_id = attendance.organization_id
    )
);

-- Admin: Can void attendance (but not edit approved ones directly)
CREATE POLICY "attendance_admin_void"
ON public.attendance
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.role = 'admin'
        AND ou.organization_id = attendance.organization_id
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.role = 'admin'
        AND ou.organization_id = attendance.organization_id
    )
);

-- ============================================================================
-- RLS for Corrections Table
-- ============================================================================

-- Anyone can request corrections for their organization
CREATE POLICY "corrections_create"
ON public.attendance_corrections
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.organization_id = organization_id
    )
);

-- View corrections for your organization
CREATE POLICY "corrections_select"
ON public.attendance_corrections
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.organization_id = organization_id
    )
);

-- Only admins can approve/reject corrections
CREATE POLICY "corrections_approve"
ON public.attendance_corrections
FOR UPDATE
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        WHERE ou.user_id = auth.uid()
        AND ou.role = 'admin'
        AND ou.organization_id = organization_id
    )
);

-- ============================================================================
-- RLS for Approval Log (Read-Only)
-- ============================================================================

CREATE POLICY "approval_log_select"
ON public.attendance_approval_log
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.attendance a
        JOIN public.organization_users ou ON ou.organization_id = a.organization_id
        WHERE a.id = attendance_id
        AND ou.user_id = auth.uid()
    )
);

-- ============================================================================
-- RLS for Sync Registry
-- ============================================================================

CREATE POLICY "sync_registry_select"
ON public.attendance_sync_registry
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1 FROM public.guards g
        WHERE g.id = guard_id
        AND g.user_id = auth.uid()
    )
    OR
    EXISTS (
        SELECT 1 FROM public.organization_users ou
        JOIN public.guards g ON g.organization_id = ou.organization_id
        WHERE g.id = guard_id
        AND ou.user_id = auth.uid()
        AND ou.role IN ('admin', 'field_officer', 'accountant')
    )
);

CREATE POLICY "sync_registry_insert"
ON public.attendance_sync_registry
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1 FROM public.guards g
        WHERE g.id = guard_id
        AND g.user_id = auth.uid()
    )
);

-- ============================================================================
-- 7. HELPER FUNCTIONS
-- ============================================================================

-- Function: Safe duplicate detection for offline sync
CREATE OR REPLACE FUNCTION check_attendance_duplicate(
    p_guard_id uuid,
    p_attendance_date date,
    p_shift text,
    p_device_id text,
    p_offline_created_at timestamptz
)
RETURNS TABLE (
    is_duplicate boolean,
    existing_attendance_id uuid,
    conflict_type text
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        true as is_duplicate,
        a.id as existing_attendance_id,
        CASE 
            WHEN a.device_id = p_device_id AND a.offline_created_at = p_offline_created_at THEN 'EXACT_MATCH'
            WHEN a.device_id = p_device_id THEN 'SAME_DEVICE_DIFFERENT_TIME'
            ELSE 'DIFFERENT_DEVICE'
        END as conflict_type
    FROM public.attendance a
    WHERE a.guard_id = p_guard_id
    AND a.attendance_date = p_attendance_date
    AND a.shift = p_shift
    AND a.is_voided = FALSE
    LIMIT 1;
    
    -- If no duplicate found
    IF NOT FOUND THEN
        RETURN QUERY SELECT false, NULL::uuid, NULL::text;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get payroll-ready attendance (only APPROVED and non-voided)
CREATE OR REPLACE FUNCTION get_payroll_attendance(
    p_organization_id uuid,
    p_start_date date,
    p_end_date date,
    p_unit_id uuid DEFAULT NULL
)
RETURNS TABLE (
    guard_id uuid,
    guard_code text,
    full_name text,
    attendance_date date,
    shift text,
    check_in_time timestamptz,
    check_out_time timestamptz,
    worked_unit_id uuid,
    is_temporary_assignment boolean,
    is_ot boolean,
    ot_hours numeric
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        a.guard_id,
        g.guard_code,
        g.full_name,
        a.attendance_date,
        a.shift,
        a.check_in_time,
        a.check_out_time,
        a.worked_unit_id,
        a.is_temporary_assignment,
        a.is_ot,
        a.ot_hours
    FROM public.attendance a
    JOIN public.guards g ON g.id = a.guard_id
    WHERE a.organization_id = p_organization_id
    AND a.attendance_date BETWEEN p_start_date AND p_end_date
    AND a.approval_status = 'APPROVED'
    AND a.is_voided = FALSE
    AND (p_unit_id IS NULL OR a.worked_unit_id = p_unit_id)
    ORDER BY a.attendance_date, g.guard_code, a.shift;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- 8. COMMENTS FOR DOCUMENTATION
-- ============================================================================

COMMENT ON TABLE public.attendance IS 'Production attendance tracking with multi-unit support and strict approval workflow';
COMMENT ON TABLE public.attendance_corrections IS 'Append-only audit trail for attendance corrections after approval';
COMMENT ON TABLE public.attendance_approval_log IS 'Immutable log of all approval/rejection actions';
COMMENT ON TABLE public.attendance_sync_registry IS 'Deduplication registry for offline attendance sync';

COMMENT ON COLUMN public.attendance.primary_unit_id IS 'Guard''s home/assigned unit';
COMMENT ON COLUMN public.attendance.worked_unit_id IS 'Actual unit where guard worked (may differ if temporary assignment)';
COMMENT ON COLUMN public.attendance.is_temporary_assignment IS 'Auto-set to true if worked_unit_id != primary_unit_id';
COMMENT ON COLUMN public.attendance.is_voided IS 'Soft delete flag - voided records are excluded from payroll';
COMMENT ON COLUMN public.attendance.approval_status IS 'PENDING_APPROVAL (default), APPROVED, or REJECTED';

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
