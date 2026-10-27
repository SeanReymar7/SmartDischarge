<script setup lang="ts">
import {
  AlertTriangle,
  CheckCircle2,
  ClipboardCheck,
  LayoutDashboard,
  LoaderCircle,
  ReceiptText,
} from '@lucide/vue'
import { computed, onMounted, ref } from 'vue'
import type { BillingRow } from '~/types/database.types'

definePageMeta({
  middleware: 'auth',
  requiredRole: 'billing',
})

useHead({
  title: 'Billing Dashboard — AHDMS',
  meta: [
    {
      name: 'description',
      content: 'Billing & PhilHealth clearance dashboard for the Automated Hospital Discharge Management System at Butuan Medical Center.',
    },
  ],
})

const supabase = useSupabaseClient()
const session = useAdminSession()
const officerId = computed(() => Number(session.value?.id))

const navItems = [
  { label: 'Overview', icon: LayoutDashboard, section: 'overview' },
  { label: 'My Tasks', icon: ClipboardCheck, section: 'tasks' },
  { label: 'Pending Billing', icon: ReceiptText, section: 'billing' },
] as const

type Section = typeof navItems[number]['section']

const activeSection = ref<Section>('overview')

interface BillingTask {
  task_id: number
  discharge_request_id: number
  patient_id: number
  patient_name: string
  task_type: string
  status: string
  created_at: string
}

interface DischargeRequest {
  request_id: number
  patient_id: number
  patient_name: string
  requested_by_name: string
  status: string
  billing_verified: boolean
  timestamp: string
}

const tasks = ref<BillingTask[]>([])
const dischargeRequests = ref<DischargeRequest[]>([])
const isLoadingData = ref(false)
const dataError = ref('')
const searchQuery = ref('')

async function loadDashboardData() {
  isLoadingData.value = true
  const errors: string[] = []

  const [tasksRes, requestsRes] = await Promise.all([
    supabase.rpc('list_tasks_for_officer_detailed', { p_officer_id: officerId.value }),
    supabase.rpc('list_discharge_requests_detailed', { p_status: null }),
  ])

  if (tasksRes.error) errors.push(`Tasks: ${tasksRes.error.message}`)
  else tasks.value = tasksRes.data ?? []

  if (requestsRes.error) errors.push(`Discharge requests: ${requestsRes.error.message}`)
  else dischargeRequests.value = requestsRes.data ?? []

  dataError.value = errors.join(' ')
  isLoadingData.value = false
}

onMounted(loadDashboardData)

const billingTasks = computed(() => tasks.value.filter((t) => t.task_type === 'billing_clearance'))
const philhealthTasks = computed(() => tasks.value.filter((t) => t.task_type === 'philhealth_documentation'))
const pendingTasks = computed(() => tasks.value.filter((t) => t.status !== 'done'))

const unverifiedRequests = computed(() => {
  const q = searchQuery.value.trim().toLowerCase()
  return dischargeRequests.value
    .filter((r) => !r.billing_verified && (r.status === 'pending' || r.status === 'in_progress'))
    .filter((r) => !q || r.patient_name.toLowerCase().includes(q))
})

// ── Complete billing / PhilHealth tasks ─────────────────────────────────

const completingTaskId = ref<number | null>(null)
const taskActionError = ref('')

async function completeTask(taskId: number) {
  completingTaskId.value = taskId
  taskActionError.value = ''

  const { error } = await supabase.rpc('complete_task', { p_task_id: taskId })

  if (error) {
    taskActionError.value = error.message
    completingTaskId.value = null
    return
  }

  completingTaskId.value = null
  await loadDashboardData()
}

// ── Clear billing (create + verify) ─────────────────────────────────────

const clearingRequest = ref<DischargeRequest | null>(null)
const billingForm = ref({ total_amount: '', philhealth_deduction: '' })
const isSavingBilling = ref(false)
const billingFormError = ref('')

function openClearBillingForm(request: DischargeRequest) {
  clearingRequest.value = request
  billingForm.value = { total_amount: '', philhealth_deduction: '' }
  billingFormError.value = ''
}

async function submitClearBilling() {
  if (!clearingRequest.value) return

  const totalAmount = Number(billingForm.value.total_amount)
  const philhealthDeduction = Number(billingForm.value.philhealth_deduction || 0)

  if (!Number.isFinite(totalAmount) || totalAmount < 0) {
    billingFormError.value = 'Enter a valid total amount.'
    return
  }
  if (!Number.isFinite(philhealthDeduction) || philhealthDeduction < 0) {
    billingFormError.value = 'Enter a valid PhilHealth deduction.'
    return
  }

  isSavingBilling.value = true
  billingFormError.value = ''

  const { data: billing, error: createError } = await supabase
    .rpc('create_billing_record', {
      p_discharge_request_id: clearingRequest.value.request_id,
      p_patient_id: clearingRequest.value.patient_id,
      p_total_amount: totalAmount,
      p_philhealth_deduction: philhealthDeduction,
    })
    .overrideTypes<BillingRow>()

  if (createError || !billing) {
    billingFormError.value = createError?.message ?? 'Could not create billing record.'
    isSavingBilling.value = false
    return
  }

  const { error: verifyError } = await supabase.rpc('verify_billing', { p_billing_id: billing.billing_id })

  if (verifyError) {
    billingFormError.value = verifyError.message
    isSavingBilling.value = false
    return
  }

  clearingRequest.value = null
  isSavingBilling.value = false
  await loadDashboardData()
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
      :badges="{ tasks: pendingTasks.length }"
      :alert="pendingTasks.length > 0"
    >
      <div v-if="dataError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
        <AlertTriangle class="h-4 w-4 shrink-0" />
        {{ dataError }}
      </div>

      <template v-if="activeSection === 'overview'">
        <div class="grid gap-4 sm:grid-cols-3">
          <div class="rounded-xl border border-border bg-card p-5">
            <span class="flex h-9 w-9 items-center justify-center rounded-md bg-primary/10 text-primary">
              <ClipboardCheck class="h-4.5 w-4.5" />
            </span>
            <p class="mt-4 text-2xl font-semibold tracking-tight tabular-nums">{{ pendingTasks.length }}</p>
            <p class="mt-1 text-sm text-muted-foreground">Open Tasks</p>
          </div>
          <div class="rounded-xl border border-border bg-card p-5">
            <span class="flex h-9 w-9 items-center justify-center rounded-md bg-warning/10 text-warning">
              <ReceiptText class="h-4.5 w-4.5" />
            </span>
            <p class="mt-4 text-2xl font-semibold tracking-tight tabular-nums">{{ unverifiedRequests.length }}</p>
            <p class="mt-1 text-sm text-muted-foreground">Awaiting Billing Clearance</p>
          </div>
          <div class="rounded-xl border border-border bg-card p-5">
            <span class="flex h-9 w-9 items-center justify-center rounded-md bg-success/10 text-success">
              <CheckCircle2 class="h-4.5 w-4.5" />
            </span>
            <p class="mt-4 text-2xl font-semibold tracking-tight tabular-nums">{{ tasks.filter((t) => t.status === 'done').length }}</p>
            <p class="mt-1 text-sm text-muted-foreground">Tasks Completed</p>
          </div>
        </div>

        <div v-if="pendingTasks.length > 0" class="flex items-center gap-2 rounded-md bg-warning/10 px-3 py-2.5 text-sm text-warning">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ pendingTasks.length }} billing/PhilHealth task{{ pendingTasks.length === 1 ? '' : 's' }} still awaiting completion.
        </div>

        <div class="grid gap-4 lg:grid-cols-2">
          <div class="rounded-xl border border-border bg-card p-5">
            <h2 class="text-base font-bold tracking-tight">Billing Clearance</h2>
            <p class="text-xs text-muted-foreground">{{ billingTasks.length }} task{{ billingTasks.length === 1 ? '' : 's' }} assigned</p>
            <ul class="mt-4 divide-y divide-border">
              <li v-for="task in billingTasks.slice(0, 5)" :key="task.task_id" class="flex items-center justify-between gap-3 py-2.5 text-sm">
                <p class="truncate font-medium">{{ task.patient_name }}</p>
                <span
                  class="shrink-0 rounded-full px-2 py-1 text-xs font-medium"
                  :class="task.status === 'done' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'"
                >
                  {{ task.status === 'done' ? 'Done' : 'Pending' }}
                </span>
              </li>
              <li v-if="billingTasks.length === 0" class="py-6 text-center text-sm text-muted-foreground">No billing tasks yet.</li>
            </ul>
          </div>
          <div class="rounded-xl border border-border bg-card p-5">
            <h2 class="text-base font-bold tracking-tight">PhilHealth Documentation</h2>
            <p class="text-xs text-muted-foreground">{{ philhealthTasks.length }} task{{ philhealthTasks.length === 1 ? '' : 's' }} assigned</p>
            <ul class="mt-4 divide-y divide-border">
              <li v-for="task in philhealthTasks.slice(0, 5)" :key="task.task_id" class="flex items-center justify-between gap-3 py-2.5 text-sm">
                <p class="truncate font-medium">{{ task.patient_name }}</p>
                <span
                  class="shrink-0 rounded-full px-2 py-1 text-xs font-medium"
                  :class="task.status === 'done' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'"
                >
                  {{ task.status === 'done' ? 'Done' : 'Pending' }}
                </span>
              </li>
              <li v-if="philhealthTasks.length === 0" class="py-6 text-center text-sm text-muted-foreground">No PhilHealth tasks yet.</li>
            </ul>
          </div>
        </div>
      </template>

      <!-- My Tasks -->
      <div v-if="activeSection === 'tasks'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Billing & PhilHealth Tasks</h2>
        <p class="text-xs text-muted-foreground">Auto-assigned when a discharge request is filed</p>

        <div v-if="taskActionError" class="mt-4 flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ taskActionError }}
        </div>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Task</th>
                <th class="pb-2 pr-4 font-medium">Assigned</th>
                <th class="pb-2 pr-4 font-medium">Status</th>
                <th class="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="task in tasks" :key="task.task_id">
                <td class="py-2 pr-4 font-medium">{{ task.patient_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">
                  {{ task.task_type === 'billing_clearance' ? 'Billing Clearance' : 'PhilHealth Documentation' }}
                </td>
                <td class="py-2 pr-4 text-muted-foreground">{{ new Date(task.created_at).toLocaleString() }}</td>
                <td class="py-2 pr-4">
                  <span
                    class="inline-flex items-center gap-1.5 rounded-full px-2 py-1 text-xs font-medium"
                    :class="task.status === 'done' ? 'bg-success/10 text-success' : 'bg-muted text-muted-foreground'"
                  >
                    <CheckCircle2 v-if="task.status === 'done'" class="h-3.5 w-3.5" />
                    {{ task.status === 'done' ? 'Done' : 'Pending' }}
                  </span>
                </td>
                <td class="py-2 text-right">
                  <button
                    v-if="task.status !== 'done'"
                    type="button"
                    :disabled="completingTaskId === task.task_id"
                    class="text-xs font-medium text-primary hover:underline disabled:cursor-not-allowed disabled:opacity-60"
                    @click="completeTask(task.task_id)"
                  >
                    {{ completingTaskId === task.task_id ? 'Completing…' : 'Mark Complete' }}
                  </button>
                </td>
              </tr>
              <tr v-if="!isLoadingData && tasks.length === 0">
                <td colspan="5" class="py-6 text-center text-sm text-muted-foreground">No tasks assigned yet.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Pending Billing -->
      <div v-if="activeSection === 'billing'" class="rounded-xl border border-border bg-card p-5">
        <h2 class="text-base font-bold tracking-tight">Discharge Requests Awaiting Billing Clearance</h2>
        <p class="text-xs text-muted-foreground">
          {{ searchQuery ? `Showing results for "${searchQuery}"` : 'Compute the bill and clear it so the doctor can finalize the discharge.' }}
        </p>

        <div class="mt-4 overflow-x-auto">
          <table class="w-full text-sm">
            <thead>
              <tr class="border-b border-border text-left text-xs text-muted-foreground">
                <th class="pb-2 pr-4 font-medium">Patient</th>
                <th class="pb-2 pr-4 font-medium">Requested By</th>
                <th class="pb-2 pr-4 font-medium">Submitted</th>
                <th class="pb-2 font-medium" />
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="request in unverifiedRequests" :key="request.request_id">
                <td class="py-2 pr-4 font-medium">{{ request.patient_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ request.requested_by_name }}</td>
                <td class="py-2 pr-4 text-muted-foreground">{{ new Date(request.timestamp).toLocaleString() }}</td>
                <td class="py-2 text-right">
                  <button type="button" class="text-xs font-medium text-primary hover:underline" @click="openClearBillingForm(request)">
                    Clear Billing
                  </button>
                </td>
              </tr>
              <tr v-if="!isLoadingData && unverifiedRequests.length === 0">
                <td colspan="4" class="py-6 text-center text-sm text-muted-foreground">Nothing awaiting billing clearance.</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </DashboardShell>

    <!-- Clear billing modal -->
    <div v-if="clearingRequest" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/45 animate-in fade-in-0" @click="!isSavingBilling && (clearingRequest = null)" />
      <div class="relative w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-lg animate-in fade-in-0 zoom-in-95 slide-in-from-bottom-2 duration-200">
        <h2 class="text-base font-semibold tracking-tight">Clear Billing</h2>
        <p class="mt-1 text-xs text-muted-foreground">
          For <span class="font-medium text-foreground">{{ clearingRequest.patient_name }}</span>. This records the bill and marks it verified.
        </p>

        <form class="mt-4 space-y-4" @submit.prevent="submitClearBilling">
          <div class="space-y-1.5">
            <label for="billing-total" class="text-sm font-medium">Total amount (₱)</label>
            <input
              id="billing-total"
              v-model="billingForm.total_amount"
              type="number"
              min="0"
              step="0.01"
              required
              class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
          </div>
          <div class="space-y-1.5">
            <label for="billing-philhealth" class="text-sm font-medium">PhilHealth deduction (₱)</label>
            <input
              id="billing-philhealth"
              v-model="billingForm.philhealth_deduction"
              type="number"
              min="0"
              step="0.01"
              class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
          </div>

          <div v-if="billingFormError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2 text-xs text-danger">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ billingFormError }}
          </div>

          <div class="flex gap-3 pt-2">
            <button
              type="button"
              :disabled="isSavingBilling"
              class="flex-1 rounded-md border border-border py-2 text-sm font-medium transition-colors hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
              @click="clearingRequest = null"
            >
              Cancel
            </button>
            <button
              type="submit"
              :disabled="isSavingBilling"
              class="flex flex-1 items-center justify-center gap-2 rounded-md bg-primary py-2 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <LoaderCircle v-if="isSavingBilling" class="h-4 w-4 animate-spin" />
              {{ isSavingBilling ? 'Saving…' : 'Clear Billing' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>
