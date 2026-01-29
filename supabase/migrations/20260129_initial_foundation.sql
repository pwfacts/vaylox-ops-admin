-- Migration: Initial Foundation Schema
-- Created: 2026-01-29
-- Description: Sets up the core tables for companies, users, guards, units, and areas with SaaS-ready company_id.

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- BLOCK 0 & 1: Foundation
-- Fixed DEFAULT_COMPANY_ID: c0a80101-b632-4e6a-9818-1d2f9d5e3f4b

-- 1. Companies Table
CREATE TABLE IF NOT EXISTS companies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Insert Default Company
INSERT INTO companies (id, name)
VALUES ('c0a80101-b632-4e6a-9818-1d2f9d5e3f4b', 'JDS Management Default')
ON CONFLICT (id) DO NOTHING;

-- 2. Areas Table
CREATE TABLE IF NOT EXISTS areas (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
    name TEXT NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Units Table
CREATE TABLE IF NOT EXISTS units (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
    area_id UUID REFERENCES areas(id),
    name TEXT NOT NULL,
    code TEXT UNIQUE,
    address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Users Table (Profile table linked to Auth)
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
    full_name TEXT NOT NULL,
    email TEXT UNIQUE,
    role TEXT NOT NULL CHECK (role IN ('admin', 'field_officer', 'supervisor', 'accountant', 'guard')),
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Guards Table (Based on PRD v2.1 with company_id)
CREATE TABLE IF NOT EXISTS guards (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
    guard_code TEXT NOT NULL UNIQUE,
    
    -- Personal Information
    full_name TEXT NOT NULL,
    phone TEXT NOT NULL UNIQUE,
    emergency_contact TEXT NOT NULL,
    aadhar_number TEXT NOT NULL UNIQUE,
    pan_number TEXT UNIQUE,
    date_of_birth DATE NOT NULL,
    
    -- Documents (ImageKit URLs)
    aadhar_front_url TEXT,
    aadhar_back_url TEXT,
    pan_card_url TEXT,
    photo_url TEXT,
    police_verification_url TEXT,
    
    -- Employment Details
    assigned_unit_id UUID NOT NULL REFERENCES units(id),
    assigned_unit_code TEXT NOT NULL,
    duty_shift TEXT NOT NULL CHECK (duty_shift IN ('day', 'night', 'both')),
    designation TEXT NOT NULL DEFAULT 'security_guard',
    
    -- Salary Configuration
    basic_salary DECIMAL(10, 2) NOT NULL,
    ot_rate_per_hour DECIMAL(10, 2),
    ot_calculation_method TEXT DEFAULT 'hourly',
    
    -- Bank Details
    bank_name TEXT,
    account_number TEXT,
    ifsc_code TEXT,
    
    -- Face Recognition
    face_encoding TEXT,
    
    -- Status
    status TEXT NOT NULL DEFAULT 'active',
    
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_areas_company_id ON areas(company_id);
CREATE INDEX IF NOT EXISTS idx_units_company_id ON units(company_id);
CREATE INDEX IF NOT EXISTS idx_users_company_id ON users(company_id);
CREATE INDEX IF NOT EXISTS idx_guards_company_id ON guards(company_id);
CREATE INDEX IF NOT EXISTS idx_guards_unit_id ON guards(assigned_unit_id);
