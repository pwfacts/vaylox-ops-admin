-- Payroll settings
CREATE TABLE IF NOT EXISTS payroll_settings (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
  pf_percentage DECIMAL(5, 2) DEFAULT 12.00,
  esic_percentage DECIMAL(5, 2) DEFAULT 0.75,
  professional_tax DECIMAL(10, 2) DEFAULT 200.00,
  lwf_amount DECIMAL(10, 2) DEFAULT 20.00,
  lwf_months INTEGER[] DEFAULT '{2,8}', -- February and August
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id)
);

-- Salary slips with status field
CREATE TABLE IF NOT EXISTS salary_slips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
  year INTEGER NOT NULL,
  
  -- Status field (CRITICAL for immutability)
  status TEXT DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'LOCKED', 'PAID')),
  locked_at TIMESTAMPTZ,
  locked_by UUID REFERENCES users(id),
  paid_at TIMESTAMPTZ,
  
  total_working_days INTEGER NOT NULL,
  present_days INTEGER NOT NULL,
  absent_days INTEGER NOT NULL,
  
  basic_pay DECIMAL(10, 2) NOT NULL,
  ot_pay DECIMAL(10, 2) DEFAULT 0,
  other_allowances DECIMAL(10, 2) DEFAULT 0,
  gross_pay DECIMAL(10, 2) NOT NULL,
  
  pf_deduction DECIMAL(10, 2) DEFAULT 0,
  esic_deduction DECIMAL(10, 2) DEFAULT 0,
  pt_deduction DECIMAL(10, 2) DEFAULT 0,
  lwf_deduction DECIMAL(10, 2) DEFAULT 0,
  advance_deduction DECIMAL(10, 2) DEFAULT 0,
  uniform_deduction DECIMAL(10, 2) DEFAULT 0,
  penalty_deduction DECIMAL(10, 2) DEFAULT 0,
  canteen_deduction DECIMAL(10, 2) DEFAULT 0,
  other_ded1 DECIMAL(10, 2) DEFAULT 0,
  other_ded2 DECIMAL(10, 2) DEFAULT 0,
  total_deductions DECIMAL(10, 2) NOT NULL,
  
  net_pay DECIMAL(10, 2) NOT NULL,
  
  manual_override_by TEXT,
  manual_override_at TIMESTAMPTZ,
  manual_override_note TEXT,
  attendance_suggested_days INTEGER,
  attendance_suggested_ot_days INTEGER,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(guard_id, month, year)
);

CREATE INDEX idx_salary_slips_company ON salary_slips(company_id);
CREATE INDEX idx_salary_slips_status ON salary_slips(status);
