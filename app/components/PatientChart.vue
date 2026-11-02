<script setup lang="ts">
import { AlertTriangle, ClipboardList, LoaderCircle } from '@lucide/vue'
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

// ── Edit entry ────────────────────────────────────────────────────────

const editingEntryId = ref<number | null>(null)
const editDetails = ref<Record<string, string>>({})
const editError = ref('')

function canEdit(entry: ChartEntryRow) {
  return entry.recorded_by === props.officerId && props.canAdd.includes(entry.entry_type)
}

function startEdit(entry: ChartEntryRow) {
  editingEntryId.value = entry.entry_id
  editDetails.value = { ...entry.details }
  editError.value = ''
}

function cancelEdit() {
  editingEntryId.value = null
  editError.value = ''
}

async function saveEdit() {
  if (editingEntryId.value === null) return
  const details = Object.fromEntries(
    Object.entries(editDetails.value).map(([k, v]) => [k, v.trim()]).filter(([, v]) => v),
  )
  if (Object.keys(details).length === 0) {
    editError.value = 'Fill in at least one field.'
    return
  }

  isSaving.value = true
  editError.value = ''

  const { error } = await supabase.rpc('update_chart_entry', {
    p_entry_id: editingEntryId.value,
    p_updated_by: props.officerId,
    p_details: details,
  })

  isSaving.value = false
  if (error) {
    editError.value = error.message
    return
  }

  editingEntryId.value = null
  await loadEntries()
}

const showAbstracts = ref(false)
</script>

<template>
  <FormModal
    :title="`Patient Chart — ${patient.full_name}`"
    :subtitle="`Age ${patient.age ?? '—'} · Room ${patient.room_number ?? '—'} · Admitted ${patient.admission_date} · PhilHealth ${patient.philhealth_no ?? '—'}`"
    :icon="ClipboardList"
    size="xl"
    :busy="isSaving"
    @close="emit('close')"
  >
      <div class="modal-body">
        <!-- Add entry -->
        <form v-if="canAdd.length > 0" class="space-y-4 rounded-lg border border-border bg-muted/30 p-4" @submit.prevent="addEntry">
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
              class="field"
              :class="field.multiline ? 'sm:col-span-2' : ''"
            >
              <label :for="`chart-${field.key}`" class="field-label">{{ field.label }}</label>
              <textarea
                v-if="field.multiline"
                :id="`chart-${field.key}`"
                v-model="newDetails[field.key]"
                rows="3"
                class="field-input"
              />
              <input
                v-else
                :id="`chart-${field.key}`"
                v-model="newDetails[field.key]"
                type="text"
                :placeholder="field.placeholder"
                class="field-input"
              >
            </div>
          </div>

          <div v-if="saveError" class="form-error">
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
              <span class="flex flex-wrap items-baseline gap-2 text-xs text-muted-foreground">
                {{ entry.recorded_by_name }} ({{ entry.recorded_by_role }}) · {{ new Date(entry.created_at).toLocaleString() }}
                <button
                  v-if="canEdit(entry) && editingEntryId !== entry.entry_id"
                  type="button"
                  :disabled="isSaving"
                  class="font-medium text-primary hover:underline disabled:cursor-not-allowed disabled:opacity-60"
                  @click="startEdit(entry)"
                >
                  Edit
                </button>
              </span>
            </div>
            <p v-if="entry.updated_at" class="mt-0.5 text-xs italic text-muted-foreground">
              Edited by {{ entry.updated_by_name }} · {{ new Date(entry.updated_at).toLocaleString() }}
            </p>

            <form v-if="editingEntryId === entry.entry_id" class="mt-2 space-y-3 rounded-lg border border-border bg-muted/30 p-3" @submit.prevent="saveEdit">
              <div class="grid gap-3 sm:grid-cols-2">
                <div
                  v-for="field in ENTRY_TYPES[entry.entry_type].fields"
                  :key="field.key"
                  class="field"
                  :class="field.multiline ? 'sm:col-span-2' : ''"
                >
                  <label :for="`edit-${field.key}`" class="field-label">{{ field.label }}</label>
                  <textarea
                    v-if="field.multiline"
                    :id="`edit-${field.key}`"
                    v-model="editDetails[field.key]"
                    rows="3"
                    class="field-input"
                  />
                  <input
                    v-else
                    :id="`edit-${field.key}`"
                    v-model="editDetails[field.key]"
                    type="text"
                    :placeholder="field.placeholder"
                    class="field-input"
                  >
                </div>
              </div>

              <div v-if="editError" class="form-error">
                <AlertTriangle class="h-4 w-4 shrink-0" />
                {{ editError }}
              </div>

              <div class="flex justify-end gap-2">
                <button type="button" :disabled="isSaving" class="btn-secondary" @click="cancelEdit">
                  Cancel
                </button>
                <button
                  type="submit"
                  :disabled="isSaving"
                  class="flex items-center gap-2 rounded-md bg-primary px-3 py-1.5 text-xs font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
                >
                  <LoaderCircle v-if="isSaving" class="h-3.5 w-3.5 animate-spin" />
                  {{ isSaving ? 'Saving…' : 'Save Changes' }}
                </button>
              </div>
            </form>

            <dl v-else class="mt-1.5 space-y-1">
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

      <div class="modal-footer">
        <button type="button" :disabled="isSaving" class="btn-secondary" @click="emit('close')">
          Close
        </button>
        <button type="button" :disabled="isSaving" class="btn-secondary" @click="showAbstracts = true">
          Medical Abstract
        </button>
        <slot name="actions" />
      </div>
  </FormModal>

  <MedicalAbstracts
    v-if="showAbstracts"
    :patient-id="patient.patient_id"
    :patient-name="patient.full_name"
    :officer-id="officerId"
    :can-write="canAdd.includes('doctor_order')"
    @close="showAbstracts = false"
  />
</template>
