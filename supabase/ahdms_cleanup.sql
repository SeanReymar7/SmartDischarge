-- ============================================
-- AHDMS Cleanup and Upgrade
-- Brings an existing database up to date. Keeps patient, staff, discharge
-- and billing rows. The only table it removes is the legacy `tasks` table.
-- Safe to run more than once.
--
-- Run this first, then ahdms_auth.sql, then ahdms_functions.sql.
-- This file drops functions the app still uses, and ahdms_functions.sql
-- recreates them, so the app will show errors until all three have run.
--
-- A new, empty database does not need this file.
-- ============================================

-- ============================================
-- 1. NEW COLUMNS
-- Older databases are missing these. A database with no tables yet is skipped.
-- ============================================

-- Each doctor has a field (specialty) the nurse can search by.
-- Doctors registered before this change have no specialty. Set it with:
--   update officers set specialty = 'Oncology'
--   where officer_id = <id> and role = 'doctor';
alter table if exists officers add column if not exists specialty text;

-- The medical abstract prints the doctor's license number.
-- Doctors registered before this change have none. Set it with:
--   update officers set license_number = '<license no.>'
--   where officer_id = <id> and role = 'doctor';
alter table if exists officers add column if not exists license_number text;

-- The medical abstract prints the patient's sex and address. For patients
-- registered before this change, a nurse can fill these in under Edit.
alter table if exists patients
    add column if not exists sex text check (sex in ('Male', 'Female')),
    add column if not exists address text;

-- The nurse chooses the doctor for a discharge request.
-- Requests filed before this change have no assigned doctor. They stay open
-- to every doctor, so none get stuck.
do $$
begin
    if to_regclass('public.discharge_requests') is not null
       and to_regclass('public.officers') is not null then
        alter table discharge_requests
            add column if not exists assigned_doctor_id bigint references officers(officer_id);

        create index if not exists idx_discharge_requests_assigned_doctor_id
            on discharge_requests(assigned_doctor_id);
    end if;

    -- Chart entries can be corrected, and each earlier version is kept.
    if to_regclass('public.chart_entries') is not null
       and to_regclass('public.officers') is not null then
        alter table chart_entries
            add column if not exists updated_by bigint references officers(officer_id),
            add column if not exists updated_at timestamptz,
            add column if not exists edit_history jsonb not null default '[]'::jsonb;
    end if;

    -- The doctor's clinical summary.
    if to_regclass('public.patients') is not null
       and to_regclass('public.officers') is not null then
        create table if not exists medical_abstracts (
            abstract_id     bigint generated always as identity primary key,
            patient_id      bigint not null references patients(patient_id) on delete cascade,
            doctor_id       bigint not null references officers(officer_id),
            sections        jsonb not null,
            created_at      timestamptz not null default now(),
            updated_at      timestamptz,
            edit_history    jsonb not null default '[]'::jsonb
        );

        create index if not exists idx_medical_abstracts_patient_id
            on medical_abstracts(patient_id);

        alter table medical_abstracts enable row level security;
    end if;
end;
$$;

-- ============================================
-- 2. LEGACY FUNCTIONS
-- Old functions stay in Postgres even after their .sql files are deleted
-- from the repo. Some share a name with a function in ahdms_functions.sql
-- but return a different shape, and `create or replace function` cannot
-- change a return type, so the old versions have to be dropped first.
-- ============================================

drop function if exists list_all_discharge_requests();
drop function if exists update_discharge_request_status_by_doctor(int8, text, int8);
drop function if exists list_all_patients();
drop function if exists create_patient(text, date, text, int8, int8, date, text, text, int8, timestamptz);
drop function if exists update_patient(int8, text, date, text, int8, date, text, text, int8, timestamptz, int8);
drop function if exists list_patients_by_officer(int8);
drop function if exists create_discharge_request(int8, int8);
drop function if exists update_discharge_request_status(int8, text, int8);
drop function if exists list_discharge_requests_by_officer(int8);
drop function if exists list_tasks_by_officer(int8);
drop function if exists update_task_status(int8, text, int8);
drop function if exists get_officer_name(int8);
drop function if exists register_users(text, text);
drop function if exists register_staff(text, text, text, text, int8);
drop function if exists list_officers_with_duty();
drop function if exists set_officer_duty_status(int8, text, int8);
drop function if exists login_administrator(text, text);
drop function if exists login_administrator(text, text, text);
drop function if exists register_administrator(text, text);

-- Removed with the task-assignment workflow (replaced by the patient chart
-- and the nurse -> doctor -> billing flow in ahdms_functions.sql).
drop function if exists get_required_role(text);
drop function if exists auto_assign_officer(text);
drop function if exists complete_task(bigint);
drop function if exists list_tasks_for_officer(bigint);
drop function if exists list_tasks_for_officer_detailed(bigint);
drop function if exists create_billing_record(bigint, bigint, numeric, numeric);
drop function if exists verify_billing(bigint);
drop function if exists complete_discharge_request(bigint);
drop function if exists get_discharge_request_details(bigint);
drop function if exists list_discharge_requests(text);
drop table if exists tasks cascade;

-- These two changed their return columns (billing_verified removed), which
-- `create or replace` can't do, so drop them; ahdms_functions.sql recreates
-- them.
drop function if exists list_discharge_requests_by_requester(bigint);
drop function if exists list_discharge_requests_detailed(text);

-- Ask PostgREST to pick up the change immediately instead of waiting for
-- its next automatic schema-cache refresh.
select pg_notify('pgrst', 'reload schema');
