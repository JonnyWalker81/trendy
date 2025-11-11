import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { eventTypeApi } from '@/lib/api-client'
import type { CreateEventTypeRequest, UpdateEventTypeRequest } from '@/types'

// Query keys
export const eventTypeKeys = {
  all: ['event-types'] as const,
  detail: (id: string) => ['event-types', id] as const,
}

// Fetch all event types
export function useEventTypes() {
  return useQuery({
    queryKey: eventTypeKeys.all,
    queryFn: () => eventTypeApi.getAll(),
  })
}

// Fetch single event type
export function useEventType(id: string) {
  return useQuery({
    queryKey: eventTypeKeys.detail(id),
    queryFn: () => eventTypeApi.getById(id),
    enabled: !!id,
  })
}

// Create event type
export function useCreateEventType() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: CreateEventTypeRequest) => eventTypeApi.create(data),
    onSuccess: () => {
      // Invalidate and refetch event types list
      queryClient.invalidateQueries({ queryKey: eventTypeKeys.all })
    },
  })
}

// Update event type
export function useUpdateEventType() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id, data }: { id: string; data: UpdateEventTypeRequest }) =>
      eventTypeApi.update(id, data),
    onSuccess: (_, variables) => {
      // Invalidate specific event type and list
      queryClient.invalidateQueries({ queryKey: eventTypeKeys.detail(variables.id) })
      queryClient.invalidateQueries({ queryKey: eventTypeKeys.all })
    },
  })
}

// Delete event type
export function useDeleteEventType() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: string) => eventTypeApi.delete(id),
    onSuccess: () => {
      // Invalidate event types list
      queryClient.invalidateQueries({ queryKey: eventTypeKeys.all })
      // Also invalidate events since they reference event types
      queryClient.invalidateQueries({ queryKey: ['events'] })
    },
  })
}
