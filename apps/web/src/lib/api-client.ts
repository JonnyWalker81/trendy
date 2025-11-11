import { supabase } from './supabase'
import type {
  Event,
  EventType,
  CreateEventRequest,
  UpdateEventRequest,
  CreateEventTypeRequest,
  UpdateEventTypeRequest,
  AnalyticsSummary,
  TrendData,
} from '../types'

// Use environment variable for production, fallback to proxy path for local dev
const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api/v1'

// Debug: Log API base URL in development
if (import.meta.env.DEV) {
  console.log('🔧 API Configuration:', {
    VITE_API_BASE_URL: import.meta.env.VITE_API_BASE_URL,
    API_BASE,
    isDev: import.meta.env.DEV,
    mode: import.meta.env.MODE,
  })
} else {
  console.log('🚀 Production API Base:', API_BASE)
}

async function getAuthHeaders() {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token

  return {
    'Content-Type': 'application/json',
    ...(token && { Authorization: `Bearer ${token}` }),
  }
}

async function handleResponse<T>(response: Response): Promise<T> {
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    throw new Error(error.error || `HTTP ${response.status}`)
  }
  return response.json()
}

// Event API
export const eventApi = {
  getAll: async (limit = 50, offset = 0): Promise<Event[]> => {
    const headers = await getAuthHeaders()
    const response = await fetch(
      `${API_BASE}/events?limit=${limit}&offset=${offset}`,
      { headers }
    )
    return handleResponse<Event[]>(response)
  },

  getById: async (id: string): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, { headers })
    return handleResponse<Event>(response)
  },

  create: async (data: CreateEventRequest): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events`, {
      method: 'POST',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<Event>(response)
  },

  update: async (id: string, data: UpdateEventRequest): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<Event>(response)
  },

  delete: async (id: string): Promise<void> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, {
      method: 'DELETE',
      headers,
    })
    if (!response.ok) {
      throw new Error(`Failed to delete event: ${response.statusText}`)
    }
  },
}

// Event Type API
export const eventTypeApi = {
  getAll: async (): Promise<EventType[]> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types`, { headers })
    return handleResponse<EventType[]>(response)
  },

  getById: async (id: string): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, { headers })
    return handleResponse<EventType>(response)
  },

  create: async (data: CreateEventTypeRequest): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types`, {
      method: 'POST',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<EventType>(response)
  },

  update: async (id: string, data: UpdateEventTypeRequest): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<EventType>(response)
  },

  delete: async (id: string): Promise<void> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, {
      method: 'DELETE',
      headers,
    })
    if (!response.ok) {
      throw new Error(`Failed to delete event type: ${response.statusText}`)
    }
  },
}

// Analytics API
export const analyticsApi = {
  getSummary: async (): Promise<AnalyticsSummary> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/analytics/summary`, { headers })
    return handleResponse<AnalyticsSummary>(response)
  },

  getTrends: async (
    period: 'week' | 'month' | 'year',
    startDate?: string,
    endDate?: string
  ): Promise<TrendData> => {
    const headers = await getAuthHeaders()
    const params = new URLSearchParams({ period })
    if (startDate) params.append('start', startDate)
    if (endDate) params.append('end', endDate)

    const response = await fetch(
      `${API_BASE}/analytics/trends?${params.toString()}`,
      { headers }
    )
    return handleResponse<TrendData>(response)
  },

  getEventTypeTrends: async (
    eventTypeId: string,
    period: 'week' | 'month' | 'year'
  ): Promise<TrendData> => {
    const headers = await getAuthHeaders()
    const response = await fetch(
      `${API_BASE}/analytics/event-type/${eventTypeId}?period=${period}`,
      { headers }
    )
    return handleResponse<TrendData>(response)
  },
}
