import { supabase } from './supabase'
import { apiLogger, errorContext } from './logger'
import type {
  Event,
  EventType,
  CreateEventRequest,
  UpdateEventRequest,
  CreateEventTypeRequest,
  UpdateEventTypeRequest,
  AnalyticsSummary,
  TrendData,
  PropertyDefinition,
  CreatePropertyDefinitionRequest,
  UpdatePropertyDefinitionRequest,
} from '../types'

// Use environment variable for production, fallback to proxy path for local dev
const API_BASE = import.meta.env.VITE_API_BASE_URL || '/api/v1'

// Log API configuration on initialization
apiLogger.info('API client initialized', {
  api_base: API_BASE,
  mode: import.meta.env.MODE,
})

async function getAuthHeaders() {
  const { data } = await supabase.auth.getSession()
  const token = data.session?.access_token

  return {
    'Content-Type': 'application/json',
    ...(token && { Authorization: `Bearer ${token}` }),
  }
}

async function handleResponse<T>(response: Response, operation: string): Promise<T> {
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: 'Unknown error' }))
    const errorMessage = error.error || `HTTP ${response.status}`

    apiLogger.warn('API request failed', {
      operation,
      status: response.status,
      error: errorMessage,
      url: response.url,
    })

    throw new Error(errorMessage)
  }

  apiLogger.debug('API request successful', {
    operation,
    status: response.status,
  })

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
    return handleResponse<Event[]>(response, 'events.getAll')
  },

  getById: async (id: string): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, { headers })
    return handleResponse<Event>(response, 'events.getById')
  },

  create: async (data: CreateEventRequest): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events`, {
      method: 'POST',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<Event>(response, 'events.create')
  },

  update: async (id: string, data: UpdateEventRequest): Promise<Event> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<Event>(response, 'events.update')
  },

  delete: async (id: string): Promise<void> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/events/${id}`, {
      method: 'DELETE',
      headers,
    })
    if (!response.ok) {
      apiLogger.warn('Failed to delete event', { id, status: response.status })
      throw new Error(`Failed to delete event: ${response.statusText}`)
    }
    apiLogger.debug('Event deleted', { id })
  },

  export: async (params?: {
    startDate?: string
    endDate?: string
    eventTypeIds?: string[]
  }): Promise<Event[]> => {
    const headers = await getAuthHeaders()
    const queryParams = new URLSearchParams()

    if (params?.startDate) {
      queryParams.append('start_date', params.startDate)
    }
    if (params?.endDate) {
      queryParams.append('end_date', params.endDate)
    }
    if (params?.eventTypeIds && params.eventTypeIds.length > 0) {
      queryParams.append('event_type_ids', params.eventTypeIds.join(','))
    }

    const url = `${API_BASE}/events/export${
      queryParams.toString() ? `?${queryParams.toString()}` : ''
    }`
    const response = await fetch(url, { headers })
    return handleResponse<Event[]>(response, 'events.export')
  },
}

// Event Type API
export const eventTypeApi = {
  getAll: async (): Promise<EventType[]> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types`, { headers })
    return handleResponse<EventType[]>(response, 'eventTypes.getAll')
  },

  getById: async (id: string): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, { headers })
    return handleResponse<EventType>(response, 'eventTypes.getById')
  },

  create: async (data: CreateEventTypeRequest): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types`, {
      method: 'POST',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<EventType>(response, 'eventTypes.create')
  },

  update: async (id: string, data: UpdateEventTypeRequest): Promise<EventType> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<EventType>(response, 'eventTypes.update')
  },

  delete: async (id: string): Promise<void> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/event-types/${id}`, {
      method: 'DELETE',
      headers,
    })
    if (!response.ok) {
      apiLogger.warn('Failed to delete event type', { id, status: response.status })
      throw new Error(`Failed to delete event type: ${response.statusText}`)
    }
    apiLogger.debug('Event type deleted', { id })
  },
}

// Analytics API
export const analyticsApi = {
  getSummary: async (): Promise<AnalyticsSummary> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/analytics/summary`, { headers })
    return handleResponse<AnalyticsSummary>(response, 'analytics.getSummary')
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
    return handleResponse<TrendData>(response, 'analytics.getTrends')
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
    return handleResponse<TrendData>(response, 'analytics.getEventTypeTrends')
  },
}

// Property Definition API
export const propertyDefinitionApi = {
  getByEventType: async (eventTypeId: string): Promise<PropertyDefinition[]> => {
    const headers = await getAuthHeaders()
    const response = await fetch(
      `${API_BASE}/event-types/${eventTypeId}/properties`,
      { headers }
    )
    return handleResponse<PropertyDefinition[]>(response, 'propertyDefinitions.getByEventType')
  },

  getById: async (id: string): Promise<PropertyDefinition> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/property-definitions/${id}`, {
      headers,
    })
    return handleResponse<PropertyDefinition>(response, 'propertyDefinitions.getById')
  },

  create: async (
    eventTypeId: string,
    data: Omit<CreatePropertyDefinitionRequest, 'event_type_id'>
  ): Promise<PropertyDefinition> => {
    const headers = await getAuthHeaders()
    const response = await fetch(
      `${API_BASE}/event-types/${eventTypeId}/properties`,
      {
        method: 'POST',
        headers,
        body: JSON.stringify(data),
      }
    )
    return handleResponse<PropertyDefinition>(response, 'propertyDefinitions.create')
  },

  update: async (
    id: string,
    data: UpdatePropertyDefinitionRequest
  ): Promise<PropertyDefinition> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/property-definitions/${id}`, {
      method: 'PUT',
      headers,
      body: JSON.stringify(data),
    })
    return handleResponse<PropertyDefinition>(response, 'propertyDefinitions.update')
  },

  delete: async (id: string): Promise<void> => {
    const headers = await getAuthHeaders()
    const response = await fetch(`${API_BASE}/property-definitions/${id}`, {
      method: 'DELETE',
      headers,
    })
    if (!response.ok) {
      apiLogger.warn('Failed to delete property definition', { id, status: response.status })
      throw new Error(
        `Failed to delete property definition: ${response.statusText}`
      )
    }
    apiLogger.debug('Property definition deleted', { id })
  },
}
