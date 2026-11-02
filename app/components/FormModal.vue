<script setup lang="ts">
import { X } from '@lucide/vue'
import type { Component } from 'vue'

// The dialog behind every form. The ward-ink header repeats the sign-in
// brand panel. Put the form in the default slot, using .modal-form,
// .modal-body and .modal-footer from tailwind.css.
const props = withDefaults(defineProps<{
  title: string
  subtitle?: string
  icon: Component
  size?: 'md' | 'lg' | 'xl'
  busy?: boolean
}>(), { size: 'md' })

const emit = defineEmits<{ close: [] }>()

const titleId = useId()

const sizeClass = { md: 'max-w-md', lg: 'max-w-xl', xl: 'max-w-2xl' }

function requestClose() {
  if (!props.busy) emit('close')
}
</script>

<template>
  <div class="fixed inset-0 z-50 flex items-center justify-center p-4">
    <div class="absolute inset-0 bg-sidebar/60 backdrop-blur-[2px] animate-in fade-in-0" @click="requestClose" />
    <div
      role="dialog"
      aria-modal="true"
      :aria-labelledby="titleId"
      class="relative flex max-h-[90vh] w-full flex-col overflow-hidden rounded-xl bg-card shadow-2xl animate-in fade-in-0 zoom-in-95 slide-in-from-bottom-2 duration-200"
      :class="sizeClass[size]"
    >
      <header class="relative shrink-0 overflow-hidden bg-sidebar px-6 py-5">
        <AppLogo class="pointer-events-none absolute -right-8 -top-10 h-40 w-40 text-sidebar-accent/70" />

        <div class="relative flex items-center gap-3 pr-8">
          <component :is="icon" class="h-6 w-6 shrink-0 text-sidebar-primary" :stroke-width="1.75" aria-hidden="true" />
          <div class="min-w-0">
            <h2 :id="titleId" class="truncate text-lg font-bold tracking-tight text-sidebar-accent-foreground">{{ title }}</h2>
            <p v-if="subtitle" class="mt-0.5 text-xs text-sidebar-foreground/75">{{ subtitle }}</p>
          </div>
        </div>

        <button
          type="button"
          aria-label="Close"
          :disabled="busy"
          class="absolute right-4 top-4 rounded-md p-1 text-sidebar-foreground/75 transition-colors hover:text-sidebar-accent-foreground disabled:cursor-not-allowed disabled:opacity-60"
          @click="requestClose"
        >
          <X class="h-4 w-4" />
        </button>
      </header>

      <slot />
    </div>
  </div>
</template>
