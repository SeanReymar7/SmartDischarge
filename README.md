# AHDMS — Automated Hospital Discharge Management System

A web-based discharge management system for **Butuan Medical Center**. It replaces paper charts and nurse carts with one shared dashboard, so Nursing, Physicians, Billing, and Administration can see and clear each patient's discharge without walking paperwork between departments.

> Thesis project. Use **fake patient data only** for testing and demos.

---

## How the system works

### Roles

Every staff account has exactly one role. The role decides which dashboard opens after sign-in.

| Role | Dashboard | What they do |
|---|---|---|
| **Nurse** | `/nursedashboardpage` | Register patients, update contact/room details, file discharge requests, complete nurse clearance tasks |
| **Doctor** | `/doctordashboardpage` | Complete physician sign-off tasks, approve or reject discharge requests, finalize approved discharges |
| **Billing** | `/billingdashboardpage` | Create the patient's billing record, verify (clear) billing, complete billing tasks |
| **Admin** | `/admindashboardpage` | Register staff accounts, set staff on/off duty, view hospital-wide discharge queue, patients, and weekly stats |

### Discharge workflow

```
 Nurse files a               System creates one task per          Each department
 discharge request  ──────►  department and auto-assigns it  ───► completes its task
                             to the least-busy ON-DUTY officer     (My Tasks / My Sign-offs)
                                                                          │
                                                                          ▼
 Patient is            Doctor finalizes        Doctor approves     Billing verifies
 discharged   ◄─────── (completed)      ◄───── the request    ◄─── the bill
 (discharge_date set)                          (only if every task
                                                is done AND billing
                                                is verified)
```

1. **Request:** a nurse picks one of their admitted patients and files a discharge request. The status is `pending`.
2. **Auto-assignment:** the database creates the clearance tasks and gives each one to the on-duty officer with the matching role who has the fewest open tasks. Staff who are **off duty** receive nothing. If nobody in a role is on duty, that task stays unassigned.
3. **Clearance:** each officer opens **My Tasks** (doctors: **My Sign-offs**) and marks their task complete.
4. **Billing:** Billing creates the billing record and clears it. That sets `billing_verified` on the request.
5. **Approval:** the doctor can approve only when every task is done **and** billing is verified. Otherwise the database refuses with a clear message. The doctor can also reject.
6. **Completion:** an approved request is finalized, the patient's `discharge_date` is set, and the patient leaves the "currently admitted" list.

Request statuses: `pending` → `approved` → `completed`, or `rejected`. (`in_progress` exists in the schema, but no function sets it yet.)

### Where the logic lives

All business rules run **inside Postgres** as functions (RPCs) in `supabase/`. The frontend only calls them with `supabase.rpc(...)`. Tables have Row Level Security enabled with no policies, so the browser cannot read or write tables directly.

| File | Contents |
|---|---|
| `supabase/ahdms_schema.sql` | Tables: `officers`, `credentials`, `patients`, `discharge_requests`, `tasks`, `billing` |
| `supabase/ahdms_auth_functions.sql` | `login_officer`, `register_officer` (bcrypt password hashing via pgcrypto) |
| `supabase/ahdms_core_functions.sql` | Workflow: requests, auto-assignment, tasks, billing, approve/reject/complete, listings |
| `supabase/ahdms_cleanup_legacy.sql` | One-time cleanup of functions from an older schema version |

---

## Getting started

### 1. Install

```bash
npm install
```

### 2. Set up the database (Supabase SQL Editor)

Open **Supabase Dashboard → SQL Editor**, paste each file, and click **Run**, in this order:

1. `supabase/ahdms_cleanup_legacy.sql`: only if the project has the old functions
2. `supabase/ahdms_schema.sql`: ⚠️ **drops and recreates all tables, so existing data is deleted**
3. `supabase/ahdms_auth_functions.sql`
4. `supabase/ahdms_core_functions.sql`

Then create the first admin. This works only while the `officers` table is empty:

```sql
select * from register_officer('admin@test.com', 'ChangeMe123!', 'Test Admin', 'admin');
```

Every other account (nurse, doctor, billing) is created from the **Admin → Staff** page.

### 3. Environment variables

Copy `.env.example` to `.env` and fill in the values from **Supabase → Project Settings → API**:

```
SUPABASE_URL=https://<your-project>.supabase.co
SUPABASE_KEY=<anon / publishable key>
```

Use the **anon** key only. Never put the `service_role` key in this project. `.env` is gitignored.

### 4. Run

```bash
npm run dev        # http://localhost:3000
npm run build      # production build
npm run preview    # serve the production build
```

### 5. Try the full workflow

1. Sign in as the admin → **Staff** → register one nurse, one doctor, and one billing officer. Set all of them **on duty**.
2. Sign in as the nurse → **My Patients → Add Patient** (fake data) → **Discharge Requests → Request Discharge**.
3. Nurse → **My Tasks → Mark Complete**.
4. Billing → **Pending Billing** → create and clear the bill → **My Tasks → Mark Complete**.
5. Doctor → **My Sign-offs** → complete the task → **Discharge Requests** → approve → finalize.
6. Admin → **Dashboard**: the discharge shows as completed.

---

## Project structure

```
app/
  assets/css/tailwind.css     Design tokens (colors, font, radius), transitions
  components/
    AppLogo.vue               Brand mark (cross with exit arrow = discharge)
    DashboardShell.vue        Shared sidebar, top bar, search, theme toggle, logout
  composables/
    useAdminSession.ts        Session cookie + role → dashboard routing
    useDarkMode.ts            Light/dark theme
    useOfficerName.ts         Initials for avatars
  middleware/auth.ts          Redirects to /loginpage; blocks other roles' dashboards
  pages/
    index.vue                 Landing page
    loginpage.vue             Staff sign-in
    nursedashboardpage.vue    Nursing
    doctordashboardpage.vue   Physicians
    billingdashboardpage.vue  Billing
    admindashboardpage.vue    Administration
  types/database.types.ts     Row types for RPC results
supabase/                     SQL to run in the Supabase SQL Editor
```

**Stack:** Nuxt 4 (Vue 3, Vite), Tailwind CSS v4, Lucide icons, Supabase (Postgres + RPC).

---

## Design system

| Token | Light | Use |
|---|---|---|
| Ward ink | `#0F2622` | Sidebar, login brand panel, brand badges |
| Theatre green | `#1F6B57` | Primary buttons, active states |
| Clinical paper | `#F3F6F5` | App background |
| Amber `warning` | `#A15C00` | Pending / needs action |
| Blue `info` | `#2463A6` | In progress |
| Green `success` | `#237A4B` | Cleared / approved |
| Red `danger` | `#B42318` | Rejected / destructive |

- **Typeface:** Atkinson Hyperlegible Next, built so 1/l/I and 0/O never look alike, which matters for room numbers and amounts.
- **Icons:** Lucide at 1.75 stroke, with one meaning per icon: bed = patients, open door = discharge, clipboard check = clearance task, signature = physician sign-off, receipt = billing, ID card = staff.
- **Dark mode:** every token has a dark value. Use the moon/sun button in the top bar.
- Use the tokens (`bg-primary`, `text-warning`, `bg-success/10`, etc.), not raw hex values.

---

## Known limitations (planned work)

- **Security:** sign-in uses a custom `credentials` table and a browser cookie, not Supabase Auth. The RPCs trust the officer ID sent by the browser, so anyone holding the public anon key can call them. **Do not store real patient data** until this moves to Supabase Auth + Row Level Security policies.
- **Not yet built:** document upload and OCR with a human review step, live updates (Supabase Realtime), the audit log, a Medical Records role, and evaluation metrics export.
- **Out of scope:** PhilHealth claims processing. The existing `philhealth_*` fields are scheduled for removal.
