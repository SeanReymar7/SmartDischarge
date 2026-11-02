<script setup lang="ts">
import {
  AlertTriangle,
  BedSingle,
  CheckCircle2,
  Circle,
  Clock,
  DoorOpen,
  IdCard,
  LayoutDashboard,
  LoaderCircle,
  ReceiptText,
  Settings,
  TrendingUp,
  UserRoundCheck,
  XCircle,
} from '@lucide/vue'
import { computed, onMounted, ref } from 'vue'

definePageMeta({
  middleware: 'auth',
  requiredRole: 'admin',
})

useHead({
  title: 'Admin Dashboard — AHDMS',
  meta: [
    {
      name: 'description',
      content: 'Administrator analytics dashboard for the Automated Hospital Discharge Management System at Butuan Medical Center.',
    },
  ],
})

const supabase = useSupabaseClient()
const session = useAdminSession()
const officerId = computed(() => Number(session.value?.id))

const navItems = [
  { label: 'Dashboard', icon: LayoutDashboard, section: 'overview' },
  { label: 'Discharge Queue', icon: DoorOpen, section: 'discharge-queue' },
  { label: 'Patients', icon: BedSingle, section: 'patients' },
  { label: 'Staff', icon: IdCard, section: 'staff' },
  { label: 'Settings', icon: Settings, section: 'settings' },
] as const

type Section = typeof navItems[number]['section']

const activeSection = ref<Section>('overview')

interface Officer {
  officer_id: number
  full_name: string
  role: string
  specialty: string | null
  duty_status: string
}

const officers = ref<Officer[]>([])
const isLoadingStaff = ref(false)
const staffError = ref('')
const updatingOfficerId = ref<number | null>(null)

async function loadStaff() {
  isLoadingStaff.value = true
  staffError.value = ''

  const { data, error } = await supabase.rpc('list_officers')
  if (error) {
    staffError.value = error.message
  } else {
    officers.value = data ?? []
  }

  isLoadingStaff.value = false
}

onMounted(loadStaff)

async function toggleDutyStatus(officer: Officer) {
  const nextStatus = officer.duty_status === 'on_duty' ? 'off_duty' : 'on_duty'
  updatingOfficerId.value = officer.officer_id

  const { error } = await supabase.rpc('set_duty_status', {
    p_officer_id: officer.officer_id,
    p_duty_status: nextStatus,
  })

  if (!error) await loadStaff()
  updatingOfficerId.value = null
}

const roleOptions = ['nurse', 'doctor', 'billing', 'admin']
const specialtyOptions = [
  'General Medicine',
  'Anesthesiology',
  'Cardiology',
  'Dermatology',
  'Emergency Medicine',
  'Family Medicine',
  'Gastroenterology',
  'General Surgery',
  'Nephrology',
  'Neurology',
  'Obstetrics and Gynecology',
  'Oncology',
  'Ophthalmology',
  'Orthopedics',
  'Otorhinolaryngology (ENT)',
  'Pediatrics',
  'Psychiatry',
  'Pulmonology',
  'Urology',
]
const emptyStaffForm = { full_name: '', email: '', password: '', role: 'nurse', specialty: '', license_number: '' }
const newStaffForm = ref({ ...emptyStaffForm })
const showRegisterStaffForm = ref(false)
const isRegisteringStaff = ref(false)
const registerStaffError = ref('')

function openRegisterStaffForm() {
  newStaffForm.value = { ...emptyStaffForm }
  registerStaffError.value = ''
  showRegisterStaffForm.value = true
}

async function registerStaff() {
  isRegisteringStaff.value = true
  registerStaffError.value = ''

  const { error } = await supabase.rpc('register_officer', {
    p_email: newStaffForm.value.email,
    p_password: newStaffForm.value.password,
    p_full_name: newStaffForm.value.full_name,
    p_role: newStaffForm.value.role,
    p_admin_id: officerId.value,
    p_specialty: newStaffForm.value.role === 'doctor' ? newStaffForm.value.specialty : null,
    p_license_number: newStaffForm.value.role === 'doctor' ? newStaffForm.value.license_number : null,
  })

  if (error) {
    registerStaffError.value = error.message
    isRegisteringStaff.value = false
    return
  }

  showRegisterStaffForm.value = false
  isRegisteringStaff.value = false
  await loadStaff()
}

// ── Discharge requests (hospital-wide) ──────────────────────────────────

interface DischargeRequest {
  request_id: number
  patient_id: number
  patient_name: string
  requested_by_name: string
  approved_by_name: string | null
  status: string
  timestamp: string
}

const requestStatusColor: Record<string, string> = {
  pending: 'var(--warning)',
  approved: 'var(--success)',
  completed: 'var(--neutral)',
  rejected: 'var(--danger)',
}

const dischargeRequests = ref<DischargeRequest[]>([])
const isLoadingDischargeRequests = ref(false)
const dischargeRequestsError = ref('')

async function loadDischargeRequests() {
  isLoadingDischargeRequests.value = true
  dischargeRequestsError.value = ''

  const { data, error } = await supabase.rpc('list_discharge_requests_detailed', { p_status: null })
  if (error) {
    dischargeRequestsError.value = error.message
  } else {
    dischargeRequests.value = data ?? []
  }

  isLoadingDischargeRequests.value = false
}

onMounted(loadDischargeRequests)

const approvedAwaitingCompletion = computed(() =>
  dischargeRequests.value.filter((r) => r.status === 'approved'))

// ── Patients (read-only, hospital-wide) ──────────────────────────────────

interface Patient {
  patient_id: number
  full_name: string
  date_of_birth: string | null
  age: number | null
  sex: string | null
  address: string | null
  contact_number: string | null
  emergency_contact: string | null
  admission_date: string
  discharge_date: string | null
  room_number: number | null
  philhealth_no: string | null
}

const patients = ref<Patient[]>([])
const isLoadingPatients = ref(false)
const patientsError = ref('')

async function loadPatients() {
  isLoadingPatients.value = true
  patientsError.value = ''

  const { data, error } = await supabase.rpc('list_all_patients')
  if (error) {
    patientsError.value = error.message
  } else {
    patients.value = data ?? []
  }

  isLoadingPatients.value = false
}

onMounted(loadPatients)

const patientSearchQuery = ref('')

const filteredPatients = computed(() => {
  const q = patientSearchQuery.value.trim().toLowerCase()
  if (!q) return patients.value
  return patients.value.filter((patient) => {
    return patient.full_name.toLowerCase().includes(q)
      || (patient.philhealth_no ?? '').toLowerCase().includes(q)
      || (patient.contact_number ?? '').toLowerCase().includes(q)
      || String(patient.room_number ?? '').includes(q)
  })
})

const viewingPatient = ref<Patient | null>(null)
const showAbstracts = ref(false)

const viewingPatientFields = computed(() => {
  const p = viewingPatient.value
  if (!p) return []
  return [
    { label: 'Full name', value: p.full_name },
    { label: 'Age', value: p.age ?? '—' },
    { label: 'Date of birth', value: p.date_of_birth ?? '—' },
    { label: 'Sex', value: p.sex ?? '—' },
    { label: 'Address', value: p.address ?? '—' },
    { label: 'Contact number', value: p.contact_number ?? '—' },
    { label: 'Emergency contact', value: p.emergency_contact ?? '—' },
    { label: 'Admission date', value: p.admission_date },
    { label: 'Room number', value: p.room_number ?? '—' },
    { label: 'PhilHealth No.', value: p.philhealth_no ?? '—' },
    { label: 'Discharge date', value: p.discharge_date ?? '—' },
  ]
})

// ── Overview: real stats derived from loaded data ───────────────────────

const onDutyCount = computed(() => officers.value.filter((o) => o.duty_status === 'on_duty').length)
const patientsInQueue = computed(() => patients.value.filter((p) => !p.discharge_date).length)

const statTiles = computed(() => [
  { icon: BedSingle, label: 'Patients in Queue', value: String(patientsInQueue.value) },
  { icon: UserRoundCheck, label: 'Staff on Duty', value: `${onDutyCount.value} of ${officers.value.length}` },
  { icon: DoorOpen, label: 'Completed Discharges', value: String(dischargeRequests.value.filter((r) => r.status === 'completed').length) },
  { icon: ReceiptText, label: 'Awaiting Billing', value: String(dischargeRequests.value.filter((r) => r.status === 'approved').length) },
])

const dischargeStatusIcon: Record<string, typeof Clock> = {
  pending: Clock,
  approved: CheckCircle2,
  rejected: XCircle,
  completed: Circle,
}

const dischargeStatus = computed(() => {
  const order = ['pending', 'approved', 'completed', 'rejected']
  return order.map((label) => ({
    label,
    count: dischargeRequests.value.filter((r) => r.status === label).length,
    color: requestStatusColor[label],
    icon: dischargeStatusIcon[label],
  }))
})
const statusTotal = computed(() => dischargeStatus.value.reduce((sum, s) => sum + s.count, 0))
const hoveredStatus = ref<number | null>(null)

// Discharges per day, current week (Mon–Sun) vs. the same weekday last
// week, counted off patients.discharge_date.
function startOfWeek(date: Date) {
  const d = new Date(date)
  const day = d.getDay()
  const diff = (day === 0 ? -6 : 1) - day
  d.setDate(d.getDate() + diff)
  d.setHours(0, 0, 0, 0)
  return d
}

function countDischargesOnDay(weekStart: Date, dayOffset: number) {
  const dayStart = new Date(weekStart)
  dayStart.setDate(dayStart.getDate() + dayOffset)
  const dayEnd = new Date(dayStart)
  dayEnd.setDate(dayEnd.getDate() + 1)
  return patients.value.filter((p) => {
    if (!p.discharge_date) return false
    const d = new Date(p.discharge_date)
    return d >= dayStart && d < dayEnd
  }).length
}

const weeklyTrend = computed(() => {
  const dayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
  const thisWeekStart = startOfWeek(new Date())
  const lastWeekStart = new Date(thisWeekStart)
  lastWeekStart.setDate(lastWeekStart.getDate() - 7)

  return dayLabels.map((day, i) => ({
    day,
    count: countDischargesOnDay(thisWeekStart, i),
    lastWeek: countDischargesOnDay(lastWeekStart, i),
  }))
})
const weeklyMax = computed(() => Math.max(1, ...weeklyTrend.value.map((d) => Math.max(d.count, d.lastWeek))))
const weeklyTotal = computed(() => weeklyTrend.value.reduce((sum, d) => sum + d.count, 0))
const lastWeekTotal = computed(() => weeklyTrend.value.reduce((sum, d) => sum + d.lastWeek, 0))
const weeklyDeltaPct = computed(() => {
  if (lastWeekTotal.value === 0) return weeklyTotal.value === 0 ? 0 : 100
  return Math.round(((weeklyTotal.value - lastWeekTotal.value) / lastWeekTotal.value) * 100)
})
const hoveredDay = ref<number | null>(null)
</script>

<template>
  <div>
    <DashboardShell
      v-model:section="activeSection"
      v-model:search="patientSearchQuery"
      department="Administration"
      role-label="System administrator"
      :nav-items="navItems"
      :alert="approvedAwaitingCompletion.length > 0"
    >
      <template v-if="activeSection === 'overview'">
      <!-- Stat tiles -->
      <div class="grid gap-4 sm:grid-cols-2 xl:grid-cols-4">
        <div
          v-for="tile in statTiles"
          :key="tile.label"
          class="rounded-xl border border-border bg-card p-5"
        >
          <p class="flex items-center gap-2 text-sm text-muted-foreground">
            <component :is="tile.icon" class="h-4 w-4 shrink-0" :stroke-width="1.75" aria-hidden="true" />
            {{ tile.label }}
          </p>
          <p class="mt-3 text-3xl font-semibold tracking-tight tabular-nums">{{ tile.value }}</p>
        </div>
      </div>

      <div class="grid gap-4 xl:grid-cols-3">
        <!-- Weekly discharge trend -->
        <div class="rounded-xl border border-border bg-card p-5 xl:col-span-2">
          <div class="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h2 class="text-base font-bold tracking-tight">Discharges This Week</h2>
              <p class="text-xs text-muted-foreground">Finalized discharges per day vs. last week</p>
            </div>
            <span
              class="flex items-center gap-1 text-xs font-medium"
              :class="weeklyDeltaPct >= 0 ? 'text-success' : 'text-danger'"
            >
              <TrendingUp v-if="weeklyDeltaPct >= 0" class="h-3.5 w-3.5" />
              <TrendingUp v-else class="h-3.5 w-3.5 rotate-180" />
              {{ weeklyDeltaPct >= 0 ? '+' : '' }}{{ weeklyDeltaPct }}% vs last week
            </span>
          </div>

          <div class="mt-4 flex items-center gap-4 text-xs text-muted-foreground">
            <span class="flex items-center gap-1.5">
              <span class="h-2 w-2 rounded-full bg-primary" />
              This week
            </span>
            <span class="flex items-center gap-1.5">
              <span class="h-2 w-2 rounded-full bg-primary/25" />
              Last week
            </span>
          </div>

          <div class="relative mt-4 flex h-48 gap-3 sm:gap-4">
            <div class="pointer-events-none absolute inset-x-0 top-0 flex h-full flex-col justify-between">
              <div v-for="n in 4" :key="n" class="border-t border-border/60 first:border-transparent" />
            </div>

            <div
              v-for="(day, i) in weeklyTrend"
              :key="day.day"
              class="relative z-10 flex flex-1 flex-col items-center gap-2"
              @mouseenter="hoveredDay = i"
              @mouseleave="hoveredDay = null"
            >
              <div
                v-if="hoveredDay === i"
                class="absolute -top-14 whitespace-nowrap rounded-md bg-foreground px-2.5 py-1.5 text-xs font-medium text-background shadow-sm"
              >
                <div class="tabular-nums">This week: {{ day.count }}</div>
                <div class="tabular-nums opacity-70">Last week: {{ day.lastWeek }}</div>
              </div>
              <div class="flex w-full flex-1 items-end justify-center gap-1">
                <div
                  class="w-full max-w-3.5 rounded-t-sm transition-colors"
                  :class="hoveredDay === i ? 'bg-primary' : 'bg-primary/80'"
                  :style="{ height: `${(day.count / weeklyMax) * 100}%` }"
                />
                <div
                  class="w-full max-w-3.5 rounded-t-sm bg-primary/25 transition-colors"
                  :class="hoveredDay === i ? 'bg-primary/35' : 'bg-primary/25'"
                  :style="{ height: `${(day.lastWeek / weeklyMax) * 100}%` }"
                />
              </div>
              <span class="text-xs text-muted-foreground">{{ day.day }}</span>
            </div>
          </div>
        </div>

        <!-- Discharge status breakdown -->
        <div class="rounded-xl border border-border bg-card p-5">
          <h2 class="text-base font-bold tracking-tight">Discharge Status</h2>
          <p class="text-xs text-muted-foreground">{{ statusTotal }} discharge request{{ statusTotal === 1 ? '' : 's' }}, hospital-wide</p>

          <div v-if="statusTotal === 0" class="flex h-24 items-center justify-center text-sm text-muted-foreground">
            No discharge requests yet.
          </div>
          <template v-else>
            <div class="mt-5 flex h-3 w-full overflow-hidden rounded-full bg-muted">
              <div
                v-for="(status, i) in dischargeStatus"
                :key="status.label"
                class="h-full transition-opacity"
                :style="{
                  width: `${(status.count / statusTotal) * 100}%`,
                  backgroundColor: status.color,
                  opacity: hoveredStatus === null || hoveredStatus === i ? 1 : 0.35,
                }"
                @mouseenter="hoveredStatus = i"
                @mouseleave="hoveredStatus = null"
              />
            </div>

            <ul class="mt-5 space-y-3">
              <li
                v-for="(status, i) in dischargeStatus"
                :key="status.label"
                class="flex items-center justify-between text-sm"
                @mouseenter="hoveredStatus = i"
                @mouseleave="hoveredStatus = null"
              >
                <span class="flex items-center gap-2">
                  <component :is="status.icon" class="h-4 w-4" :style="{ color: status.color }" />
                  <span class="capitalize" :class="hoveredStatus !== null && hoveredStatus !== i ? 'text-muted-foreground' : ''">
                    {{ status.label.replace('_', ' ') }}
                  </span>
                </span>
                <span class="font-medium tabular-nums">{{ status.count }}</span>
              </li>
            </ul>
          </template>
        </div>
      </div>
      </template>

      <!-- Discharge Queue -->
      <div v-if="activeSection === 'discharge-queue'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Discharge Queue</h2>
        <p class="text-xs text-muted-foreground">Approved by a doctor, awaiting final completion</p>

        <div v-if="dischargeRequestsError" class="mt-4 flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ dischargeRequestsError }}
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Requested By</th>
                <th class="pb-2 pr-4 font-medium">Approved By</th>
                <th class="pb-2 font-medium">Submitted</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="request in approvedAwaitingCompletion" :key="request.request_id">
                <td class="py-2 pr-4 font-medium">{{ request.patient_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.requested_by_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.approved_by_name ?? '—' }}</td>
                <td class="py-2 text-muted-foreground">{{ new Date(request.timestamp).toLocaleString() }}</td>
              </tr>
              <tr v-if="!isLoadingDischargeRequests && approvedAwaitingCompletion.length === 0">
                <td colspan="4" class="py-6 text-center text-sm text-muted-foreground">No approved requests are awaiting completion.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Patients -->
      <div v-if="activeSection === 'patients'" class="rounded-xl border border-border bg-card p-5">
        <div>
          <h2 class="text-base font-bold tracking-tight">Patient Records</h2>
          <p class="text-xs text-muted-foreground">
            {{ patientSearchQuery ? `Showing results for "${patientSearchQuery}"` : 'All patients, hospital-wide (read-only)' }}
          </p>
        </div>

        <div v-if="patientsError" class="mt-4 flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ patientsError }}
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Name</th>
                <th class="pb-2 pr-4 font-medium">Admitted</th>
                <th class="pb-2 pr-4 font-medium">Room</th>
                <th class="pb-2 pr-4 font-medium">PhilHealth No.</th>
                <th class="pb-2 pr-4 font-medium">Discharge Date</th>
                <th class="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="patient in filteredPatients" :key="patient.patient_id">
                <td class="py-2 pr-4 font-medium">{{ patient.full_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ patient.admission_date }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ patient.room_number ?? '—' }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ patient.philhealth_no ?? '—' }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ patient.discharge_date ?? '—' }}</td>
                <td class="py-2 text-right">
                  <button type="button" class="text-xs font-medium text-primary hover:underline" @click="viewingPatient = patient">
                    View
                  </button>
                </td>
              </tr>
              <tr v-if="!isLoadingPatients && filteredPatients.length === 0">
                <td colspan="6" class="py-6 text-center text-sm text-muted-foreground">
                  {{ patientSearchQuery ? 'No patients match your search.' : 'No patients yet.' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Staff -->
      <div v-if="activeSection === 'staff'" class="space-y-6">
        <div class="rounded-xl border border-border bg-card p-5">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 class="text-base font-bold tracking-tight">Staff</h2>
              <p class="mt-1 text-xs text-muted-foreground">All staff members, hospital-wide</p>
            </div>
            <button
              type="button"
              class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90"
              @click="openRegisterStaffForm"
            >
              Register Staff
            </button>
          </div>

          <div v-if="staffError" class="mt-4 flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ staffError }}
          </div>

          <div class="mt-4 overflow-x-auto">
            <table class="w-full text-sm">
              <thead>
                <tr class="border-b border-border text-left text-xs text-muted-foreground">
                  <th class="pb-2 pr-4 font-medium">Name</th>
                  <th class="pb-2 pr-4 font-medium">Role</th>
                  <th class="pb-2 pr-4 font-medium">Field</th>
                  <th class="pb-2 font-medium">Duty status</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                <tr v-for="officer in officers" :key="officer.officer_id">
                  <td class="py-2 pr-4 font-medium">{{ officer.full_name }}</td>
                  <td class="py-2 pr-4 text-muted-foreground capitalize">{{ officer.role }}</td>
                  <td class="py-2 pr-4 text-muted-foreground">{{ officer.specialty ?? '—' }}</td>
                  <td class="py-2">
                    <button
                      type="button"
                      :disabled="updatingOfficerId === officer.officer_id"
                      class="rounded-full px-2.5 py-1 text-xs font-medium capitalize transition-opacity hover:opacity-80 disabled:cursor-not-allowed disabled:opacity-60"
                      :class="officer.duty_status === 'on_duty' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'"
                      @click="toggleDutyStatus(officer)"
                    >
                      {{ officer.duty_status.replace('_', ' ') }}
                    </button>
                  </td>
                </tr>
                <tr v-if="!isLoadingStaff && officers.length === 0">
                  <td colspan="4" class="py-6 text-center text-sm text-muted-foreground">No staff found.</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>

      <!-- Settings -->
      <div v-if="activeSection === 'settings'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Settings</h2>
        <p class="mt-1 text-xs text-muted-foreground">Nothing here yet.</p>
      </div>
    </DashboardShell>

    <!-- Patient view modal -->
    <FormModal
      v-if="viewingPatient"
      title="Patient Information"
      :icon="BedSingle"
      @close="viewingPatient = null"
    >
      <div class="modal-body">
        <dl class="space-y-3">
          <div v-for="field in viewingPatientFields" :key="field.label" class="flex justify-between gap-4 border-b border-border pb-2 text-sm">
            <dt class="text-muted-foreground">{{ field.label }}</dt>
            <dd class="text-right font-medium">{{ field.value }}</dd>
          </div>
        </dl>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn-secondary" @click="viewingPatient = null">Close</button>
        <button type="button" class="btn-secondary" @click="showAbstracts = true">Medical Abstract</button>
      </div>
    </FormModal>

    <MedicalAbstracts
      v-if="viewingPatient && showAbstracts"
      :patient-id="viewingPatient.patient_id"
      :patient-name="viewingPatient.full_name"
      :officer-id="officerId"
      :can-write="false"
      @close="showAbstracts = false"
    />

    <!-- Register staff modal -->
    <FormModal
      v-if="showRegisterStaffForm"
      title="Register New Staff"
      subtitle="Creates a login and an officer profile in one go"
      :icon="IdCard"
      size="lg"
      :busy="isRegisteringStaff"
      @close="showRegisterStaffForm = false"
    >
      <form class="modal-form" @submit.prevent="registerStaff">
        <div class="modal-body">
          <fieldset class="field">
            <legend class="field-label">Role</legend>
            <div class="grid grid-cols-2 gap-1 rounded-md bg-muted p-1 sm:grid-cols-4">
              <label
                v-for="option in roleOptions"
                :key="option"
                class="cursor-pointer rounded-sm py-2 text-center text-sm font-medium capitalize text-muted-foreground transition-colors hover:text-foreground has-checked:bg-card has-checked:text-primary has-checked:shadow-sm has-focus-visible:outline-2 has-focus-visible:outline-ring"
              >
                <input v-model="newStaffForm.role" type="radio" name="staff-role" :value="option" class="sr-only">
                {{ option }}
              </label>
            </div>
          </fieldset>

          <div class="grid gap-4 sm:grid-cols-2">
            <div class="field sm:col-span-2">
              <label for="staff-full-name" class="field-label">Full name</label>
              <input id="staff-full-name" v-model="newStaffForm.full_name" type="text" required class="field-input">
            </div>
            <div v-if="newStaffForm.role === 'doctor'" class="field sm:col-span-2">
              <label for="staff-specialty" class="field-label">Field</label>
              <select id="staff-specialty" v-model="newStaffForm.specialty" required class="field-input">
                <option value="" disabled>Choose a field</option>
                <option v-for="option in specialtyOptions" :key="option" :value="option">{{ option }}</option>
              </select>
              <p class="text-xs text-muted-foreground">Nurses search by this when sending a discharge request.</p>
            </div>
            <div v-if="newStaffForm.role === 'doctor'" class="field sm:col-span-2">
              <label for="staff-license" class="field-label">License number</label>
              <input id="staff-license" v-model="newStaffForm.license_number" type="text" required class="field-input">
              <p class="text-xs text-muted-foreground">Printed on the doctor's medical abstracts.</p>
            </div>
            <div class="field">
              <label for="staff-email" class="field-label">Email</label>
              <input id="staff-email" v-model="newStaffForm.email" type="email" required class="field-input">
            </div>
            <div class="field">
              <label for="staff-password" class="field-label">Password</label>
              <input id="staff-password" v-model="newStaffForm.password" type="password" required class="field-input">
            </div>
          </div>

          <div v-if="registerStaffError" class="form-error">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ registerStaffError }}
          </div>
        </div>

        <div class="modal-footer">
          <button type="button" :disabled="isRegisteringStaff" class="btn-secondary" @click="showRegisterStaffForm = false">
            Cancel
          </button>
          <button type="submit" :disabled="isRegisteringStaff" class="btn-primary">
            <LoaderCircle v-if="isRegisteringStaff" class="h-4 w-4 animate-spin" />
            {{ isRegisteringStaff ? 'Registering…' : 'Register Staff' }}
          </button>
        </div>
      </form>
    </FormModal>
  </div>
</template>
