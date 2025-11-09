// Shared types for Trendy monorepo
// These types are used across the web frontend and can serve as a reference for the backend

export interface User {
  id: string
  email: string
  created_at: string
  updated_at: string
}

export interface EventType {
  id: string
  user_id: string
  name: string
  color: string
  icon: string
  created_at: string
  updated_at: string
}

export interface Event {
  id: string
  user_id: string
  event_type_id: string
  timestamp: string
  notes?: string
  is_all_day: boolean
  end_date?: string
  source_type: 'manual' | 'imported'
  external_id?: string
  original_title?: string
  created_at: string
  updated_at: string
  event_type?: EventType
}

export interface CreateEventRequest {
  event_type_id: string
  timestamp: string
  notes?: string
  is_all_day?: boolean
  end_date?: string
  source_type?: 'manual' | 'imported'
  external_id?: string
  original_title?: string
}

export interface UpdateEventRequest {
  event_type_id?: string
  timestamp?: string
  notes?: string
  is_all_day?: boolean
  end_date?: string
  source_type?: 'manual' | 'imported'
  external_id?: string
  original_title?: string
}

export interface CreateEventTypeRequest {
  name: string
  color: string
  icon: string
}

export interface UpdateEventTypeRequest {
  name?: string
  color?: string
  icon?: string
}

export interface AnalyticsSummary {
  total_events: number
  event_type_counts: Record<string, number>
  recent_events: Event[]
}

export interface TrendData {
  event_type_id: string
  period: string
  data: TimeSeriesDataPoint[]
  average: number
  trend: 'increasing' | 'decreasing' | 'stable'
}

export interface TimeSeriesDataPoint {
  date: string
  count: number
}

export interface LoginRequest {
  email: string
  password: string
}

export interface SignupRequest {
  email: string
  password: string
}

export interface AuthResponse {
  access_token: string
  refresh_token: string
  user: User
}
