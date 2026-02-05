export interface Database {
    public: {
        Tables: {
            guards: {
                Row: {
                    id: string
                    organization_id: string
                    full_name: string
                    phone_number: string
                    guard_code: string
                    primary_unit_id: string | null
                    employment_status: 'active' | 'inactive' | 'suspended'
                    created_at: string
                    updated_at: string
                    deleted_at: string | null
                }
                Insert: {
                    id?: string
                    organization_id: string
                    full_name: string
                    phone_number: string
                    guard_code: string
                    primary_unit_id?: string | null
                    employment_status?: 'active' | 'inactive' | 'suspended'
                    created_at?: string
                    updated_at?: string
                    deleted_at?: string | null
                }
                Update: {
                    full_name?: string
                    phone_number?: string
                    guard_code?: string
                    primary_unit_id?: string | null
                    employment_status?: 'active' | 'inactive' | 'suspended'
                    updated_at?: string
                    deleted_at?: string | null
                }
            }
            units: {
                Row: {
                    id: string
                    organization_id: string
                    unit_name: string
                    address: string | null
                    required_guard_count: number
                    created_at: string
                    updated_at: string
                    deleted_at: string | null
                }
                Insert: {
                    id?: string
                    organization_id: string
                    unit_name: string
                    address?: string | null
                    required_guard_count?: number
                    created_at?: string
                    updated_at?: string
                    deleted_at?: string | null
                }
                Update: {
                    unit_name?: string
                    address?: string | null
                    required_guard_count?: number
                    updated_at?: string
                    deleted_at?: string | null
                }
            }
            work_events: {
                Row: {
                    id: string
                    organization_id: string
                    guard_id: string
                    primary_unit_id: string
                    working_unit_id: string
                    check_in_time: string
                    check_out_time: string | null
                    shift_date: string
                    total_hours: number | null
                    duty_type: 'PRIMARY' | 'TEMP_DEPLOYMENT' | 'OVERTIME' | 'DOUBLE_SHIFT' | 'UNSCHEDULED'
                    event_status: 'CHECKED_IN' | 'CHECKED_OUT' | 'NO_SHOW' | 'CANCELLED'
                    approval_status: 'AUTO_APPROVED' | 'PENDING' | 'APPROVED' | 'REJECTED'
                    anomaly_flag: boolean
                    anomaly_reason: string | null
                    created_at: string
                    updated_at: string
                    locked_at: string | null
                    deleted_at: string | null
                    created_by: string | null
                    approved_by: string | null
                    approved_at: string | null
                }
                Insert: {
                    id?: string
                    organization_id: string
                    guard_id: string
                    primary_unit_id: string
                    working_unit_id: string
                    check_in_time: string
                    check_out_time?: string | null
                    shift_date: string
                    total_hours?: number | null
                    duty_type?: 'PRIMARY' | 'TEMP_DEPLOYMENT' | 'OVERTIME' | 'DOUBLE_SHIFT' | 'UNSCHEDULED'
                    event_status?: 'CHECKED_IN' | 'CHECKED_OUT' | 'NO_SHOW' | 'CANCELLED'
                    approval_status?: 'AUTO_APPROVED' | 'PENDING' | 'APPROVED' | 'REJECTED'
                    anomaly_flag?: boolean
                    anomaly_reason?: string | null
                    created_at?: string
                    updated_at?: string
                    locked_at?: string | null
                    deleted_at?: string | null
                    created_by?: string | null
                    approved_by?: string | null
                    approved_at?: string | null
                }
                Update: {
                    check_out_time?: string | null
                    event_status?: 'CHECKED_IN' | 'CHECKED_OUT' | 'NO_SHOW' | 'CANCELLED'
                    approval_status?: 'AUTO_APPROVED' | 'PENDING' | 'APPROVED' | 'REJECTED'
                    approved_by?: string | null
                    approved_at?: string | null
                }
            }
            attendance: {
                Row: {
                    id: string
                    guard_id: string
                    unit_id: string
                    attendance_date: string
                    check_in_time: string | null
                    check_out_time: string | null
                    status: 'present' | 'late' | 'absent' | 'missing'
                    is_manual: boolean
                    created_at: string
                }
                Insert: {
                    id?: string
                    guard_id: string
                    unit_id: string
                    attendance_date: string
                    check_in_time?: string | null
                    check_out_time?: string | null
                    status: 'present' | 'late' | 'absent' | 'missing'
                    is_manual?: boolean
                    created_at?: string
                }
                Update: {
                    check_in_time?: string | null
                    check_out_time?: string | null
                    status?: 'present' | 'late' | 'absent' | 'missing'
                }
            }
        }
    }
}

export type Guard = Database['public']['Tables']['guards']['Row']
export type Unit = Database['public']['Tables']['units']['Row']
export type WorkEvent = Database['public']['Tables']['work_events']['Row']
export type Attendance = Database['public']['Tables']['attendance']['Row']
