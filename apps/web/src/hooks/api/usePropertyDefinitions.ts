import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { propertyDefinitionApi } from '@/lib/api-client'
import type {
  CreatePropertyDefinitionRequest,
  UpdatePropertyDefinitionRequest,
} from '@/types'

// Query keys
export const propertyDefinitionKeys = {
  all: ['property-definitions'] as const,
  byEventType: (eventTypeId: string) =>
    ['property-definitions', 'event-type', eventTypeId] as const,
  detail: (id: string) => ['property-definitions', id] as const,
}

// Fetch all property definitions for an event type
export function usePropertyDefinitions(eventTypeId: string) {
  return useQuery({
    queryKey: propertyDefinitionKeys.byEventType(eventTypeId),
    queryFn: () => propertyDefinitionApi.getByEventType(eventTypeId),
    enabled: !!eventTypeId,
  })
}

// Fetch single property definition
export function usePropertyDefinition(id: string) {
  return useQuery({
    queryKey: propertyDefinitionKeys.detail(id),
    queryFn: () => propertyDefinitionApi.getById(id),
    enabled: !!id,
  })
}

// Create property definition
export function useCreatePropertyDefinition() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({
      eventTypeId,
      data,
    }: {
      eventTypeId: string
      data: Omit<CreatePropertyDefinitionRequest, 'event_type_id'>
    }) => propertyDefinitionApi.create(eventTypeId, data),
    onSuccess: (_, variables) => {
      // Invalidate property definitions list for this event type
      queryClient.invalidateQueries({
        queryKey: propertyDefinitionKeys.byEventType(variables.eventTypeId),
      })
    },
  })
}

// Update property definition
export function useUpdatePropertyDefinition() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({
      id,
      data,
    }: {
      id: string
      data: UpdatePropertyDefinitionRequest
    }) => propertyDefinitionApi.update(id, data),
    onSuccess: (updatedDef) => {
      // Invalidate specific property definition
      queryClient.invalidateQueries({
        queryKey: propertyDefinitionKeys.detail(updatedDef.id),
      })
      // Invalidate list for this event type
      queryClient.invalidateQueries({
        queryKey: propertyDefinitionKeys.byEventType(updatedDef.event_type_id),
      })
    },
  })
}

// Delete property definition
export function useDeletePropertyDefinition() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id }: { id: string; eventTypeId: string }) =>
      propertyDefinitionApi.delete(id),
    onSuccess: (_, variables) => {
      // Invalidate property definitions list for this event type
      queryClient.invalidateQueries({
        queryKey: propertyDefinitionKeys.byEventType(variables.eventTypeId),
      })
    },
  })
}
