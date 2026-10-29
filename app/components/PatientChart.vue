<script setup lang="ts">
import { AlertTriangle, LoaderCircle } from '@lucide/vue'
import type { ChartEntryRow, ChartEntryType, PatientRow } from '~/types/database.types'

// The patient chart: nurses record vitals / notes / medication / other,
// doctors add advice. `canAdd` lists the entry types this viewer may add;
// leave it empty for a read-only chart (billing).
const props = defineProps<{
  patient: Pick<PatientRow, 'patient_id' | 'full_name' | 'age' | 'room_number' | 'admission_date' | 'philhealth_no'>
  officerId: number
  canAdd: ChartEntryType[]
}>()

const emit = defineEmits<{ close: [] }>()

const ENTRY_TYPES: Record<ChartEntryType, { label: string, fields: { key: string, label: string, multiline?: boolean, placeholder?: string }[] }> = {
  vital_signs: {
    label: 'Vital Signs',
    fields: [
      { key: 'blood_pressure', label: 'Blood pressure (mmHg)', placeholder: '120/80' },
      { key: 'pulse', label: 'Pulse (bpm)' },
      { key: 'respiratory_rate', label: 'Respiratory rate (/min)' },
      { key: 'temperature', label: 'Temperature (°C)' },
      { key: 'oxygen_saturation', label: 'SpO₂ (%)' },
    ],
  },
  nursing_note: {
    label: 'Nursing Notes',
    fields: [{ key: 'note', label: 'Note', multiline: true }],
  },
  medication: {
    label: 'Medication',
    fields: [
      { key: 'medicine', label: 'Medicine' },
      { key: 'dose', label: 'Dose' },
      { key: 'route', label: 'Route', placeholder: 'Oral, IV, IM…' },
      { key: 'remarks', label: 'Remarks' },
    ],
  },
  other: {
    label: 'Other Records',
    fields: [
      { key: 'title', label: 'Record', placeholder: 'Lab result, procedure…' },
      { key: 'note', label: 'Details', multiline: true },
    ],
  },
  doctor_order: {
    label: "Doctor's Advice",
    fields: [{ key: 'note', label: 'Advice / orders', multiline: true }],
  },
}

const supabase = useSupabaseClient()

const entries = ref<ChartEntryRow[]>([])
const isLoading = ref(false)
const loadError = ref('')
const filter = ref<ChartEntryType | 'all'>('all')

async function loadEntries() {
  isLoading.value = true
  const { data, error } = await supabase.rpc('list_chart_entries', { p_patient_id: props.patient.patient_id })
  loadError.value = error?.message ?? ''
  entries.value = data ?? []
  isLoading.value = false
}

onMounted(loadEntries)

const filteredEntries = computed(() => filter.value === 'all' ? entries.value : entries.value.filter((e) => e.entry_type === filter.value))

function filledFields(entry: ChartEntryRow) {
  return ENTRY_TYPES[entry.entry_type].fields
    .filter((f) => entry.details[f.key])
    .map((f) => ({ label: f.label, value: entry.details[f.key] }))
}

// ── Add entry ─────────────────────────────────────────────────────────

const newType = ref<ChartEntryType | null>(props.canAdd[0] ?? null)
const newDetails = ref<Record<string, string>>({})
const isSaving = ref(false)
const saveError = ref('')

async function addEntry() {
  if (!newType.value) return
  const details = Object.fromEntries(
    Object.entries(newDetails.value).map(([k, v]) => [k, v.trim()]).filter(([, v]) => v),
  )
  if (Object.keys(details).length === 0) {
    saveError.value = 'Fill in at least one field.'
    return
  }

  isSaving.value = true
  saveError.value = ''

  const { error } = await supabase.rpc('add_chart_entry', {
    p_patient_id: props.patient.patient_id,
    p_recorded_by: props.officerId,
    p_entry_type: newType.value,
    p_details: details,
  })

  isSaving.value = false
  if (error) {
    saveError.value = error.message
    return
  }

  newDetails.value = {}
  await loadEntries()
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
    <div class="absolute inset-0 bg-black/45 animate-in fade-in-0" @click="!isSaving && emit('close')" />
    <div role="dialog" aria-modal="true" aria-labelledby="chart-title" class="relative flex max-h-[90vh] w-full max-w-2xl flex-col rounded-xl border border-border bg-card p-6 shadow-lg animate-in fade-in-0 zoom-in-95 slide-in-from-bottom-2 duration-200">
      <div class="shrink-0">
        <h2 id="chart-title" class="text-base font-semibold tracking-tight">Patient Chart — {{ patient.full_name }}</h2>
        <p class="mt-1 text-xs text-muted-foreground">
          Age {{ patient.age ?? '—' }} · Room {{ patient.room_number ?? '—' }} · Admitted {{ patient.admission_date }}
          · PhilHealth {{ patient.philhealth_no ?? '—' }}
        </p>
      </div>

      <div class="mt-4 min-h-0 flex-1 space-y-4 overflow-y-auto pr-1">
        <!-- Add entry -->
        <form v-if="canAdd.length > 0" class="space-y-3 rounded-lg border border-border p-4" @submit.prevent="addEntry">
          <div class="flex flex-wrap gap-1.5">
            <button
              v-for="type in canAdd"
              :key="type"
              type="button"
              class="rounded-md px-2.5 py-1 text-xs font-medium transition-colors"
              :class="newType === type ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:text-foreground'"
              @click="newType = type; newDetails = {}; saveError = ''"
            >
              {{ ENTRY_TYPES[type].label }}
            </button>
          </div>

          <div v-if="newType" class="grid gap-3 sm:grid-cols-2">
            <div
              v-for="field in ENTRY_TYPES[newType].fields"
              :key="field.key"
              class="space-y-1.5"
              :class="field.multiline ? 'sm:col-span-2' : ''"
            >
              <label :for="`chart-${field.key}`" class="text-sm font-medium">{{ field.label }}</label>
              <textarea
                v-if="field.multiline"
                :id="`chart-${field.key}`"
                v-model="newDetails[field.key]"
                rows="3"
                class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring"
              />
              <input
                v-else
                :id="`chart-${field.key}`"
                v-model="newDetails[field.key]"
                type="text"
                :placeholder="field.placeholder"
                class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
              >
            </div>
          </div>

          <div v-if="saveError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2 text-xs text-danger">
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ saveError }}
          </div>

          <div class="flex justify-end">
            <button
              type="submit"
              :disabled="isSaving"
              class="flex items-center gap-2 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
            >
              <LoaderCircle v-if="isSaving" class="h-3.5 w-3.5 animate-spin" />
              {{ isSaving ? 'Saving…' : 'Add to Chart' }}
            </button>
          </div>
        </form>

        <!-- Entries -->
        <div class="flex flex-wrap gap-1.5">
          <button
            v-for="key in (['all', ...Object.keys(ENTRY_TYPES)] as const)"
            :key="key"
            type="button"
            class="rounded-full px-2.5 py-1 text-xs font-medium transition-colors"
            :class="filter === key ? 'bg-foreground text-background' : 'bg-muted text-muted-foreground hover:text-foreground'"
            @click="filter = key as ChartEntryType | 'all'"
          >
            {{ key === 'all' ? 'All' : ENTRY_TYPES[key as ChartEntryType].label }}
          </button>
        </div>

        <div v-if="loadError" class="flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2 text-xs text-danger">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ loadError }}
        </div>

        <ul class="divide-y divide-border">
          <li v-for="entry in filteredEntries" :key="entry.entry_id" class="py-3 text-sm">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <span class="font-medium">{{ ENTRY_TYPES[entry.entry_type].label }}</span>
              <span class="text-xs text-muted-foreground">
                {{ entry.recorded_by_name }} ({{ entry.recorded_by_role }}) · {{ new Date(entry.created_at).toLocaleString() }}
              </span>
            </div>
            <dl class="mt-1.5 space-y-1">
              <div v-for="field in filledFields(entry)" :key="field.label" class="flex gap-3">
                <dt class="w-32 shrink-0 text-muted-foreground sm:w-44">{{ field.label }}</dt>
                <dd class="min-w-0 whitespace-pre-line break-words">{{ field.value }}</dd>
              </div>
            </dl>
          </li>
          <li v-if="!isLoading && filteredEntries.length === 0" class="py-6 text-center text-sm text-muted-foreground">
            No chart entries yet.
          </li>
        </ul>
      </div>

      <div class="mt-4 flex shrink-0 gap-3">
        <button
          type="button"
          :disabled="isSaving"
          class="flex-1 rounded-md border border-border py-2 text-sm font-medium transition-colors hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
          @click="emit('close')"
        >
          Close
        </button>
        <slot name="actions" />
      </div>
    </div>
  </div>
</template>
