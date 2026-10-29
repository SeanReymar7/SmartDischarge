-- ============================================
-- AHDMS Core Functionality RPC Functions
-- Run after: ahdms_schema.sql and ahdms_auth_functions.sql
--
-- Workflow:
--   1. Nurse keeps the patient chart (vital signs, nursing notes,
--      medication, other records) and submits a discharge request.
--   2. Doctor reads the chart, adds advice/orders, approves or rejects.
--   3. Billing computes the expenses of an approved request; clearing
--      the bill completes the discharge.
-- ============================================

-- ============================================
-- OFFICERS: toggle duty status (admin action)
-- ============================================
create or replace function set_duty_status(p_officer_id bigint, p_duty_status text)
returns officers
language plpgsql
security definer
as $$
declare
    v_officer officers;
begin
    if p_duty_status not in ('on_duty', 'off_duty') then
        raise exception 'Invalid duty_status: %', p_duty_status;
    end if;

    update officers
    set duty_status = p_duty_status
    where officer_id = p_officer_id
    returning * into v_officer;

    if v_officer is null then
        raise exception 'Officer not found';
    end if;

    return v_officer;
end;
$$;

-- ============================================
-- PATIENTS: register new patient
-- ============================================
create or replace function register_patient(
    p_full_name             text,
    p_date_of_birth         date,
    p_age                   smallint,
    p_contact_number        text,
    p_emergency_contact     text,
    p_room_number           smallint,
    p_philhealth_no         text,
    p_attending_officer_id  bigint
)
returns patients
language plpgsql
security definer
as $$
declare
    v_patient patients;
begin
    insert into patients (
        full_name, date_of_birth, age, contact_number,
        emergency_contact, room_number, philhealth_no, attending_officer_id
    )
    values (
        p_full_name, p_date_of_birth, p_age, p_contact_number,
        p_emergency_contact, p_room_number, p_philhealth_no, p_attending_officer_id
    )
    returning * into v_patient;

    return v_patient;
end;
$$;

-- ============================================
-- PATIENTS: update patient info
-- ============================================
create or replace function update_patient_info(
    p_patient_id            bigint,
    p_contact_number        text default null,
    p_emergency_contact     text default null,
    p_room_number           smallint default null,
    p_attending_officer_id  bigint default null
)
returns patients
language plpgsql
security definer
as $$
declare
    v_patient patients;
begin
    update patients
    set contact_number       = coalesce(p_contact_number, contact_number),
        emergency_contact    = coalesce(p_emergency_contact, emergency_contact),
        room_number          = coalesce(p_room_number, room_number),
        attending_officer_id = coalesce(p_attending_officer_id, attending_officer_id)
    where patient_id = p_patient_id
    returning * into v_patient;

    if v_patient is null then
        raise exception 'Patient not found';
    end if;

    return v_patient;
end;
$$;

-- ============================================
-- CHART: add an entry. Doctors may only add 'doctor_order'; nurses may
-- add every other type.
-- ============================================
create or replace function add_chart_entry(
    p_patient_id   bigint,
    p_recorded_by  bigint,
    p_entry_type   text,
    p_details      jsonb
)
returns chart_entries
language plpgsql
security definer
as $$
declare
    v_role  text;
    v_entry chart_entries;
begin
    select role into v_role from officers where officer_id = p_recorded_by;

    if v_role is null then
        raise exception 'Officer not found';
    end if;
    if v_role not in ('nurse', 'doctor') or (p_entry_type = 'doctor_order') <> (v_role = 'doctor') then
        raise exception 'A % cannot add a % entry', v_role, p_entry_type;
    end if;
    if p_details is null or p_details = '{}'::jsonb then
        raise exception 'Chart entry cannot be empty';
    end if;

    insert into chart_entries (patient_id, recorded_by, entry_type, details)
    values (p_patient_id, p_recorded_by, p_entry_type, p_details)
    returning * into v_entry;

    return v_entry;
end;
$$;

-- ============================================
-- CHART: every entry for a patient, newest first, with author name
-- ============================================
create or replace function list_chart_entries(p_patient_id bigint)
returns table (
    entry_id          bigint,
    entry_type        text,
    details           jsonb,
    recorded_by_name  text,
    recorded_by_role  text,
    created_at        timestamptz
)
language sql
stable
security definer
as $$
    select ce.entry_id, ce.entry_type, ce.details, o.full_name, o.role, ce.created_at
    from chart_entries ce
    join officers o on o.officer_id = ce.recorded_by
    where ce.patient_id = p_patient_id
    order by ce.created_at desc;
$$;

-- ============================================
-- DISCHARGE REQUESTS: nurse submits the patient's record for discharge
-- ============================================
create or replace function create_discharge_request(
    p_patient_id    bigint,
    p_requested_by  bigint
)
returns bigint
language plpgsql
security definer
as $$
declare
    v_request_id bigint;
begin
    if exists (
        select 1 from discharge_requests
        where patient_id = p_patient_id and status in ('pending', 'approved')
    ) then
        raise exception 'Patient already has an open discharge request';
    end if;

    insert into discharge_requests (patient_id, requested_by)
    values (p_patient_id, p_requested_by)
    returning request_id into v_request_id;

    return v_request_id;
end;
$$;

-- ============================================
-- DISCHARGE REQUESTS: doctor approves / rejects a pending request.
-- approved_by doubles as "acted_by" -- it records who made the call.
-- ============================================
create or replace function approve_discharge_request(
    p_request_id   bigint,
    p_approved_by  bigint
)
returns discharge_requests
language plpgsql
security definer
as $$
declare
    v_request discharge_requests;
begin
    update discharge_requests
    set status = 'approved', approved_by = p_approved_by
    where request_id = p_request_id and status = 'pending'
    returning * into v_request;

    if v_request is null then
        raise exception 'Only a pending discharge request can be approved';
    end if;

    return v_request;
end;
$$;

create or replace function reject_discharge_request(
    p_request_id  bigint,
    p_rejected_by bigint
)
returns discharge_requests
language plpgsql
security definer
as $$
declare
    v_request discharge_requests;
begin
    update discharge_requests
    set status = 'rejected', approved_by = p_rejected_by
    where request_id = p_request_id and status = 'pending'
    returning * into v_request;

    if v_request is null then
        raise exception 'Only a pending discharge request can be rejected';
    end if;

    return v_request;
end;
$$;

-- ============================================
-- BILLING: compute the expenses of a doctor-approved request and clear
-- it. The total is summed here from the itemized charges so it can never
-- disagree with them. Clearing completes the discharge.
-- ============================================
create or replace function clear_billing(
    p_request_id            bigint,
    p_handled_by            bigint,
    p_charges               jsonb,
    p_philhealth_deduction  numeric
)
returns billing
language plpgsql
security definer
as $$
declare
    v_request discharge_requests;
    v_total   numeric;
    v_billing billing;
begin
    select * into v_request from discharge_requests where request_id = p_request_id for update;

    if v_request is null or v_request.status <> 'approved' then
        raise exception 'Only a doctor-approved discharge request can be billed';
    end if;
    if jsonb_typeof(p_charges) is distinct from 'object'
        or exists (
            select 1 from jsonb_each(p_charges)
            where case when jsonb_typeof(value) = 'number' then value::numeric < 0 else true end
        ) then
        raise exception 'Every charge must be a non-negative number';
    end if;

    select coalesce(sum(value::numeric), 0) into v_total from jsonb_each(p_charges);

    if p_philhealth_deduction is null or p_philhealth_deduction < 0 or p_philhealth_deduction > v_total then
        raise exception 'PhilHealth deduction must be between 0 and the total amount';
    end if;

    insert into billing (
        discharge_request_id, patient_id, handled_by,
        charges, total_amount, philhealth_deduction
    )
    values (
        p_request_id, v_request.patient_id, p_handled_by,
        p_charges, v_total, p_philhealth_deduction
    )
    returning * into v_billing;

    update discharge_requests
    set status = 'completed'
    where request_id = p_request_id;

    update patients
    set discharge_date = now()
    where patient_id = v_request.patient_id;

    return v_billing;
end;
$$;

-- ============================================
-- BILLING: cleared bills with patient name, newest first
-- ============================================
create or replace function list_billing_records()
returns table (
    billing_id            bigint,
    patient_name          text,
    handled_by_name       text,
    charges               jsonb,
    total_amount          numeric,
    philhealth_deduction  numeric,
    created_at            timestamptz
)
language sql
stable
security definer
as $$
    select b.billing_id, p.full_name, o.full_name, b.charges,
        b.total_amount, b.philhealth_deduction, b.created_at
    from billing b
    join patients p on p.patient_id = b.patient_id
    left join officers o on o.officer_id = b.handled_by
    order by b.created_at desc;
$$;

-- ============================================
-- LISTINGS joined with display data the tables alone don't carry
-- ============================================

-- ── DISCHARGE REQUESTS: list scoped to the officer who filed them ──────
create or replace function list_discharge_requests_by_requester(p_officer_id bigint)
returns table (
    request_id       bigint,
    patient_id       bigint,
    patient_name     text,
    status           text,
    "timestamp"      timestamptz
)
language sql
stable
security definer
as $$
    select dr.request_id, dr.patient_id, p.full_name, dr.status, dr."timestamp"
    from discharge_requests dr
    join patients p on p.patient_id = dr.patient_id
    where dr.requested_by = p_officer_id
    order by dr."timestamp" desc;
$$;

-- ── DISCHARGE REQUESTS: hospital-wide list with display names ──────────
create or replace function list_discharge_requests_detailed(p_status text default null)
returns table (
    request_id        bigint,
    patient_id        bigint,
    patient_name      text,
    requested_by      bigint,
    requested_by_name text,
    approved_by       bigint,
    approved_by_name  text,
    status            text,
    "timestamp"       timestamptz
)
language sql
stable
security definer
as $$
    select dr.request_id, dr.patient_id, p.full_name, dr.requested_by, ro.full_name,
        dr.approved_by, ao.full_name,
        dr.status, dr."timestamp"
    from discharge_requests dr
    join patients p on p.patient_id = dr.patient_id
    join officers ro on ro.officer_id = dr.requested_by
    left join officers ao on ao.officer_id = dr.approved_by
    where p_status is null or dr.status = p_status
    order by dr."timestamp" desc;
$$;

-- ── PATIENTS: scoped to attending officer ──────────────────────────────
create or replace function list_patients_by_officer(p_officer_id bigint)
returns setof patients
language sql
stable
security definer
as $$
    select * from patients
    where attending_officer_id = p_officer_id
    order by admission_date desc;
$$;

-- ── PATIENTS: hospital-wide, read-only ──────────────────────────────────
create or replace function list_all_patients()
returns setof patients
language sql
stable
security definer
as $$
    select * from patients
    order by admission_date desc;
$$;

-- ── OFFICERS: hospital-wide staff list ───────────────────────────────────
create or replace function list_officers()
returns setof officers
language sql
stable
security definer
as $$
    select * from officers
    order by role, full_name;
$$;

-- ============================================
-- GRANTS
-- RLS is enabled on every table with no policies, so the anon role has
-- zero direct table access. Every function the client calls has to be
-- explicitly granted here.
-- ============================================

revoke all on function set_duty_status(bigint, text) from public;
revoke all on function register_patient(text, date, smallint, text, text, smallint, text, bigint) from public;
revoke all on function update_patient_info(bigint, text, text, smallint, bigint) from public;
revoke all on function add_chart_entry(bigint, bigint, text, jsonb) from public;
revoke all on function list_chart_entries(bigint) from public;
revoke all on function create_discharge_request(bigint, bigint) from public;
revoke all on function approve_discharge_request(bigint, bigint) from public;
revoke all on function reject_discharge_request(bigint, bigint) from public;
revoke all on function clear_billing(bigint, bigint, jsonb, numeric) from public;
revoke all on function list_billing_records() from public;
revoke all on function list_discharge_requests_by_requester(bigint) from public;
revoke all on function list_discharge_requests_detailed(text) from public;
revoke all on function list_patients_by_officer(bigint) from public;
revoke all on function list_all_patients() from public;
revoke all on function list_officers() from public;

grant execute on function set_duty_status(bigint, text) to anon;
grant execute on function register_patient(text, date, smallint, text, text, smallint, text, bigint) to anon;
grant execute on function update_patient_info(bigint, text, text, smallint, bigint) to anon;
grant execute on function add_chart_entry(bigint, bigint, text, jsonb) to anon;
grant execute on function list_chart_entries(bigint) to anon;
grant execute on function create_discharge_request(bigint, bigint) to anon;
grant execute on function approve_discharge_request(bigint, bigint) to anon;
grant execute on function reject_discharge_request(bigint, bigint) to anon;
grant execute on function clear_billing(bigint, bigint, jsonb, numeric) to anon;
grant execute on function list_billing_records() to anon;
grant execute on function list_discharge_requests_by_requester(bigint) to anon;
grant execute on function list_discharge_requests_detailed(text) to anon;
grant execute on function list_patients_by_officer(bigint) to anon;
grant execute on function list_all_patients() to anon;
grant execute on function list_officers() to anon;
