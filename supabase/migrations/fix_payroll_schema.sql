-- FIX MISSING PAYROLL SCHEMA ELEMENTS
-- Prerequisites for calculate_payroll functions

-- 1. Create payroll_work_units table
CREATE TABLE IF NOT EXISTS payroll_work_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  present_days INTEGER DEFAULT 0,
  aggregation_status TEXT DEFAULT 'DRAFT',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(payroll_period_id, guard_id)
);

CREATE INDEX IF NOT EXISTS idx_payroll_work_units_period ON payroll_work_units(payroll_period_id);
CREATE INDEX IF NOT EXISTS idx_payroll_work_units_guard ON payroll_work_units(guard_id);

-- 2. Add payroll_period_id to attendance
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS payroll_period_id UUID REFERENCES payroll_periods(id);

CREATE INDEX IF NOT EXISTS idx_attendance_payroll_period ON attendance(payroll_period_id);

-- 3. Add is_retroactive_change to attendance (was missing in view)
ALTER TABLE attendance
ADD COLUMN IF NOT EXISTS is_retroactive_change BOOLEAN DEFAULT false;
