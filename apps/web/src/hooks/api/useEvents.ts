import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { eventApi } from '@/lib/api-client'
import type { Event, CreateEventRequest, UpdateEventRequest } from '@/types'

// Query keys
export const eventKeys = {
  all: ['events'] as const,
  lists: () => [...eventKeys.all, 'list'] as const,
  list: (limit: number, offset: number) => [...eventKeys.lists(), { limit, offset }] as const,
  detail: (id: string) => [...eventKeys.all, id] as const,
}

// Fetch all events with pagination
export function useEvents(limit = 50, offset = 0) {
  return useQuery({
    queryKey: eventKeys.list(limit, offset),
    queryFn: () => eventApi.getAll(limit, offset),
  })
}

// Fetch single event
export function useEvent(id: string) {
  return useQuery({
    queryKey: eventKeys.detail(id),
    queryFn: () => eventApi.getById(id),
    enabled: !!id,
  })
}

// Create event
export function useCreateEvent() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: CreateEventRequest) => eventApi.create(data),
    onSuccess: () => {
      // Invalidate events list
      queryClient.invalidateQueries({ queryKey: eventKeys.lists() })
      // Also invalidate analytics since new event affects stats
      queryClient.invalidateQueries({ queryKey: ['analytics'] })
    },
  })
}

// Update event
export function useUpdateEvent() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateEventRequest }) =>
      eventApi.update(id, data),
    onSuccess: (_, variables) => {
      // Invalidate specific event and lists
      queryClient.invalidateQueries({ queryKey: eventKeys.detail(variables.id) })
      queryClient.invalidateQueries({ queryKey: eventKeys.lists() })
      queryClient.invalidateQueries({ queryKey: ['analytics'] })
    },
  })
}

// Delete event
export function useDeleteEvent() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => eventApi.delete(id),
    onSuccess: () => {
      // Invalidate events list
      queryClient.invalidateQueries({ queryKey: eventKeys.lists() })
      queryClient.invalidateQueries({ queryKey: ['analytics'] })
    },
  })
}
