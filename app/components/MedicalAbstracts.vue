<script setup lang="ts">
import { AlertTriangle, FileText, LoaderCircle } from '@lucide/vue'
import type { MedicalAbstractRow } from '~/types/database.types'

// The doctor's Clinical Summary / Medical Abstract. The seven sections are the
// doctor's own assessment, so nothing is copied from the chart. Other staff
// can read and print. Only the doctor who wrote an abstract can edit it.
const props = defineProps<{
  patientId: number
  patientName: string
  officerId: number
  canWrite: boolean
}>()

const emit = defineEmits<{ close: [] }>()

const SECTIONS = [
  { key: 'brief_history', label: 'Brief History' },
  { key: 'physical_findings', label: 'Pertinent Physical Findings' },
  { key: 'impression', label: 'Impression' },
  { key: 'medication', label: 'Medication' },
  { key: 'procedures', label: 'Procedures' },
  { key: 'final_diagnosis', label: 'Final Diagnosis' },
  { key: 'recommendation', label: 'Recommendation' },
] as const

const supabase = useSupabaseClient()

const abstracts = ref<MedicalAbstractRow[]>([])
const isLoading = ref(false)
const loadError = ref('')

async function loadAbstracts() {
  isLoading.value = true
  const { data, error } = await supabase.rpc('list_medical_abstracts', { p_patient_id: props.patientId })
  loadError.value = error?.message ?? ''
  abstracts.value = data ?? []
  isLoading.value = false
}

onMounted(loadAbstracts)

// ── Write / edit ──────────────────────────────────────────────────────

const isWriting = ref(false)
const editingAbstractId = ref<number | null>(null)
const sections = ref<Record<string, string>>({})
const isSaving = ref(false)
const saveError = ref('')

function startNew() {
  editingAbstractId.value = null
  sections.value = {}
  saveError.value = ''
  isWriting.value = true
}

function startEdit(abstract: MedicalAbstractRow) {
  editingAbstractId.value = abstract.abstract_id
  sections.value = { ...abstract.sections }
  saveError.value = ''
  isWriting.value = true
}

async function saveAbstract() {
  const filled = Object.fromEntries(
    Object.entries(sections.value).map(([k, v]) => [k, v.trim()]).filter(([, v]) => v),
  )
  if (Object.keys(filled).length === 0) {
    saveError.value = 'Fill in at least one section.'
    return
  }

  isSaving.value = true
  saveError.value = ''

  const { error } = editingAbstractId.value === null
    ? await supabase.rpc('create_medical_abstract', {
        p_patient_id: props.patientId,
        p_doctor_id: props.officerId,
        p_sections: filled,
      })
    : await supabase.rpc('update_medical_abstract', {
        p_abstract_id: editingAbstractId.value,
        p_doctor_id: props.officerId,
        p_sections: filled,
      })

  isSaving.value = false
  if (error) {
    saveError.value = error.message
    return
  }

  isWriting.value = false
  await loadAbstracts()
}

// ── View / print ──────────────────────────────────────────────────────

const printingAbstract = ref<MedicalAbstractRow | null>(null)
</script>

<template>
  <FormModal
    :title="`Medical Abstract — ${patientName}`"
    :subtitle="isWriting ? 'Record your own assessment of the patient.' : 'Clinical summary written by the doctor'"
    :icon="FileText"
    size="xl"
    :busy="isSaving"
    @close="emit('close')"
  >
    <form v-if="isWriting" class="modal-form" @submit.prevent="saveAbstract">
      <div class="modal-body">
        <div v-for="(section, i) in SECTIONS" :key="section.key" class="field">
          <label :for="`abstract-${section.key}`" class="field-label">{{ i + 1 }}. {{ section.label }}</label>
          <textarea :id="`abstract-${section.key}`" v-model="sections[section.key]" rows="3" class="field-input" />
        </div>

        <div v-if="saveError" class="form-error">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ saveError }}
        </div>
      </div>

      <div class="modal-footer">
        <button type="button" :disabled="isSaving" class="btn-secondary" @click="isWriting = false">
          Cancel
        </button>
        <button type="submit" :disabled="isSaving" class="btn-primary">
          <LoaderCircle v-if="isSaving" class="h-4 w-4 animate-spin" />
          {{ isSaving ? 'Saving…' : 'Save Abstract' }}
        </button>
      </div>
    </form>

    <template v-else>
      <div class="modal-body">
        <div v-if="loadError" class="form-error">
          <AlertTriangle class="h-4 w-4 shrink-0" />
          {{ loadError }}
        </div>

        <ul class="divide-y divide-border">
          <li v-for="abstract in abstracts" :key="abstract.abstract_id" class="flex flex-wrap items-center justify-between gap-3 py-3 text-sm">
            <div class="min-w-0">
              <p class="font-medium">{{ abstract.doctor_name }}</p>
              <p class="text-xs text-muted-foreground">
                {{ new Date(abstract.created_at).toLocaleString() }}
                <template v-if="abstract.updated_at"> · Edited {{ new Date(abstract.updated_at).toLocaleString() }}</template>
              </p>
            </div>
            <div class="flex gap-3">
              <button
                v-if="canWrite && abstract.doctor_id === officerId"
                type="button"
                class="text-xs font-medium text-primary hover:underline"
                @click="startEdit(abstract)"
              >
                Edit
              </button>
              <button type="button" class="text-xs font-medium text-primary hover:underline" @click="printingAbstract = abstract">
                View / Print
              </button>
            </div>
          </li>
          <li v-if="!isLoading && abstracts.length === 0" class="py-6 text-center text-sm text-muted-foreground">
            No medical abstract yet.
          </li>
        </ul>
      </div>

      <div class="modal-footer">
        <button type="button" class="btn-secondary" @click="emit('close')">Close</button>
        <button v-if="canWrite" type="button" class="btn-primary" @click="startNew">New Abstract</button>
      </div>
    </template>
  </FormModal>

  <PrintPreview v-if="printingAbstract" label="Medical abstract" @close="printingAbstract = null">
    <header class="text-center">
      <p class="text-xs">Republic of the Philippines</p>
      <p class="text-lg font-bold">Butuan Medical Center</p>
      <p class="text-xs">Km. 5, Baan, Butuan City</p>
      <h1 class="mt-4 text-base font-bold uppercase">Clinical Summary / Medical Abstract</h1>
    </header>

    <dl class="mt-6 grid grid-cols-2 gap-x-6 gap-y-1 text-sm">
      <div class="flex gap-2"><dt class="font-semibold">Name:</dt><dd>{{ printingAbstract.patient_name }}</dd></div>
      <div class="flex gap-2"><dt class="font-semibold">Date:</dt><dd>{{ new Date(printingAbstract.created_at).toLocaleDateString() }}</dd></div>
      <div class="flex gap-2"><dt class="font-semibold">Age:</dt><dd>{{ printingAbstract.patient_age ?? '—' }}</dd></div>
      <div class="flex gap-2"><dt class="font-semibold">Sex:</dt><dd>{{ printingAbstract.patient_sex ?? '—' }}</dd></div>
      <div class="col-span-2 flex gap-2"><dt class="font-semibold">Address:</dt><dd>{{ printingAbstract.patient_address ?? '—' }}</dd></div>
    </dl>

    <section v-for="(section, i) in SECTIONS" :key="section.key" class="mt-5 break-inside-avoid text-sm">
      <h2 class="font-bold uppercase">{{ i + 1 }}. {{ section.label }}</h2>
      <p class="mt-1 min-h-5 whitespace-pre-line break-words">{{ printingAbstract.sections[section.key] }}</p>
    </section>

    <footer class="ml-auto mt-14 w-72 break-inside-avoid text-center text-sm">
      <p class="border-b border-black pb-1 font-semibold">{{ printingAbstract.doctor_name }}</p>
      <p class="mt-1 text-xs">Physician's Signature Over Printed Name</p>
      <p class="mt-2 text-xs">License No. {{ printingAbstract.doctor_license ?? '____________' }}</p>
    </footer>
  </PrintPreview>
</template>
