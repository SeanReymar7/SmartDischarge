<script setup lang="ts">
import { Printer } from '@lucide/vue'

// Shows a document as a sheet of paper. Printing outputs only the sheet;
// see .print-preview in tailwind.css. Render it with v-if after a click so
// it never runs during server rendering.
defineProps<{ label: string }>()

const emit = defineEmits<{ close: [] }>()

function printSheet() {
  window.print()
}
</script>

<template>
  <Teleport to="body">
    <div class="print-preview" role="dialog" aria-modal="true" :aria-label="label">
      <div class="print-toolbar">
        <button type="button" class="btn-secondary max-w-32" @click="emit('close')">Close</button>
        <button type="button" class="btn-primary max-w-32" @click="printSheet">
          <Printer class="h-4 w-4" />
          Print
        </button>
      </div>
      <div class="print-sheet">
        <slot />
      </div>
    </div>
  </Teleport>
</template>
