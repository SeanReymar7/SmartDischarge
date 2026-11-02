<script setup lang="ts">
import {
  AlertTriangle,
  LoaderCircle,
  ReceiptText,
  WalletCards,
} from '@lucide/vue'
import { computed, onMounted, ref } from 'vue'
import type { BillingRecordRow, PatientRow } from '~/types/database.types'

definePageMeta({
  middleware: 'auth',
  requiredRole: 'billing',
})

useHead({
  title: 'Billing Dashboard — AHDMS',
  meta: [
    {
      name: 'description',
      content: 'Billing dashboard for the Automated Hospital Discharge Management System at Butuan Medical Center.',
    },
  ],
})

const supabase = useSupabaseClient()
const session = useAdminSession()
const officerId = computed(() => Number(session.value?.id))

const navItems = [
  { label: 'Awaiting Billing', icon: ReceiptText, section: 'billing' },
  { label: 'Billed', icon: WalletCards, section: 'billed' },
] as const

type Section = typeof navItems[number]['section']

const activeSection = ref<Section>('billing')

interface DischargeRequest {
  request_id: number
  patient_id: number
  patient_name: string
  requested_by_name: string
  approved_by_name: string | null
  timestamp: string
}

const CHARGE_FIELDS = [
  { key: 'room', label: 'Room & board' },
  { key: 'medicines', label: 'Medicines & supplies' },
  { key: 'laboratory', label: 'Laboratory & diagnostics' },
  { key: 'professional_fee', label: 'Professional fee' },
  { key: 'other', label: 'Other charges' },
] as const

const peso = new Intl.NumberFormat('en-PH', { style: 'currency', currency: 'PHP' })

const approvedRequests = ref<DischargeRequest[]>([])
const billingRecords = ref<BillingRecordRow[]>([])
const patients = ref<PatientRow[]>([])
const isLoadingData = ref(false)
const dataError = ref('')
const searchQuery = ref('')

async function loadDashboardData() {
  isLoadingData.value = true
  const errors: string[] = []

  const [requestsRes, recordsRes, patientsRes] = await Promise.all([
    supabase.rpc('list_discharge_requests_detailed', { p_status: 'approved' }),
    supabase.rpc('list_billing_records'),
    supabase.rpc('list_all_patients'),
  ])

  if (requestsRes.error) errors.push(`Discharge requests: ${requestsRes.error.message}`)
  else approvedRequests.value = requestsRes.data ?? []

  if (recordsRes.error) errors.push(`Billing records: ${recordsRes.error.message}`)
  else billingRecords.value = recordsRes.data ?? []

  if (patientsRes.error) errors.push(`Patients: ${patientsRes.error.message}`)
  else patients.value = patientsRes.data ?? []

  dataError.value = errors.join(' ')
  isLoadingData.value = false
}

onMounted(loadDashboardData)

function matchesSearch(name: string) {
  const q = searchQuery.value.trim().toLowerCase()
  return !q || name.toLowerCase().includes(q)
}

const filteredRequests = computed(() => approvedRequests.value.filter((r) => matchesSearch(r.patient_name)))
const filteredRecords = computed(() => billingRecords.value.filter((r) => matchesSearch(r.patient_name)))

// ── Patient chart (read-only: medication & records to bill from) ────────

const chartPatient = ref<PatientRow | null>(null)

function viewChart(patientId: number) {
  chartPatient.value = patients.value.find((p) => p.patient_id === patientId) ?? null
}

// ── Compute expenses & clear billing ────────────────────────────────────

const billingRequest = ref<DischargeRequest | null>(null)
const charges = ref<Record<string, string>>({})
const philhealthDeduction = ref('')
const isSavingBilling = ref(false)
const billingFormError = ref('')

const totalAmount = computed(() => CHARGE_FIELDS.reduce((sum, f) => sum + (Number(charges.value[f.key]) || 0), 0))
const netPayable = computed(() => totalAmount.value - (Number(philhealthDeduction.value) || 0))

function openBillingForm(request: DischargeRequest) {
  billingRequest.value = request
  charges.value = {}
  philhealthDeduction.value = ''
  billingFormError.value = ''
}

async function submitBilling() {
  if (!billingRequest.value) return

  const parsed: Record<string, number> = {}
  for (const field of CHARGE_FIELDS) {
    const amount = Number(charges.value[field.key] || 0)
    if (!Number.isFinite(amount) || amount < 0) {
      billingFormError.value = `Enter a valid amount for ${field.label.toLowerCase()}.`
      return
    }
    if (amount > 0) parsed[field.key] = amount
  }
  const deduction = Number(philhealthDeduction.value || 0)
  if (!Number.isFinite(deduction) || deduction < 0 || deduction > totalAmount.value) {
    billingFormError.value = 'PhilHealth deduction must be between 0 and the total amount.'
    return
  }

  isSavingBilling.value = true
  billingFormError.value = ''

  const { data, error } = await supabase.rpc('clear_billing', {
    p_request_id: billingRequest.value.request_id,
    p_handled_by: officerId.value,
    p_charges: parsed,
    p_philhealth_deduction: deduction,
  })

  isSavingBilling.value = false
  if (error) {
    billingFormError.value = error.message
    return
  }

  billingRequest.value = null
  await loadDashboardData()
  activeSection.value = 'billed'
  receiptRecord.value = billingRecords.value.find((r) => r.billing_id === data?.billing_id) ?? null
}

function chargeLabel(key: string) {
  return CHARGE_FIELDS.find((f) => f.key === key)?.label ?? key
}

// ── Discharge receipt ───────────────────────────────────────────────────

const receiptRecord = ref<BillingRecordRow | null>(null)

function receiptNumber(billingId: number) {
  return String(billingId).padStart(6, '0')
}

const longDate = new Intl.DateTimeFormat('en-PH', { dateStyle: 'long' })

function receiptDate(value: string | null) {
  if (!value) return '—'
  return longDate.format(new Date(value.length === 10 ? `${value}T00:00:00` : value))
}

const receiptRows = computed(() => {
  const record = receiptRecord.value
  if (!record) return []
  return [
    { label: 'Patient', value: record.patient_name },
    { label: 'PhilHealth No.', value: record.philhealth_no ?? '—' },
    { label: 'Room', value: record.room_number ?? '—' },
    { label: 'Admitted', value: receiptDate(record.admission_date) },
    { label: 'Discharged', value: receiptDate(record.discharge_date) },
    { label: 'Billed by', value: record.handled_by_name ?? '—' },
  ]
})
</script>

<template>
  <div>
    <DashboardShell
      v-model:section="activeSection"
      v-model:search="searchQuery"
      department="Billing"
      role-label="Billing officer"
      :nav-items="navItems"
      :badges="{ billing: approvedRequests.length }"
      :alert="approvedRequests.length > 0"
    >
      <div v-if="dataError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
        <AlertTriangle class="h-4 w-4 shrink-0" />
        {{ dataError }}
      </div>

      <!-- Awaiting Billing -->
      <div v-if="activeSection === 'billing'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Approved for Discharge</h2>
        <p class="text-xs text-muted-foreground">
          {{ searchQuery ? `Showing results for "${searchQuery}"` : 'The doctor approved these discharges. Compute the expenses to complete them.' }}
        </p>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Nurse</th>
                <th class="pb-2 pr-4 font-medium">Approved By</th>
                <th class="pb-2 pr-4 font-medium">Submitted</th>
                <th class="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="request in filteredRequests" :key="request.request_id">
                <td class="py-2 pr-4 font-medium">{{ request.patient_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.requested_by_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.approved_by_name ?? '—' }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ new Date(request.timestamp).toLocaleString() }}</td>
                <td class="py-2 text-right">
                  <div class="flex justify-end gap-3">
                    <button type="button" class="text-xs font-medium text-primary hover:underline" @click="viewChart(request.patient_id)">
                      Chart
                    </button>
                    <button type="button" class="text-xs font-medium text-primary hover:underline" @click="openBillingForm(request)">
                      Compute Bill
                    </button>
                  </div>
                </td>
              </tr>
              <tr v-if="!isLoadingData && filteredRequests.length === 0">
                <td colspan="5" class="py-6 text-center text-sm text-muted-foreground">Nothing awaiting billing.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Billed -->
      <div v-if="activeSection === 'billed'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Billing Records</h2>
        <p class="text-xs text-muted-foreground">Cleared bills, newest first</p>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Charges</th>
                <th class="pb-2 pr-4 text-right font-medium">Total</th>
                <th class="pb-2 pr-4 text-right font-medium">PhilHealth</th>
                <th class="pb-2 pr-4 text-right font-medium">Net Payable</th>
                <th class="pb-2 pr-4 font-medium">Billed</th>
                <th class="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="record in filteredRecords" :key="record.billing_id" class="align-top">
                <td class="py-2 pr-4 font-medium">{{ record.patient_name }}</td>
                <td class="py-2 pr-4 text-xs text-muted-foreground">
                  <div v-for="(amount, key) in record.charges" :key="key">{{ chargeLabel(String(key)) }}: {{ peso.format(amount) }}</div>
                </td>
                <td class="py-2 pr-4 text-right tabular-nums">{{ peso.format(record.total_amount) }}</td>
                <td class="py-2 pr-4 text-right tabular-nums text-muted-foreground">−{{ peso.format(record.philhealth_deduction) }}</td>
                <td class="py-2 pr-4 text-right font-medium tabular-nums">{{ peso.format(record.total_amount - record.philhealth_deduction) }}</td>
                <td class="py-2 pr-4 text-muted-foreground">
                  {{ new Date(record.created_at).toLocaleDateString() }}
                  <span class="block text-xs">{{ record.handled_by_name ?? '—' }}</span>
                </td>
                <td class="py-2 text-right">
                  <button type="button" class="text-xs font-medium text-primary hover:underline" @click="receiptRecord = record">
                    Receipt
                  </button>
                </td>
              </tr>
              <tr v-if="!isLoadingData && filteredRecords.length === 0">
                <td colspan="7" class="py-6 text-center text-sm text-muted-foreground">No bills yet.</td>
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
      :can-add="[]"
      @close="chartPatient = null"
    />

    <!-- Compute bill modal -->
    <FormModal
      v-if="billingRequest"
      title="Compute Bill"
      :subtitle="`For ${billingRequest.patient_name}. Clearing the bill completes the discharge.`"
      :icon="ReceiptText"
      size="lg"
      :busy="isSavingBilling"
      @close="billingRequest = null"
    >
      <form class="modal-form" @submit.prevent="submitBilling">
        <div class="modal-body">
          <section>
            <h3 class="field-group-title">Charges</h3>
            <div class="grid gap-4 sm:grid-cols-2">
              <div v-for="field in CHARGE_FIELDS" :key="field.key" class="field">
                <label :for="`charge-${field.key}`" class="field-label">{{ field.label }} (₱)</label>
                <input :id="`charge-${field.key}`" v-model="charges[field.key]" type="number" min="0" step="0.01" class="field-input tabular-nums">
              </div>
            </div>
          </section>

          <div class="field">
            <label for="billing-philhealth" class="field-label">PhilHealth deduction (₱)</label>
            <input id="billing-philhealth" v-model="philhealthDeduction" type="number" min="0" step="0.01" class="field-input tabular-nums">
          </div>

          <dl class="rounded-md bg-sidebar px-4 py-3 text-sm text-sidebar-foreground">
            <div class="flex justify-between">
              <dt>Total amount</dt>
              <dd class="tabular-nums">{{ peso.format(totalAmount) }}</dd>
            </div>
            <div class="mt-1 flex items-baseline justify-between text-sidebar-accent-foreground">
              <dt class="font-semibold">Net payable</dt>
              <dd class="text-xl font-bold tracking-tight tabular-nums">{{ peso.format(netPayable) }}</dd>
            </div>
          </dl>

          <div v-if="billingFormError" class="form-error">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ billingFormError }}
          </div>
        </div>

        <div class="modal-footer">
          <button type="button" :disabled="isSavingBilling" class="btn-secondary" @click="billingRequest = null">
            Cancel
          </button>
          <button type="submit" :disabled="isSavingBilling" class="btn-primary">
            <LoaderCircle v-if="isSavingBilling" class="h-4 w-4 animate-spin" />
            {{ isSavingBilling ? 'Saving…' : 'Clear Bill & Discharge' }}
          </button>
        </div>
      </form>
    </FormModal>

    <!-- Discharge receipt -->
    <PrintPreview v-if="receiptRecord" label="Discharge receipt" @close="receiptRecord = null">
      <!-- Black rules only, so it prints the same on any office printer -->
      <header class="flex items-start justify-between gap-6 border-b-2 border-black pb-4">
        <div class="flex items-center gap-3">
          <AppLogo class="h-11 w-11 shrink-0" />
          <div class="leading-tight">
            <p class="text-xl font-bold tracking-tight">Butuan Medical Center</p>
            <p class="text-xs">Km. 5, Baan, Butuan City</p>
          </div>
        </div>
        <div class="text-right leading-tight">
          <h1 class="text-sm font-bold">Discharge Billing Receipt</h1>
          <p class="mt-1 text-xl font-bold tabular-nums">No. {{ receiptNumber(receiptRecord.billing_id) }}</p>
          <p class="text-xs">{{ receiptDate(receiptRecord.created_at) }}</p>
        </div>
      </header>

      <dl class="mt-5 grid grid-cols-2 gap-x-10 gap-y-2 text-sm">
        <div v-for="row in receiptRows" :key="row.label" class="flex justify-between gap-4">
          <dt class="text-black/70">{{ row.label }}</dt>
          <dd class="text-right font-semibold">{{ row.value }}</dd>
        </div>
      </dl>

      <table class="mt-8 w-full text-sm">
        <thead>
          <tr class="border-b border-black text-left">
            <th class="pb-1.5 font-semibold">Charge</th>
            <th class="pb-1.5 text-right font-semibold">Amount</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="(amount, key) in receiptRecord.charges" :key="key" class="border-b border-black/15">
            <td class="py-2">{{ chargeLabel(String(key)) }}</td>
            <td class="py-2 text-right tabular-nums">{{ peso.format(amount) }}</td>
          </tr>
          <tr v-if="Object.keys(receiptRecord.charges).length === 0" class="border-b border-black/15">
            <td colspan="2" class="py-2">No charges recorded.</td>
          </tr>
        </tbody>
      </table>

      <!-- Accounting convention: a double rule closes the final amount -->
      <dl class="ml-auto mt-4 w-72 text-sm">
        <div class="flex justify-between py-1">
          <dt>Total amount</dt>
          <dd class="tabular-nums">{{ peso.format(receiptRecord.total_amount) }}</dd>
        </div>
        <div class="flex justify-between py-1">
          <dt>PhilHealth deduction</dt>
          <dd class="tabular-nums">−{{ peso.format(receiptRecord.philhealth_deduction) }}</dd>
        </div>
        <div class="mt-1 flex items-baseline justify-between border-t border-b-4 border-t-black border-b-black py-2 [border-bottom-style:double]">
          <dt class="font-bold">Net payable</dt>
          <dd class="text-2xl font-bold tracking-tight tabular-nums">{{ peso.format(receiptRecord.total_amount - receiptRecord.philhealth_deduction) }}</dd>
        </div>
      </dl>

      <footer class="ml-auto mt-14 w-72 break-inside-avoid text-center text-sm">
        <p class="border-b border-black pb-1 font-semibold">{{ receiptRecord.handled_by_name ?? '' }}</p>
        <p class="mt-1 text-xs">Billing officer's signature over printed name</p>
      </footer>

      <p class="mt-6 text-xs text-black/70">This is a billing statement. It does not replace the official receipt from the Cashier.</p>

      <!-- Tear-off stub the hospital keeps -->
      <section class="mt-8 break-inside-avoid border-t-2 border-dashed border-black pt-4 text-sm">
        <div class="flex items-baseline justify-between gap-4">
          <h2 class="font-bold">Hospital copy</h2>
          <p class="font-bold tabular-nums">No. {{ receiptNumber(receiptRecord.billing_id) }}</p>
        </div>
        <div class="mt-3 flex items-end justify-between gap-10">
          <div class="min-w-0">
            <p class="truncate font-semibold">{{ receiptRecord.patient_name }}</p>
            <p class="text-xs">Net payable {{ peso.format(receiptRecord.total_amount - receiptRecord.philhealth_deduction) }}</p>
          </div>
          <div class="w-64 shrink-0 text-center">
            <p class="border-b border-black pb-5" />
            <p class="mt-1 text-xs">Received by patient or representative</p>
          </div>
        </div>
      </section>
    </PrintPreview>
  </div>
</template>
