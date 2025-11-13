import { useQuery } from '@tanstack/react-query'
import { analyticsApi } from '@/lib/api-client'
import type { AnalyticsSummary, TrendData } from '@/types'

export function useAnalyticsSummary() {
  return useQuery<AnalyticsSummary>({
    queryKey: ['analytics', 'summary'],
    queryFn: () => analyticsApi.getSummary(),
    staleTime: 5 * 60 * 1000, // 5 minutes
  })
}

export function useAnalyticsTrends(
  period: 'week' | 'month' | 'year',
  startDate?: string,
  endDate?: string
) {
  return useQuery<TrendData>({
    queryKey: ['analytics', 'trends', period, startDate, endDate],
    queryFn: () => analyticsApi.getTrends(period, startDate, endDate),
    staleTime: 5 * 60 * 1000,
  })
}

export function useEventTypeAnalytics(
  eventTypeId: string | null,
  period: 'week' | 'month' | 'year'
) {
  return useQuery<TrendData>({
    queryKey: ['analytics', 'event-type', eventTypeId, period],
    queryFn: () => analyticsApi.getEventTypeTrends(eventTypeId!, period),
    enabled: !!eventTypeId,
    staleTime: 5 * 60 * 1000,
  })
}
