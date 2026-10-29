-- ============================================
-- AHDMS Database Schema
-- Automated Hospital Discharge Management System
-- Butuan Medical Center
-- ============================================

-- Required for password hashing. Supabase installs extensions into the
-- `extensions` schema by default, not `public` -- the SECURITY DEFINER
-- functions in ahdms_auth_functions.sql set search_path accordingly.
create extension if not exists pgcrypto with schema extensions;

-- ============================================
-- 0. DROP EXISTING TABLES (reverse dependency order)
-- WARNING: this deletes existing data in these tables.
-- ============================================
drop table if exists billing cascade;
drop table if exists chart_entries cascade;
drop table if exists discharge_requests cascade;
drop table if exists patients cascade;
drop table if exists credentials cascade;
drop table if exists officers cascade;

-- ============================================
-- 1. OFFICERS
-- Single table for all staff roles, distinguished by `role`
-- ============================================
create table officers (
    officer_id      bigint generated always as identity primary key,
    full_name       text not null,
    role            text not null check (role in ('nurse', 'doctor', 'billing', 'admin')),
    duty_status     text not null default 'off_duty' check (duty_status in ('on_duty', 'off_duty')),
    created_at      timestamptz not null default now()
);

-- ============================================
-- 2. CREDENTIALS
-- 1-to-1 with officers. officers = parent, credentials references it.
-- ============================================
create table credentials (
    credential_id   bigint generated always as identity primary key,
    officer_id      bigint not null unique references officers(officer_id) on delete cascade,
    email           text not null unique,
    password        text not null, -- store hashed via pgcrypto (crypt())
    created_at      timestamptz not null default now()
);

-- ============================================
-- 3. PATIENTS
-- ============================================
create table patients (
    patient_id              bigint generated always as identity primary key,
    full_name               text not null,
    date_of_birth           date,
    age                     smallint,
    contact_number          text,
    emergency_contact       text,
    admission_date          date not null default current_date,
    discharge_date          timestamptz,
    room_number             smallint,
    philhealth_no           text,
    attending_officer_id    bigint references officers(officer_id),
    created_at              timestamptz not null default now()
);

-- ============================================
-- 4. DISCHARGE_REQUESTS
-- pending -> approved (doctor) -> completed (billing cleared), or rejected.
-- approved_by records the doctor who approved or rejected.
-- ============================================
create table discharge_requests (
    request_id      bigint generated always as identity primary key,
    patient_id      bigint not null references patients(patient_id) on delete cascade,
    requested_by    bigint not null references officers(officer_id),
    approved_by     bigint references officers(officer_id),
    status          text not null default 'pending'
                     check (status in ('pending', 'approved', 'completed', 'rejected')),
    "timestamp"     timestamptz not null default now()
);

-- ============================================
-- 5. CHART_ENTRIES
-- The patient chart. Nurses record vital signs, nursing notes,
-- medication and other records; doctors add their advice/orders.
-- `details` holds the type's fields (see app/components/PatientChart.vue).
-- ============================================
create table chart_entries (
    entry_id        bigint generated always as identity primary key,
    patient_id      bigint not null references patients(patient_id) on delete cascade,
    recorded_by     bigint not null references officers(officer_id),
    entry_type      text not null
                     check (entry_type in ('vital_signs', 'nursing_note', 'medication', 'other', 'doctor_order')),
    details         jsonb not null,
    created_at      timestamptz not null default now()
);

-- ============================================
-- 6. BILLING
-- One cleared bill per discharge request, written by clear_billing().
-- ============================================
create table billing (
    billing_id              bigint generated always as identity primary key,
    discharge_request_id    bigint not null unique references discharge_requests(request_id) on delete cascade,
    patient_id              bigint not null references patients(patient_id),
    handled_by              bigint references officers(officer_id),
    charges                 jsonb not null, -- itemized expenses, e.g. {"room": 1500}
    total_amount            numeric(12,2) not null,
    philhealth_deduction    numeric(12,2) not null default 0,
    created_at              timestamptz not null default now()
);

-- ============================================
-- INDEXES (for FK lookups & common filters)
-- ============================================
create index idx_credentials_officer_id on credentials(officer_id);
create index idx_patients_attending_officer_id on patients(attending_officer_id);
create index idx_discharge_requests_patient_id on discharge_requests(patient_id);
create index idx_discharge_requests_requested_by on discharge_requests(requested_by);
create index idx_discharge_requests_approved_by on discharge_requests(approved_by);
create index idx_discharge_requests_status on discharge_requests(status);
create index idx_chart_entries_patient_id on chart_entries(patient_id);
create index idx_billing_patient_id on billing(patient_id);
create index idx_officers_role_duty on officers(role, duty_status);

-- ============================================
-- RLS: enabled with no policies on purpose. There is no Supabase Auth
-- session in this app (see supabase/ahdms_auth_functions.sql) — the only
-- way in for the anon role is through the SECURITY DEFINER RPC functions
-- in ahdms_auth_functions.sql and ahdms_core_functions.sql.
-- ============================================
alter table officers enable row level security;
alter table credentials enable row level security;
alter table patients enable row level security;
alter table discharge_requests enable row level security;
alter table chart_entries enable row level security;
alter table billing enable row level security;
