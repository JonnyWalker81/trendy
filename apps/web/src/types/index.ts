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
  properties?: Record<string, PropertyValue>
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
  properties?: Record<string, PropertyValue>
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
  properties?: Record<string, PropertyValue>
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

// Property Types
export type PropertyType =
  | 'text'
  | 'number'
  | 'boolean'
  | 'date'
  | 'select'
  | 'duration'
  | 'url'
  | 'email'

export interface PropertyValue {
  type: PropertyType
  value: string | number | boolean | Date
}

export interface PropertyDefinition {
  id: string
  event_type_id: string
  user_id: string
  key: string
  label: string
  property_type: PropertyType
  options?: string[]
  default_value?: string | number | boolean | Date
  display_order: number
  created_at: string
  updated_at: string
}

export interface CreatePropertyDefinitionRequest {
  event_type_id: string
  key: string
  label: string
  property_type: PropertyType
  options?: string[]
  default_value?: string | number | boolean | Date
  display_order?: number
}

export interface UpdatePropertyDefinitionRequest {
  key?: string
  label?: string
  property_type?: PropertyType
  options?: string[]
  default_value?: string | number | boolean | Date
  display_order?: number
}
