import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { BarChart3, Hash, Calendar, Clock, TrendingUp } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { EventTypePicker } from '@/components/analytics/EventTypePicker'
import { TimeRangePicker } from '@/components/analytics/TimeRangePicker'
import { StatisticCard } from '@/components/analytics/StatisticCard'
import { FrequencyChart } from '@/components/analytics/FrequencyChart'
import { useEventTypes } from '@/hooks/api/useEventTypes'
import { useEventTypeAnalytics } from '@/hooks/api/useAnalytics'
import { supabase } from '@/lib/supabase'
import { formatDistanceToNow } from 'date-fns'

export function Analytics() {
  const navigate = useNavigate()
  const { data: eventTypes = [], isLoading: eventTypesLoading } = useEventTypes()

  // Persistent state using localStorage
  const [selectedEventType, setSelectedEventType] = useState<typeof eventTypes[0] | null>(null)
  const [timeRange, setTimeRange] = useState<'week' | 'month' | 'year'>(() => {
    const saved = localStorage.getItem('analytics-time-range')
    return (saved as 'week' | 'month' | 'year') || 'month'
  })

  // Fetch analytics data for selected event type
  const {
    data: analyticsData,
    isLoading: analyticsLoading,
    error: analyticsError
  } = useEventTypeAnalytics(selectedEventType?.id || null, timeRange)

  // Initialize selected event type from localStorage or first event type
  useEffect(() => {
    if (eventTypes.length > 0 && !selectedEventType) {
      const savedId = localStorage.getItem('analytics-selected-event-type')
      const savedType = eventTypes.find((et) => et.id === savedId)
      setSelectedEventType(savedType || eventTypes[0])
    }
  }, [eventTypes, selectedEventType])

  // Persist time range selection
  useEffect(() => {
    localStorage.setItem('analytics-time-range', timeRange)
  }, [timeRange])

  // Persist event type selection
  useEffect(() => {
    if (selectedEventType) {
      localStorage.setItem('analytics-selected-event-type', selectedEventType.id)
    }
  }, [selectedEventType])

  const handleLogout = async () => {
    await supabase.auth.signOut()
    navigate('/login')
  }

  // Calculate statistics
  const statistics = analyticsData
    ? {
        total: analyticsData.data.reduce((sum, point) => sum + point.count, 0),
        average: analyticsData.average,
        trend: analyticsData.trend,
        lastOccurrence: analyticsData.data.length > 0
          ? analyticsData.data[analyticsData.data.length - 1].date
          : null,
      }
    : null

  const getAverageLabel = () => {
    switch (timeRange) {
      case 'week':
        return 'Avg/Day'
      case 'month':
        return 'Avg/Week'
      case 'year':
        return 'Avg/Month'
    }
  }

  const getAverageIcon = () => {
    switch (timeRange) {
      case 'week':
        return Calendar
      case 'month':
        return Calendar
      case 'year':
        return Calendar
    }
  }

  return (
    <div className="min-h-screen bg-background">
      {/* Navigation */}
      <nav className="bg-card shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex items-center">
              <div className="flex-shrink-0 flex items-center">
                <div className="w-10 h-10 bg-gradient-to-br from-primary to-primary/80 rounded-xl flex items-center justify-center shadow-md">
                  <BarChart3 className="h-5 w-5 text-primary-foreground" />
                </div>
                <h1 className="ml-3 text-xl font-bold">TrendSight</h1>
              </div>
              <div className="hidden sm:ml-8 sm:flex sm:space-x-1">
                <a
                  href="/"
                  className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition"
                >
                  Dashboard
                </a>
                <a
                  href="/events"
                  className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition"
                >
                  Events
                </a>
                <a
                  href="/analytics"
                  className="bg-accent text-foreground px-4 py-2 rounded-lg text-sm font-semibold"
                >
                  Analytics
                </a>
                <a
                  href="/settings"
                  className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition"
                >
                  Settings
                </a>
              </div>
            </div>
            <div className="flex items-center">
              <button
                onClick={handleLogout}
                className="px-4 py-2 text-sm font-medium text-muted-foreground hover:text-foreground hover:bg-accent rounded-lg transition"
              >
                Logout
              </button>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        {/* Header */}
        <div className="mb-8">
          <h2 className="text-3xl font-bold">Analytics</h2>
          <p className="mt-2 text-muted-foreground">
            Visualize trends and patterns in your event data
          </p>
        </div>

        {/* Loading State */}
        {eventTypesLoading && (
          <div className="flex items-center justify-center py-12">
            <div className="text-center">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-muted rounded-full mb-4 animate-pulse">
                <BarChart3 className="h-8 w-8 text-muted-foreground" />
              </div>
              <p className="text-muted-foreground text-sm">Loading analytics...</p>
            </div>
          </div>
        )}

        {/* Empty State - No Event Types */}
        {!eventTypesLoading && eventTypes.length === 0 && (
          <Card className="p-12">
            <div className="text-center">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-muted rounded-full mb-4">
                <BarChart3 className="h-8 w-8 text-muted-foreground" />
              </div>
              <h3 className="text-lg font-semibold mb-2">No Event Types</h3>
              <p className="text-muted-foreground text-sm mb-4">
                Create an event type in Settings to start tracking analytics
              </p>
              <button
                onClick={() => navigate('/settings')}
                className="px-4 py-2 bg-primary text-primary-foreground rounded-lg text-sm font-medium hover:bg-primary/90 transition"
              >
                Go to Settings
              </button>
            </div>
          </Card>
        )}

        {/* Main Analytics Content */}
        {!eventTypesLoading && eventTypes.length > 0 && (
          <div className="space-y-6">
            {/* Event Type Picker */}
            <Card className="p-4">
              <h3 className="text-sm font-medium text-muted-foreground mb-3">
                Select Event Type
              </h3>
              <EventTypePicker
                eventTypes={eventTypes}
                selectedEventType={selectedEventType}
                onSelectEventType={setSelectedEventType}
              />
            </Card>

            {/* Time Range Picker */}
            {selectedEventType && (
              <div className="flex justify-center">
                <TimeRangePicker value={timeRange} onChange={setTimeRange} />
              </div>
            )}

            {/* Analytics Error State */}
            {analyticsError && (
              <Card className="p-6">
                <div className="text-center text-destructive">
                  <p className="text-sm">Failed to load analytics data</p>
                  <p className="text-xs mt-1 text-muted-foreground">
                    {analyticsError.message}
                  </p>
                </div>
              </Card>
            )}

            {/* Statistics Cards */}
            {selectedEventType && analyticsLoading && (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                {[1, 2, 3, 4].map((i) => (
                  <Card key={i} className="p-4 animate-pulse">
                    <div className="h-20 bg-muted rounded" />
                  </Card>
                ))}
              </div>
            )}

            {selectedEventType && !analyticsLoading && statistics && (
              <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
                <StatisticCard
                  title="Total Events"
                  value={statistics.total}
                  icon={Hash}
                  subtitle="All time"
                />
                <StatisticCard
                  title={getAverageLabel()}
                  value={statistics.average.toFixed(1)}
                  icon={getAverageIcon()}
                  subtitle="Average frequency"
                />
                <StatisticCard
                  title="Trend"
                  value={
                    statistics.trend === 'increasing'
                      ? 'Up'
                      : statistics.trend === 'decreasing'
                      ? 'Down'
                      : 'Stable'
                  }
                  icon={TrendingUp}
                  trend={statistics.trend}
                />
                <StatisticCard
                  title="Last Event"
                  value={
                    statistics.lastOccurrence
                      ? formatDistanceToNow(new Date(statistics.lastOccurrence), {
                          addSuffix: true,
                        })
                      : 'Never'
                  }
                  icon={Clock}
                  subtitle="Most recent"
                />
              </div>
            )}

            {/* Frequency Chart */}
            {selectedEventType && !analyticsLoading && analyticsData && (
              <FrequencyChart
                data={analyticsData.data}
                color={selectedEventType.color}
                timeRange={timeRange}
              />
            )}

            {/* Loading Chart */}
            {selectedEventType && analyticsLoading && (
              <Card className="p-6">
                <div className="h-64 flex items-center justify-center bg-muted/20 rounded animate-pulse">
                  <div className="text-center">
                    <BarChart3 className="h-12 w-12 text-muted-foreground mx-auto mb-2" />
                    <p className="text-sm text-muted-foreground">Loading chart...</p>
                  </div>
                </div>
              </Card>
            )}

            {/* No Event Selected State */}
            {!selectedEventType && (
              <Card className="p-12">
                <div className="text-center">
                  <BarChart3 className="h-12 w-12 text-muted-foreground mx-auto mb-4" />
                  <p className="text-muted-foreground text-sm">
                    Select an event type to view analytics
                  </p>
                </div>
              </Card>
            )}
          </div>
        )}
      </main>
    </div>
  )
}
