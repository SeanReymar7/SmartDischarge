<script setup lang="ts" generic="S extends string">
import type { Component } from 'vue'
import { Bell, LoaderCircle, LogOut, Menu, Moon, Search, Sun, X } from '@lucide/vue'

const props = defineProps<{
  department: string
  roleLabel: string
  navItems: readonly { label: string, icon: Component, section: S }[]
  badges?: Partial<Record<S, number>>
  alert?: boolean
}>()

const activeSection = defineModel<S>('section', { required: true })
const search = defineModel<string>('search', { default: '' })

const session = useAdminSession()
const fullName = computed(() => session.value?.fullName ?? '')
const { initials } = useOfficerName(fullName)

const { isDark, init: initDarkMode, toggle: toggleDarkMode } = useDarkMode()
onMounted(initDarkMode)

const sectionLabel = computed(() => props.navItems.find((i) => i.section === activeSection.value)?.label ?? '')

const sidebarOpen = ref(false)
const showLogoutConfirm = ref(false)
const isLoggingOut = ref(false)

function selectSection(section: S) {
  activeSection.value = section
  sidebarOpen.value = false
}

async function handleLogout() {
  isLoggingOut.value = true
  session.value = null
  await navigateTo('/loginpage')
}
</script>

<template>
  <div class="flex min-h-screen bg-background">
    <!-- Mobile backdrop -->
    <Transition
      enter-from-class="opacity-0"
      leave-to-class="opacity-0"
      enter-active-class="transition-opacity duration-200"
      leave-active-class="transition-opacity duration-200"
    >
      <div v-if="sidebarOpen" class="fixed inset-0 z-40 bg-black/45 lg:hidden" @click="sidebarOpen = false" />
    </Transition>

    <!-- Sidebar: a drawer below lg, pinned at lg and up -->
    <aside
      class="fixed inset-y-0 left-0 z-50 flex w-64 flex-col border-r border-sidebar-border bg-sidebar text-sidebar-foreground transition-[translate,visibility] duration-200 ease-out lg:visible lg:sticky lg:top-0 lg:h-screen lg:translate-x-0"
      :class="sidebarOpen ? 'visible translate-x-0' : 'invisible -translate-x-full'"
    >
      <div class="flex h-16 shrink-0 items-center gap-3 px-5">
        <span class="flex h-9 w-9 items-center justify-center rounded-md bg-sidebar-primary text-sidebar-primary-foreground">
          <AppLogo class="h-5 w-5" />
        </span>
        <div class="min-w-0 flex-1 leading-tight">
          <p class="font-bold tracking-tight text-sidebar-accent-foreground">AHDMS</p>
          <p class="truncate text-xs text-sidebar-foreground/60">Butuan Medical Center</p>
        </div>
        <button
          type="button"
          aria-label="Close menu"
          class="rounded-md p-1 text-sidebar-foreground/70 hover:text-sidebar-accent-foreground lg:hidden"
          @click="sidebarOpen = false"
        >
          <X class="h-5 w-5" />
        </button>
      </div>

      <nav class="flex-1 space-y-0.5 overflow-y-auto px-3 py-4" :aria-label="`${department} sections`">
        <button
          v-for="item in navItems"
          :key="item.section"
          type="button"
          class="relative flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-sm font-medium transition-colors"
          :class="activeSection === item.section
            ? 'bg-sidebar-accent text-sidebar-accent-foreground'
            : 'text-sidebar-foreground/70 hover:bg-sidebar-accent/50 hover:text-sidebar-accent-foreground'"
          :aria-current="activeSection === item.section ? 'page' : undefined"
          @click="selectSection(item.section)"
        >
          <span
            v-if="activeSection === item.section"
            class="absolute inset-y-2 left-0 w-0.5 rounded-full bg-sidebar-primary"
          />
          <component :is="item.icon" class="h-4 w-4 shrink-0" />
          {{ item.label }}
          <span
            v-if="badges?.[item.section]"
            class="ml-auto min-w-5 rounded-full bg-sidebar-primary px-1.5 py-0.5 text-center text-[11px] font-bold tabular-nums text-sidebar-primary-foreground"
          >
            {{ badges[item.section] }}
          </span>
        </button>
      </nav>

      <div class="flex shrink-0 items-center gap-3 border-t border-sidebar-border px-5 py-4">
        <span class="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-sidebar-accent text-xs font-bold text-sidebar-accent-foreground">
          {{ initials || department.slice(0, 2).toUpperCase() }}
        </span>
        <div class="min-w-0 flex-1 leading-tight">
          <p class="truncate text-sm font-semibold text-sidebar-accent-foreground">{{ fullName || department }}</p>
          <p class="truncate text-xs text-sidebar-foreground/60">{{ roleLabel }}</p>
        </div>
        <button
          type="button"
          aria-label="Log out"
          title="Log out"
          class="rounded-md p-2 text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent hover:text-sidebar-accent-foreground"
          @click="showLogoutConfirm = true"
        >
          <LogOut class="h-4 w-4" />
        </button>
      </div>
    </aside>

    <!-- Main -->
    <div class="flex min-w-0 flex-1 flex-col">
      <header class="sticky top-0 z-30 flex h-16 items-center gap-3 border-b border-border bg-background/85 px-4 backdrop-blur sm:gap-4 sm:px-8">
        <button type="button" aria-label="Open menu" class="-ml-1 rounded-md p-1 text-muted-foreground lg:hidden" @click="sidebarOpen = true">
          <Menu class="h-5 w-5" />
        </button>

        <div class="min-w-0 flex-1 leading-tight">
          <p class="truncate text-xs text-muted-foreground">{{ department }}</p>
          <h1 class="truncate text-lg font-bold tracking-tight">{{ sectionLabel }}</h1>
        </div>

        <label class="relative hidden w-full max-w-xs sm:block">
          <span class="sr-only">Search patients</span>
          <Search class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
          <input
            v-model="search"
            type="search"
            placeholder="Search patients"
            class="w-full rounded-md border border-input bg-card py-2 pl-9 pr-3 text-sm outline-none placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
          >
        </label>

        <button
          type="button"
          :aria-label="isDark ? 'Switch to light mode' : 'Switch to dark mode'"
          class="rounded-md p-2 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground"
          @click="toggleDarkMode"
        >
          <Sun v-if="isDark" class="h-5 w-5" />
          <Moon v-else class="h-5 w-5" />
        </button>

        <button type="button" aria-label="Notifications" class="relative rounded-md p-2 text-muted-foreground transition-colors hover:bg-muted hover:text-foreground">
          <Bell class="h-5 w-5" />
          <span v-if="alert" class="absolute right-1.5 top-1.5 h-2 w-2 rounded-full bg-danger ring-2 ring-background" />
        </button>
      </header>

      <main class="flex-1 px-4 py-6 sm:px-8 sm:py-8">
        <Transition name="section" mode="out-in">
          <div :key="activeSection" class="mx-auto max-w-7xl space-y-6">
            <slot />
          </div>
        </Transition>
      </main>
    </div>

    <!-- Logout confirmation -->
    <div v-if="showLogoutConfirm" class="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div class="absolute inset-0 bg-black/45 animate-in fade-in-0" @click="!isLoggingOut && (showLogoutConfirm = false)" />
      <div role="dialog" aria-modal="true" aria-labelledby="logout-title" class="relative w-full max-w-sm rounded-xl border border-border bg-card p-6 shadow-lg animate-in fade-in-0 zoom-in-95 slide-in-from-bottom-2 duration-200">
        <h2 id="logout-title" class="text-base font-bold tracking-tight">Log out of AHDMS?</h2>
        <p class="mt-1.5 text-sm text-muted-foreground">
          You'll need to sign in again to continue.
        </p>
        <div class="mt-6 flex gap-3">
          <button
            type="button"
            :disabled="isLoggingOut"
            class="flex-1 rounded-md border border-border py-2 text-sm font-medium transition-colors hover:bg-muted disabled:cursor-not-allowed disabled:opacity-60"
            @click="showLogoutConfirm = false"
          >
            Stay signed in
          </button>
          <button
            type="button"
            :disabled="isLoggingOut"
            class="flex flex-1 items-center justify-center gap-2 rounded-md bg-danger py-2 text-sm font-medium text-background transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
            @click="handleLogout"
          >
            <LoaderCircle v-if="isLoggingOut" class="h-4 w-4 animate-spin" />
            {{ isLoggingOut ? 'Logging out…' : 'Log out' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
