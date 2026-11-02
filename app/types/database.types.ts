export interface PatientRow {
  patient_id: number
  full_name: string
  date_of_birth: string | null
  age: number | null
  sex: string | null
  address: string | null
  contact_number: string | null
  emergency_contact: string | null
  admission_date: string
  discharge_date: string | null
  room_number: number | null
  philhealth_no: string | null
  attending_officer_id: number | null
  created_at: string
}

interface DischargeRequestRow {
  request_id: number
  patient_id: number
  requested_by: number
  assigned_doctor_id: number | null
  approved_by: number | null
  status: string
  timestamp: string
}

interface DischargeRequestByRequesterRow {
  request_id: number
  patient_id: number
  patient_name: string
  assigned_doctor_name: string | null
  status: string
  timestamp: string
}

interface DischargeRequestDetailedRow {
  request_id: number
  patient_id: number
  patient_name: string
  requested_by: number
  requested_by_name: string
  assigned_doctor_id: number | null
  assigned_doctor_name: string | null
  approved_by: number | null
  approved_by_name: string | null
  status: string
  timestamp: string
}

export type ChartEntryType = 'vital_signs' | 'nursing_note' | 'medication' | 'other' | 'doctor_order'

export interface ChartEntryRow {
  entry_id: number
  entry_type: ChartEntryType
  details: Record<string, string>
  recorded_by: number
  recorded_by_name: string
  recorded_by_role: string
  created_at: string
  updated_by_name: string | null
  updated_at: string | null
}

export interface MedicalAbstractRow {
  abstract_id: number
  doctor_id: number
  doctor_name: string
  doctor_license: string | null
  patient_name: string
  patient_age: number | null
  patient_sex: string | null
  patient_address: string | null
  sections: Record<string, string>
  created_at: string
  updated_at: string | null
}

export interface BillingRecordRow {
  billing_id: number
  patient_name: string
  philhealth_no: string | null
  room_number: number | null
  admission_date: string
  discharge_date: string | null
  handled_by_name: string | null
  charges: Record<string, number>
  total_amount: number
  philhealth_deduction: number
  created_at: string
}

interface OfficerRow {
  officer_id: number
  full_name: string
  role: string
  specialty: string | null
  license_number: string | null
  duty_status: string
  created_at: string
}

export interface BillingRow {
  billing_id: number
  discharge_request_id: number
  patient_id: number
  handled_by: number | null
  charges: Record<string, number>
  total_amount: number
  philhealth_deduction: number
  created_at: string
}

interface LoginResultRow {
  officer_id: number
  full_name: string
  email: string
  role: string
  duty_status: string
}

export interface Database {
  public: {
    Tables: Record<string, never>
    Views: Record<string, never>
    Functions: {
      login_officer: {
        Args: { p_email: string; p_password: string }
        Returns: LoginResultRow[]
      }
      register_officer: {
        Args: { p_email: string; p_password: string; p_full_name: string; p_role: string; p_admin_id: number | null; p_specialty?: string | null; p_license_number?: string | null }
        Returns: LoginResultRow[]
      }
      set_duty_status: {
        Args: { p_officer_id: number; p_duty_status: string }
        Returns: OfficerRow
      }
      register_patient: {
        Args: {
          p_full_name: string
          p_date_of_birth: string | null
          p_age: number | null
          p_contact_number: string | null
          p_emergency_contact: string | null
          p_room_number: number | null
          p_philhealth_no: string | null
          p_attending_officer_id: number | null
          p_sex: string | null
          p_address: string | null
        }
        Returns: PatientRow
      }
      update_patient_info: {
        Args: {
          p_patient_id: number
          p_contact_number?: string | null
          p_emergency_contact?: string | null
          p_room_number?: number | null
          p_attending_officer_id?: number | null
          p_sex?: string | null
          p_address?: string | null
        }
        Returns: PatientRow
      }
      create_discharge_request: {
        Args: { p_patient_id: number; p_requested_by: number; p_assigned_doctor_id: number }
        Returns: number
      }
      add_chart_entry: {
        Args: { p_patient_id: number; p_recorded_by: number; p_entry_type: ChartEntryType; p_details: Record<string, string> }
        Returns: unknown
      }
      update_chart_entry: {
        Args: { p_entry_id: number; p_updated_by: number; p_details: Record<string, string> }
        Returns: unknown
      }
      list_chart_entries: {
        Args: { p_patient_id: number }
        Returns: ChartEntryRow[]
      }
      create_medical_abstract: {
        Args: { p_patient_id: number; p_doctor_id: number; p_sections: Record<string, string> }
        Returns: unknown
      }
      update_medical_abstract: {
        Args: { p_abstract_id: number; p_doctor_id: number; p_sections: Record<string, string> }
        Returns: unknown
      }
      list_medical_abstracts: {
        Args: { p_patient_id: number }
        Returns: MedicalAbstractRow[]
      }
      clear_billing: {
        Args: { p_request_id: number; p_handled_by: number; p_charges: Record<string, number>; p_philhealth_deduction: number }
        Returns: BillingRow
      }
      list_billing_records: {
        Args: Record<string, never>
        Returns: BillingRecordRow[]
      }
      approve_discharge_request: {
        Args: { p_request_id: number; p_approved_by: number }
        Returns: DischargeRequestRow
      }
      reject_discharge_request: {
        Args: { p_request_id: number; p_rejected_by: number }
        Returns: DischargeRequestRow
      }
      list_discharge_requests_by_requester: {
        Args: { p_officer_id: number }
        Returns: DischargeRequestByRequesterRow[]
      }
      list_discharge_requests_detailed: {
        Args: { p_status?: string | null }
        Returns: DischargeRequestDetailedRow[]
      }
      list_patients_by_officer: {
        Args: { p_officer_id: number }
        Returns: PatientRow[]
      }
      list_all_patients: {
        Args: Record<string, never>
        Returns: PatientRow[]
      }
      list_officers: {
        Args: Record<string, never>
        Returns: OfficerRow[]
      }
    }
    Enums: Record<string, never>
    CompositeTypes: Record<string, never>
  }
}
