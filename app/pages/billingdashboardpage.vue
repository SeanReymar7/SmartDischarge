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

  const { error } = await supabase.rpc('clear_billing', {
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
}

function chargeLabel(key: string) {
  return CHARGE_FIELDS.find((f) => f.key === key)?.label ?? key
}
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
                <th class="pb-2 font-medium">Billed</th>
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
                <td class="py-2 text-muted-foreground">
                  {{ new Date(record.created_at).toLocaleDateString() }}
                  <span class="block text-xs">{{ record.handled_by_name ?? '—' }}</span>
                </td>
              </tr>
              <tr v-if="!isLoadingData && filteredRecords.length === 0">
                <td colspan="6" class="py-6 text-center text-sm text-muted-foreground">No bills yet.</td>
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
    <div v-if="billingRequest" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/45 animate-in fade-in-0" @click="!isSavingBilling && (billingRequest = null)" />
      <div class="relative flex max-h-[90vh] w-full max-w-md flex-col rounded-xl border border-border bg-card p-6 shadow-lg animate-in fade-in-0 zoom-in-95 slide-in-from-bottom-2 duration-200">
        <h2 class="shrink-0 text-base font-semibold tracking-tight">Compute Bill</h2>
        <p class="mt-1 shrink-0 text-xs text-muted-foreground">
          For <span class="font-medium text-foreground">{{ billingRequest.patient_name }}</span>. Clearing the bill completes the discharge.
        </p>

        <form class="mt-4 flex min-h-0 flex-1 flex-col" @submit.prevent="submitBilling">
          <div class="min-h-0 flex-1 space-y-3 overflow-y-auto pr-1">
            <div v-for="field in CHARGE_FIELDS" :key="field.key" class="space-y-1.5">
              <label :for="`charge-${field.key}`" class="text-sm font-medium">{{ field.label }} (₱)</label>
              <input
                :id="`charge-${field.key}`"
                v-model="charges[field.key]"
                type="number"
                min="0"
                step="0.01"
                class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
            </div>
            <div class="space-y-1.5">
              <label for="billing-philhealth" class="text-sm font-medium">PhilHealth deduction (₱)</label>
              <input
                id="billing-philhealth"
                v-model="philhealthDeduction"
                type="number"
                min="0"
                step="0.01"
                class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
            </div>

            <dl class="space-y-1.5 rounded-md bg-muted px-3 py-2.5 text-sm">
              <div class="flex justify-between">
                <dt class="text-muted-foreground">Total amount</dt>
                <dd class="tabular-nums">{{ peso.format(totalAmount) }}</dd>
              </div>
              <div class="flex justify-between font-semibold">
                <dt>Net payable</dt>
                <dd class="tabular-nums">{{ peso.format(netPayable) }}</dd>
              </div>
            </dl>
          </div>

          <div v-if="billingFormError" class="mt-4 flex shrink-0 items-center gap-2 rounded-md bg-danger/10 px-3 py-2 text-xs text-danger">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ billingFormError }}
          </div>

          <div class="mt-4 flex shrink-0 gap-3">
            <button
              type="button"
              :disabled="isSavingBilling"
              class="flex-1 rounded-md border border-border py-2 text-sm font-medium transition-colors hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
              @click="billingRequest = null"
            >
              Cancel
            </button>
            <button
              type="submit"
              :disabled="isSavingBilling"
              class="flex flex-1 items-center justify-center gap-2 rounded-md bg-primary py-2 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <LoaderCircle v-if="isSavingBilling" class="h-4 w-4 animate-spin" />
              {{ isSavingBilling ? 'Saving…' : 'Clear Bill & Discharge' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
