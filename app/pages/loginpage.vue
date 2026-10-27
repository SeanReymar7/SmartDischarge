<script setup lang="ts">
import {
  AlertTriangle,
  ArrowLeft,
  ClipboardList,
  Eye,
  EyeOff,
  Gauge,
  ListChecks,
  Lock,
  LoaderCircle,
  LogIn,
  Mail,
  Sun,
  Moon,
} from '@lucide/vue'
import { onMounted, ref } from 'vue'
import type { AdminSession } from '~/composables/useAdminSession'

const brandHighlights = [
  { icon: ClipboardList, text: 'Digitized charts & records' },
  { icon: ListChecks, text: 'Automated task delegation' },
  { icon: Gauge, text: 'Real-time discharge tracking' },
]

useHead({
  title: 'Sign In — AHDMS',
  meta: [
    {
      name: 'description',
      content: 'Staff sign-in for the Automated Hospital Discharge Management System (AHDMS) at Butuan Medical Center.',
    },
  ],
})

const { isDark, init: initDarkMode, toggle: toggleDarkMode } = useDarkMode()
onMounted(initDarkMode)

const supabase = useSupabaseClient()
const session = useAdminSession()

const email = ref('')
const password = ref('')
const showPassword = ref(false)
const isSubmitting = ref(false)
const errorMessage = ref('')

async function handleSubmit() {
  errorMessage.value = ''
  isSubmitting.value = true

  const { data, error } = await supabase
    .rpc('login_officer', { p_email: email.value, p_password: password.value })
    .single()

  if (error || !data) {
    errorMessage.value = 'Incorrect email or password.'
    isSubmitting.value = false
    return
  }

  session.value = {
    id: String(data.officer_id),
    email: data.email,
    fullName: data.full_name,
    role: data.role as AdminSession['role'],
  }
  await navigateTo(dashboardPathForRole(session.value.role))
}
</script>

<template>
  <div class="grid min-h-screen lg:grid-cols-2">
    <!-- Form side -->
    <div class="relative flex flex-col justify-center overflow-hidden px-6 py-12 sm:px-12 lg:px-20">
      <a
        href="/"
        class="absolute left-6 top-6 flex items-center gap-1.5 text-sm text-muted-foreground transition-colors hover:text-foreground sm:left-12 lg:left-20"
      >
        <ArrowLeft class="h-4 w-4" />
        Back to home
      </a>

      <button
        :aria-label="isDark ? 'Switch to light mode' : 'Switch to dark mode'"
        class="absolute right-6 top-6 text-muted-foreground transition-colors hover:text-foreground sm:right-12 lg:right-20"
        @click="toggleDarkMode"
      >
        <Sun v-if="isDark" class="h-5 w-5" />
        <Moon v-else class="h-5 w-5" />
      </button>

      <div class="mx-auto w-full max-w-sm">
        <a href="/" class="mb-10 flex items-center gap-2.5 font-bold tracking-tight lg:hidden">
          <span class="flex h-10 w-10 items-center justify-center rounded-md bg-sidebar text-sidebar-primary">
            <AppLogo class="h-5 w-5" />
          </span>
          <span class="text-lg">AHDMS</span>
        </a>

        <h1 class="text-3xl font-bold tracking-tight">
          Welcome back
        </h1>
        <p class="mt-2 text-sm text-muted-foreground">
          Sign in to access the discharge management dashboard for Butuan Medical Center.
        </p>

        <form class="mt-8 rounded-xl border border-border bg-card p-6 sm:p-7" @submit.prevent="handleSubmit">
          <fieldset :disabled="isSubmitting" class="space-y-5">
          <div class="space-y-1.5">
            <label for="email" class="text-sm font-medium">Hospital email</label>
            <div class="relative">
              <Mail class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                id="email"
                v-model="email"
                type="email"
                autocomplete="username"
                placeholder="you@butuanmedicalcenter.gov.ph"
                required
                class="w-full rounded-md border border-input bg-background py-2.5 pl-10 pr-3 text-sm outline-none ring-offset-background transition-colors placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
              >
            </div>
          </div>

          <div class="space-y-1.5">
            <div class="flex items-center justify-between">
              <label for="password" class="text-sm font-medium">Password</label>
              <a href="#" class="text-xs text-primary hover:underline">Forgot password?</a>
            </div>
            <div class="relative">
              <Lock class="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
              <input
                id="password"
                v-model="password"
                :type="showPassword ? 'text' : 'password'"
                autocomplete="current-password"
                placeholder="••••••••"
                required
                class="w-full rounded-md border border-input bg-background py-2.5 pl-10 pr-10 text-sm outline-none ring-offset-background transition-colors placeholder:text-muted-foreground focus-visible:ring-2 focus-visible:ring-ring"
              >
              <button
                type="button"
                class="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground transition-colors hover:text-foreground"
                :aria-label="showPassword ? 'Hide password' : 'Show password'"
                @click="showPassword = !showPassword"
              >
                <EyeOff v-if="showPassword" class="h-4 w-4" />
                <Eye v-else class="h-4 w-4" />
              </button>
            </div>
          </div>

          </fieldset>

          <div
            v-if="errorMessage"
            class="mt-5 flex items-center gap-2 rounded-md bg-danger/10 px-3 py-2.5 text-sm text-danger"
          >
            <AlertTriangle class="h-4 w-4 shrink-0" />
            {{ errorMessage }}
          </div>

          <button
            type="submit"
            :disabled="isSubmitting"
            class="mt-5 flex w-full items-center justify-center gap-2 rounded-md bg-primary py-2.5 text-sm font-medium text-primary-foreground transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <LoaderCircle v-if="isSubmitting" class="h-4 w-4 animate-spin" />
            <LogIn v-else class="h-4 w-4" />
            {{ isSubmitting ? 'Signing in…' : 'Sign in' }}
          </button>
        </form>

        <p class="mt-4 text-center text-xs text-muted-foreground">
          Authorized BMC personnel only. Access is logged for audit purposes.
        </p>
      </div>
    </div>

    <!-- Brand side -->
    <div class="relative hidden overflow-hidden bg-sidebar lg:block">
      <!-- The brand mark, oversized and cropped, as the panel's only ornament -->
      <AppLogo class="pointer-events-none absolute -bottom-24 -right-24 h-[28rem] w-[28rem] text-sidebar-accent/70" />

      <div class="relative flex h-full flex-col p-12 text-sidebar-foreground">
        <div class="flex items-center gap-3">
          <span class="flex h-11 w-11 items-center justify-center rounded-md bg-sidebar-primary text-sidebar-primary-foreground">
            <AppLogo class="h-6 w-6" />
          </span>
          <div class="leading-tight">
            <p class="font-bold tracking-tight text-sidebar-accent-foreground">AHDMS</p>
            <p class="text-xs text-sidebar-foreground/60">Butuan Medical Center</p>
          </div>
        </div>

        <div class="flex flex-1 flex-col justify-center">
          <h2 class="max-w-md text-4xl font-bold leading-tight tracking-tight text-balance text-sidebar-accent-foreground">
            One dashboard for every step of the discharge process.
          </h2>
          <p class="mt-4 max-w-sm text-base text-sidebar-foreground/80">
            Track documentation, task delegation, and discharge status in real time —
            no more paper carts.
          </p>

          <ul class="mt-8 space-y-3 text-left">
            <li
              v-for="highlight in brandHighlights"
              :key="highlight.text"
              class="flex items-center gap-3 text-sm"
            >
              <component :is="highlight.icon" class="h-4 w-4 shrink-0 text-sidebar-primary" />
              <span>{{ highlight.text }}</span>
            </li>
          </ul>
        </div>
      </div>
    </div>
  </div>
</template>
