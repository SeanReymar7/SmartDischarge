<script setup lang="ts">
import {
  AlertTriangle,
  BedSingle,
  Check,
  DoorOpen,
  LayoutDashboard,
  LoaderCircle,
  Search,
  UserRoundPlus,
} from '@lucide/vue'
import { computed, onMounted, ref } from 'vue'

definePageMeta({
  middleware: 'auth',
  requiredRole: 'nurse',
})

useHead({
  title: 'Nurse Dashboard — AHDMS',
  meta: [
    {
      name: 'description',
      content: 'Nurse patient records dashboard for the Automated Hospital Discharge Management System at Butuan Medical Center.',
    },
  ],
})

const supabase = useSupabaseClient()
const session = useAdminSession()
const officerId = computed(() => Number(session.value?.id))

const navItems = [
  { label: 'Overview', icon: LayoutDashboard, section: 'overview' },
  { label: 'My Patients', icon: BedSingle, section: 'patients' },
  { label: 'Discharge Requests', icon: DoorOpen, section: 'discharge-requests' },
] as const

type Section = typeof navItems[number]['section']

const activeSection = ref<Section>('overview')

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
  attending_officer_id: number | null
}

interface DischargeRequest {
  request_id: number
  patient_id: number
  patient_name: string
  assigned_doctor_name: string | null
  status: string
  timestamp: string
}

interface Doctor {
  officer_id: number
  full_name: string
  specialty: string | null
  duty_status: string
}

const patients = ref<Patient[]>([])
const dischargeRequests = ref<DischargeRequest[]>([])
const doctors = ref<Doctor[]>([])
const isLoadingData = ref(false)
const dataError = ref('')
const searchQuery = ref('')

async function loadDashboardData() {
  isLoadingData.value = true
  const errors: string[] = []

  const [patientsRes, requestsRes, officersRes] = await Promise.all([
    supabase.rpc('list_patients_by_officer', { p_officer_id: officerId.value }),
    supabase.rpc('list_discharge_requests_by_requester', { p_officer_id: officerId.value }),
    supabase.rpc('list_officers'),
  ])

  if (patientsRes.error) errors.push(`Patients: ${patientsRes.error.message}`)
  else patients.value = patientsRes.data ?? []

  if (requestsRes.error) errors.push(`Discharge requests: ${requestsRes.error.message}`)
  else dischargeRequests.value = requestsRes.data ?? []

  if (officersRes.error) errors.push(`Doctors: ${officersRes.error.message}`)
  else doctors.value = (officersRes.data ?? []).filter((o) => o.role === 'doctor')

  dataError.value = errors.join(' ')
  isLoadingData.value = false
}

onMounted(loadDashboardData)

const filteredPatients = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  if (!q) return patients.value
  return patients.value.filter((patient) => {
    return patient.full_name.toLowerCase().includes(q)
      || (patient.philhealth_no ?? '').toLowerCase().includes(q)
      || (patient.contact_number ?? '').toLowerCase().includes(q)
      || String(patient.room_number ?? '').includes(q)
  })
})

const statusBarColor: Record<string, string> = {
  pending: 'var(--warning)',
  approved: 'var(--success)',
  completed: 'var(--neutral)',
  rejected: 'var(--danger)',
}

// ── Overview: ward board ────────────────────────────────────────────────

const DISCHARGE_STEPS = ['In care', 'Doctor review', 'Billing', 'Discharged']

const STAGE: Record<string, { step: number, label: string, color: string }> = {
  none: { step: 0, label: 'In care', color: 'var(--primary)' },
  rejected: { step: 0, label: 'Doctor rejected the request', color: 'var(--danger)' },
  pending: { step: 1, label: 'Waiting for doctor', color: 'var(--warning)' },
  approved: { step: 2, label: 'With billing', color: 'var(--success)' },
}

// Requests arrive newest first, so the first one found is the latest.
function patientStage(patientId: number) {
  const latest = dischargeRequests.value.find((r) => r.patient_id === patientId)
  return STAGE[latest?.status ?? 'none'] ?? STAGE.none!
}

function dayOfStay(admissionDate: string) {
  const days = Math.floor((Date.now() - new Date(`${admissionDate}T00:00:00`).getTime()) / 86_400_000)
  return Math.max(days, 0) + 1
}

const wardBoard = computed(() => filteredPatients.value
  .filter((p) => !p.discharge_date)
  .sort((a, b) => (a.room_number ?? Infinity) - (b.room_number ?? Infinity))
  .map((patient) => ({
    patient,
    stage: patientStage(patient.patient_id),
    day: dayOfStay(patient.admission_date),
  })))

const wardHeadline = computed(() => {
  const admitted = patients.value.filter((p) => !p.discharge_date).length
  if (admitted === 0) return 'You have no patients admitted.'
  return `You have ${admitted} patient${admitted === 1 ? '' : 's'} in your care.`
})

const wardDetail = computed(() => {
  const count = (label: string) => patients.value.filter((p) => !p.discharge_date && patientStage(p.patient_id).label === label).length
  return [
    { n: count(STAGE.pending!.label), text: 'waiting for a doctor' },
    { n: count(STAGE.approved!.label), text: 'with billing' },
    { n: count(STAGE.rejected!.label), text: 'rejected by a doctor' },
  ].filter((part) => part.n > 0).map((part) => `${part.n} ${part.text}`).join(', ')
})

const recentDischargeRequests = computed(() => dischargeRequests.value.slice(0, 5))

// ── Patient chart (vitals, notes, medication, other records) ────────────

const chartPatient = ref<Patient | null>(null)

// ── Discharge requests: create ────────────────────────────────────────

const requestFormError = ref('')
const showRequestForm = ref(false)
const requestFormStep = ref<'form' | 'confirm'>('form')
const requestPatientId = ref<number | null>(null)
const requestPatientSearch = ref('')
const requestDoctorId = ref<number | null>(null)
const requestDoctorSearch = ref('')
const isSavingRequest = ref(false)

const TERMINAL_STATUSES = ['completed', 'rejected']

function hasActiveRequest(patientId: number) {
  return dischargeRequests.value.some((r) => r.patient_id === patientId && !TERMINAL_STATUSES.includes(r.status))
}

const dischargeablePatients = computed(() => patients.value.filter((p) => !p.discharge_date && !hasActiveRequest(p.patient_id)))

const filteredRequestPatients = computed(() => {
  const q = requestPatientSearch.value.trim().toLowerCase()
  if (!q) return dischargeablePatients.value
  return dischargeablePatients.value.filter((p) => p.full_name.toLowerCase().includes(q))
})

// On-duty doctors first, but any doctor can be chosen.
const filteredRequestDoctors = computed(() => {
  const q = requestDoctorSearch.value.trim().toLowerCase()
  return doctors.value
    .filter((d) => d.full_name.toLowerCase().includes(q) || (d.specialty ?? '').toLowerCase().includes(q))
    .sort((a, b) => Number(b.duty_status === 'on_duty') - Number(a.duty_status === 'on_duty'))
})

const selectedRequestPatientName = computed(() => patients.value.find((p) => p.patient_id === requestPatientId.value)?.full_name ?? '')
const selectedRequestDoctorName = computed(() => {
  const doctor = doctors.value.find((d) => d.officer_id === requestDoctorId.value)
  if (!doctor) return ''
  return doctor.specialty ? `${doctor.full_name} (${doctor.specialty})` : doctor.full_name
})

function initials(name: string) {
  return name.split(/\s+/).filter((w) => !/^dr\.?$/i.test(w)).slice(0, 2).map((w) => w[0]).join('').toUpperCase()
}

function openNewRequestForm() {
  requestPatientId.value = dischargeablePatients.value[0]?.patient_id ?? null
  requestPatientSearch.value = ''
  requestDoctorId.value = null
  requestDoctorSearch.value = ''
  requestFormError.value = ''
  requestFormStep.value = 'form'
  showRequestForm.value = true
}

function handleRequestFormSubmit() {
  if (requestFormStep.value === 'form') {
    requestFormError.value = ''
    requestFormStep.value = 'confirm'
    return
  }
  submitNewRequest()
}

async function submitNewRequest() {
  if (requestPatientId.value === null || requestDoctorId.value === null) return

  isSavingRequest.value = true
  requestFormError.value = ''

  const { error } = await supabase.rpc('create_discharge_request', {
    p_patient_id: requestPatientId.value,
    p_requested_by: officerId.value,
    p_assigned_doctor_id: requestDoctorId.value,
  })

  if (error) {
    requestFormError.value = error.message
    isSavingRequest.value = false
    return
  }

  showRequestForm.value = false
  isSavingRequest.value = false
  await loadDashboardData()
}

// ── Patients: add / edit ──────────────────────────────────────────────

const showPatientForm = ref(false)
const editingPatientId = ref<number | null>(null)
const emptyPatientForm = {
  full_name: '',
  date_of_birth: '',
  age: '',
  sex: '',
  address: '',
  contact_number: '',
  emergency_contact: '',
  room_number: '',
  philhealth_no: '',
}
const patientForm = ref({ ...emptyPatientForm })
const isSavingPatient = ref(false)
const patientFormError = ref('')
const patientFormStep = ref<'form' | 'preview'>('form')

const patientFormTitle = computed(() => {
  if (patientFormStep.value === 'form') return editingPatientId.value === null ? 'Add Patient' : 'Edit Patient'
  return editingPatientId.value === null ? 'Confirm New Patient' : 'Confirm Patient Changes'
})

const patientFormSubtitle = computed(() => {
  if (patientFormStep.value === 'preview') return 'Check the details below before saving.'
  return editingPatientId.value === null ? undefined : 'Only sex, address, contact info and room number can be changed after registration.'
})

const patientPreviewFields = computed(() => [
  { label: 'Full name', value: patientForm.value.full_name },
  { label: 'Age', value: patientForm.value.age || '—' },
  { label: 'Date of birth', value: patientForm.value.date_of_birth || '—' },
  { label: 'Sex', value: patientForm.value.sex || '—' },
  { label: 'Address', value: patientForm.value.address || '—' },
  { label: 'Contact number', value: patientForm.value.contact_number || '—' },
  { label: 'Emergency contact', value: patientForm.value.emergency_contact || '—' },
  { label: 'Room number', value: patientForm.value.room_number || '—' },
  { label: 'PhilHealth No.', value: patientForm.value.philhealth_no || '—' },
])

function openNewPatientForm() {
  editingPatientId.value = null
  patientForm.value = { ...emptyPatientForm }
  patientFormError.value = ''
  patientFormStep.value = 'form'
  showPatientForm.value = true
}

function openEditPatientForm(patient: Patient) {
  editingPatientId.value = patient.patient_id
  patientForm.value = {
    full_name: patient.full_name,
    date_of_birth: patient.date_of_birth ?? '',
    age: patient.age === null ? '' : String(patient.age),
    sex: patient.sex ?? '',
    address: patient.address ?? '',
    contact_number: patient.contact_number ?? '',
    emergency_contact: patient.emergency_contact ?? '',
    room_number: patient.room_number === null ? '' : String(patient.room_number),
    philhealth_no: patient.philhealth_no ?? '',
  }
  patientFormError.value = ''
  patientFormStep.value = 'form'
  showPatientForm.value = true
}

function handlePatientFormSubmit() {
  if (patientFormStep.value === 'form') {
    patientFormError.value = ''
    patientFormStep.value = 'preview'
    return
  }
  submitPatientForm()
}

async function submitPatientForm() {
  isSavingPatient.value = true
  patientFormError.value = ''

  if (patientForm.value.contact_number && !/^\+?\d{7,15}$/.test(patientForm.value.contact_number)) {
    patientFormError.value = 'Invalid contact number format. Please enter a valid number.'
    isSavingPatient.value = false
    return
  }

  const { error } = editingPatientId.value === null
    ? await supabase.rpc('register_patient', {
        p_full_name: patientForm.value.full_name,
        p_date_of_birth: patientForm.value.date_of_birth || null,
        p_age: patientForm.value.age === '' ? null : Number(patientForm.value.age),
        p_contact_number: patientForm.value.contact_number || null,
        p_emergency_contact: patientForm.value.emergency_contact || null,
        p_room_number: patientForm.value.room_number === '' ? null : Number(patientForm.value.room_number),
        p_philhealth_no: patientForm.value.philhealth_no || null,
        p_attending_officer_id: officerId.value,
        p_sex: patientForm.value.sex || null,
        p_address: patientForm.value.address.trim() || null,
      })
    : await supabase.rpc('update_patient_info', {
        p_patient_id: editingPatientId.value,
        p_contact_number: patientForm.value.contact_number || null,
        p_emergency_contact: patientForm.value.emergency_contact || null,
        p_room_number: patientForm.value.room_number === '' ? null : Number(patientForm.value.room_number),
        p_sex: patientForm.value.sex || null,
        p_address: patientForm.value.address.trim() || null,
      })

  if (error) {
    patientFormError.value = error.message
    isSavingPatient.value = false
    return
  }

  showPatientForm.value = false
  isSavingPatient.value = false
  await loadDashboardData()
}
</script>

<template>
  <div>
    <DashboardShell
      v-model:section="activeSection"
      v-model:search="searchQuery"
      department="Nursing"
      role-label="Nurse"
      :nav-items="navItems"
    >
      <div v-if="dataError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
        <AlertTriangle class="h-4 w-4 shrink-0" />
        {{ dataError }}
      </div>

      <template v-if="activeSection === 'overview'">
        <div class="flex flex-wrap items-end justify-between gap-4">
          <div class="min-w-0 max-w-2xl">
            <p class="text-2xl font-bold tracking-tight sm:text-3xl">{{ wardHeadline }}</p>
            <p v-if="wardDetail" class="mt-1 text-sm text-muted-foreground">{{ wardDetail }}</p>
          </div>
          <div class="flex gap-2">
            <button
              type="button"
              class="rounded-md border border-input bg-card px-3 py-2 text-sm font-medium transition-colors hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
              :disabled="dischargeablePatients.length === 0"
              @click="openNewRequestForm"
            >
              Request Discharge
            </button>
            <button
              type="button"
              class="rounded-md bg-primary px-3 py-2 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90"
              @click="openNewPatientForm"
            >
              Add Patient
            </button>
          </div>
        </div>

        <div class="grid items-start gap-4 xl:grid-cols-3">
          <!-- Ward board: one cell per admitted patient, in room order -->
          <section class="overflow-hidden rounded-xl border border-border bg-card xl:col-span-2" aria-labelledby="ward-board-title">
            <div class="border-b border-border px-5 py-4">
              <h2 id="ward-board-title" class="text-base font-bold tracking-tight">Ward board</h2>
              <p class="text-xs text-muted-foreground">
                {{ searchQuery ? `Showing results for "${searchQuery}"` : 'Select a patient to open their chart' }}
              </p>
            </div>

            <ul v-if="wardBoard.length > 0" class="-mb-px -mr-px grid sm:grid-cols-2">
              <li v-for="{ patient, stage, day } in wardBoard" :key="patient.patient_id" class="border-b border-r border-border">
                <button
                  type="button"
                  class="flex h-full w-full gap-4 p-4 text-left transition-colors hover:bg-muted/60 focus-visible:-outline-offset-2"
                  @click="chartPatient = patient"
                >
                  <span class="w-14 shrink-0">
                    <span class="block text-xs text-muted-foreground">Room</span>
                    <span class="block text-3xl font-bold leading-tight tracking-tight tabular-nums">{{ patient.room_number ?? '—' }}</span>
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-semibold">{{ patient.full_name }}</span>
                    <span class="block text-xs text-muted-foreground">Day {{ day }} of stay</span>
                    <span class="mt-2.5 flex gap-1" aria-hidden="true">
                      <span
                        v-for="(step, i) in DISCHARGE_STEPS"
                        :key="step"
                        class="h-1.5 flex-1 rounded-full bg-muted"
                        :style="i <= stage.step ? { backgroundColor: stage.color } : undefined"
                      />
                    </span>
                    <span class="mt-1.5 block text-xs font-medium" :style="{ color: stage.color }">{{ stage.label }}</span>
                  </span>
                </button>
              </li>
            </ul>
            <div v-else-if="!isLoadingData" class="px-5 py-10 text-center text-sm text-muted-foreground">
              {{ searchQuery ? 'No admitted patients match your search.' : 'Add a patient to start your ward board.' }}
            </div>
          </section>

          <!-- Recent Discharge Requests -->
          <div class="rounded-xl border border-border bg-card p-5">
            <h2 class="text-base font-bold tracking-tight">Recent Discharge Requests</h2>
            <p class="text-xs text-muted-foreground">Your 5 latest submissions</p>

            <ul class="mt-4 divide-y divide-border">
              <li v-for="request in recentDischargeRequests" :key="request.request_id" class="flex items-center justify-between gap-3 py-2.5 text-sm">
                <div class="min-w-0">
                  <p class="truncate font-medium">{{ request.patient_name }}</p>
                  <p class="truncate text-xs text-muted-foreground">
                    {{ new Date(request.timestamp).toLocaleDateString() }}<template v-if="request.assigned_doctor_name">, sent to {{ request.assigned_doctor_name }}</template>
                  </p>
                </div>
                <span
                  class="inline-flex shrink-0 items-center gap-1.5 rounded-full px-2 py-1 text-xs font-medium capitalize"
                  :style="{ backgroundColor: `color-mix(in oklab, ${statusBarColor[request.status] ?? 'var(--neutral)'} 12%, transparent)`, color: statusBarColor[request.status] ?? 'var(--neutral)' }"
                >
                  <span class="h-1.5 w-1.5 rounded-full" :style="{ backgroundColor: statusBarColor[request.status] ?? 'var(--neutral)' }" />
                  {{ request.status.replace('_', ' ') }}
                </span>
              </li>
              <li v-if="recentDischargeRequests.length === 0" class="py-6 text-center text-sm text-muted-foreground">No discharge requests yet.</li>
            </ul>
          </div>
        </div>
      </template>

      <!-- Patients -->
      <div v-if="activeSection === 'patients'" class="rounded-xl border border-border bg-card p-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-bold tracking-tight">Patient Records</h2>
            <p class="text-xs text-muted-foreground">
              {{ searchQuery ? `Showing results for "${searchQuery}"` : 'Patients under your care' }}
            </p>
          </div>
          <button
            type="button"
            class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90"
            @click="openNewPatientForm"
          >
            Add Patient
          </button>
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
                <td class="py-2 pr-4 text-muted-foreground">{{ patient.discharge_date ? new Date(patient.discharge_date).toLocaleDateString() : '—' }}</td>
                <td class="py-2 text-right">
                  <div class="flex justify-end gap-3">
                    <button type="button" class="text-xs font-medium text-primary hover:underline" @click="chartPatient = patient">
                      Chart
                    </button>
                    <button type="button" class="text-xs font-medium text-primary hover:underline" @click="openEditPatientForm(patient)">
                      Edit
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!isLoadingData && filteredPatients.length === 0">
                <td colspan="6" class="py-6 text-center text-sm text-muted-foreground">
                  {{ searchQuery ? 'No patients match your search.' : 'No patients yet.' }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Discharge Requests -->
      <div v-if="activeSection === 'discharge-requests'" class="rounded-xl border border-border bg-card p-5">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h2 class="text-base font-bold tracking-tight">Discharge Requests</h2>
            <p class="text-xs text-muted-foreground">Patient records you've sent to a doctor for approval</p>
          </div>
          <button
            type="button"
            :disabled="dischargeablePatients.length === 0"
            class="rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
            @click="openNewRequestForm"
          >
            Request Discharge
          </button>
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Doctor</th>
                <th class="pb-2 pr-4 font-medium">Billed</th>
                <th class="pb-2 pr-4 font-medium">Submitted</th>
                <th class="pb-2 font-medium">Status</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="request in dischargeRequests" :key="request.request_id">
                <td class="py-2 pr-4 font-medium">{{ request.patient_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.assigned_doctor_name ?? '—' }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.status === 'completed' ? 'Yes' : 'No' }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ new Date(request.timestamp).toLocaleString() }}</td>
                <td class="py-2">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-xs font-medium capitalize"
                    :style="{ backgroundColor: `color-mix(in oklab, ${statusBarColor[request.status] ?? 'var(--neutral)'} 12%, transparent)`, color: statusBarColor[request.status] ?? 'var(--neutral)' }"
                  >
                    <span class="h-1.5 w-1.5 rounded-full" :style="{ backgroundColor: statusBarColor[request.status] ?? 'var(--neutral)' }" />
                    {{ request.status.replace('_', ' ') }}
                  </span>
                </td>
              </tr>
              <tr v-if="!isLoadingData && dischargeRequests.length === 0">
                <td colspan="5" class="py-6 text-center text-sm text-muted-foreground">No discharge requests yet.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

    </DashboardShell>

    <PatientChart
      v-if="chartPatient"
      :patient="chartPatient"
      :officer-id="officerId"
      :can-add="['vital_signs', 'nursing_note', 'medication', 'other']"
      @close="chartPatient = null"
    />

    <!-- Add / edit patient modal -->
    <FormModal
      v-if="showPatientForm"
      :title="patientFormTitle"
      :subtitle="patientFormSubtitle"
      :icon="UserRoundPlus"
      size="lg"
      :busy="isSavingPatient"
      @close="showPatientForm = false"
    >
      <form class="modal-form" @submit.prevent="handlePatientFormSubmit">
        <div v-if="patientFormStep === 'form'" class="modal-body">
          <section>
            <h3 class="field-group-title">Patient details</h3>
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="field sm:col-span-2">
                <label for="patient-name" class="field-label">Full name</label>
                <input id="patient-name" v-model="patientForm.full_name" type="text" required :disabled="editingPatientId !== null" class="field-input">
              </div>
              <div class="field">
                <label for="patient-age" class="field-label">Age</label>
                <input id="patient-age" v-model="patientForm.age" type="number" min="0" :disabled="editingPatientId !== null" class="field-input">
              </div>
              <div class="field">
                <label for="patient-dob" class="field-label">Date of birth</label>
                <input id="patient-dob" v-model="patientForm.date_of_birth" type="date" :disabled="editingPatientId !== null" class="field-input">
              </div>
              <div class="field">
                <label for="patient-sex" class="field-label">Sex</label>
                <select id="patient-sex" v-model="patientForm.sex" class="field-input">
                  <option value="">Not set</option>
                  <option value="Male">Male</option>
                  <option value="Female">Female</option>
                </select>
              </div>
              <div class="field">
                <label for="patient-philhealth" class="field-label">PhilHealth No.</label>
                <input id="patient-philhealth" v-model="patientForm.philhealth_no" type="text" :disabled="editingPatientId !== null" class="field-input">
              </div>
              <div class="field">
                <label for="patient-room" class="field-label">Room number</label>
                <input id="patient-room" v-model="patientForm.room_number" type="number" min="0" class="field-input">
              </div>
            </div>
          </section>

          <section>
            <h3 class="field-group-title">Contact</h3>
            <div class="grid gap-4 sm:grid-cols-2">
              <div class="field sm:col-span-2">
                <label for="patient-address" class="field-label">Address</label>
                <input id="patient-address" v-model="patientForm.address" type="text" class="field-input">
              </div>
              <div class="field">
                <label for="patient-contact" class="field-label">Contact number</label>
                <input id="patient-contact" v-model="patientForm.contact_number" type="text" class="field-input">
              </div>
              <div class="field">
                <label for="patient-emergency" class="field-label">Emergency contact</label>
                <input id="patient-emergency" v-model="patientForm.emergency_contact" type="text" class="field-input">
              </div>
            </div>
          </section>
        </div>

        <div v-else class="modal-body">
          <dl class="space-y-3">
            <div v-for="field in patientPreviewFields" :key="field.label" class="flex justify-between gap-4 border-b border-border pb-2 text-sm">
              <dt class="text-muted-foreground">{{ field.label }}</dt>
              <dd class="text-right font-medium">{{ field.value }}</dd>
            </div>
          </dl>

          <div v-if="patientFormError" class="form-error">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ patientFormError }}
          </div>
        </div>

        <div class="modal-footer">
          <button
            type="button"
            :disabled="isSavingPatient"
            class="btn-secondary"
            @click="patientFormStep === 'form' ? (showPatientForm = false) : (patientFormStep = 'form')"
          >
            {{ patientFormStep === 'form' ? 'Cancel' : 'Back' }}
          </button>
          <button type="submit" :disabled="isSavingPatient" class="btn-primary">
            <LoaderCircle v-if="isSavingPatient" class="h-4 w-4 animate-spin" />
            <template v-if="patientFormStep === 'form'">Next</template>
            <template v-else>{{ isSavingPatient ? 'Saving…' : 'Confirm & Save' }}</template>
          </button>
        </div>
      </form>
    </FormModal>

    <!-- New discharge request modal -->
    <FormModal
      v-if="showRequestForm"
      :title="requestFormStep === 'form' ? 'New Discharge Request' : 'Submit discharge request?'"
      :subtitle="requestFormStep === 'form'
        ? 'The doctor you choose reviews the chart. Once approved, billing computes the expenses.'
        : 'Check the details below before sending.'"
      :icon="DoorOpen"
      :size="requestFormStep === 'form' ? 'xl' : 'md'"
      :busy="isSavingRequest"
      @close="showRequestForm = false"
    >
      <form class="modal-form" @submit.prevent="handleRequestFormSubmit">
        <div v-if="requestFormStep === 'form'" class="modal-body">
          <div class="grid gap-5 sm:grid-cols-2">
            <fieldset class="field min-w-0">
              <legend class="field-label">Patient</legend>
              <div class="relative">
                <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <input
                  v-model="requestPatientSearch"
                  type="search"
                  aria-label="Search patients"
                  placeholder="Search patients…"
                  class="field-input pl-9"
                >
              </div>
              <div class="pick-list">
                <label v-for="patient in filteredRequestPatients" :key="patient.patient_id" class="pick-row">
                  <input v-model="requestPatientId" type="radio" name="request-patient" :value="patient.patient_id" class="sr-only">
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-medium">{{ patient.full_name }}</span>
                    <span class="block text-xs text-muted-foreground">Room {{ patient.room_number ?? '—' }}</span>
                  </span>
                  <Check v-if="requestPatientId === patient.patient_id" class="h-4 w-4 shrink-0" />
                </label>
                <p v-if="filteredRequestPatients.length === 0" class="px-2.5 py-2 text-sm text-muted-foreground">
                  No matching patients.
                </p>
              </div>
            </fieldset>

            <fieldset class="field min-w-0">
              <legend class="field-label">Send to doctor</legend>
              <div class="relative">
                <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
                <input
                  v-model="requestDoctorSearch"
                  type="search"
                  aria-label="Search doctors by name or field"
                  placeholder="Search name or field, e.g. Oncology"
                  class="field-input pl-9"
                >
              </div>
              <div class="pick-list">
                <label v-for="doctor in filteredRequestDoctors" :key="doctor.officer_id" class="pick-row">
                  <input v-model="requestDoctorId" type="radio" name="request-doctor" :value="doctor.officer_id" class="sr-only">
                  <span class="flex h-8 w-8 shrink-0 items-center justify-center rounded-md bg-secondary text-xs font-semibold text-secondary-foreground">
                    {{ initials(doctor.full_name) }}
                  </span>
                  <span class="min-w-0 flex-1">
                    <span class="block truncate font-medium">{{ doctor.full_name }}</span>
                    <span class="block truncate text-xs text-muted-foreground">{{ doctor.specialty ?? 'No field set' }}</span>
                    <span class="flex items-center gap-1.5 text-xs text-muted-foreground">
                      <span class="h-1.5 w-1.5 rounded-full" :class="doctor.duty_status === 'on_duty' ? 'bg-success' : 'bg-neutral'" />
                      {{ doctor.duty_status === 'on_duty' ? 'On duty' : 'Off duty' }}
                    </span>
                  </span>
                  <Check v-if="requestDoctorId === doctor.officer_id" class="h-4 w-4 shrink-0" />
                </label>
                <p v-if="filteredRequestDoctors.length === 0" class="px-2.5 py-2 text-sm text-muted-foreground">
                  {{ doctors.length === 0 ? 'No doctors registered. Ask an admin to add one.' : 'No matching doctors.' }}
                </p>
              </div>
            </fieldset>
          </div>
        </div>

        <div v-else class="modal-body">
          <dl class="space-y-3">
            <div class="flex justify-between gap-4 border-b border-border pb-2 text-sm">
              <dt class="text-muted-foreground">Patient</dt>
              <dd class="text-right font-medium">{{ selectedRequestPatientName }}</dd>
            </div>
            <div class="flex justify-between gap-4 border-b border-border pb-2 text-sm">
              <dt class="text-muted-foreground">Doctor</dt>
              <dd class="text-right font-medium">{{ selectedRequestDoctorName }}</dd>
            </div>
          </dl>

          <div v-if="requestFormError" class="form-error">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ requestFormError }}
          </div>
        </div>

        <div class="modal-footer">
          <button
            type="button"
            :disabled="isSavingRequest"
            class="btn-secondary"
            @click="requestFormStep === 'form' ? (showRequestForm = false) : (requestFormStep = 'form')"
          >
            {{ requestFormStep === 'form' ? 'Cancel' : 'Back' }}
          </button>
          <button
            type="submit"
            :disabled="isSavingRequest || requestPatientId === null || requestDoctorId === null"
            class="btn-primary"
          >
            <LoaderCircle v-if="isSavingRequest" class="h-4 w-4 animate-spin" />
            <template v-if="requestFormStep === 'form'">Next</template>
            <template v-else>{{ isSavingRequest ? 'Submitting…' : 'Submit Request' }}</template>
          </button>
        </div>
      </form>
    </FormModal>
  </div>
</template>
