import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'
import { EventForm } from '@/components/events/EventForm'
import { getIconByName } from '@/components/ui/icon-picker'
import { useEventTypes } from '@/hooks/api/useEventTypes'
import { useEvents, useCreateEvent } from '@/hooks/api/useEvents'
import { supabase } from '../lib/supabase'
import { format } from 'date-fns'

export function Dashboard() {
  const navigate = useNavigate()
  const [isFormOpen, setIsFormOpen] = useState(false)
  const [selectedEventTypeId, setSelectedEventTypeId] = useState<string>()

  const { data: eventTypes = [] } = useEventTypes()
  const { data: events = [] } = useEvents(10, 0) // Get last 10 events
  const createMutation = useCreateEvent()

  const handleLogout = async () => {
    await supabase.auth.signOut()
    navigate('/login')
  }

  const handleBubbleClick = (eventTypeId: string) => {
    setSelectedEventTypeId(eventTypeId)
    setIsFormOpen(true)
  }

  const handleAddEvent = () => {
    setSelectedEventTypeId(undefined)
    setIsFormOpen(true)
  }

  const handleSubmit = async (data: {
    event_type_id: string
    timestamp: string
    notes?: string
    is_all_day?: boolean
    end_date?: string
  }) => {
    await createMutation.mutateAsync(data)
  }

  // Calculate stats
  const totalEvents = events.length
  const eventTypesCount = eventTypes.length

  return (
    <div className="min-h-screen bg-background">
      {/* Navigation */}
      <nav className="bg-card shadow-sm border-b">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex justify-between h-16">
            <div className="flex items-center">
              <div className="flex-shrink-0 flex items-center">
                <div className="w-10 h-10 bg-gradient-to-br from-primary to-primary/80 rounded-xl flex items-center justify-center shadow-md">
                  <span className="text-xl">📊</span>
                </div>
                <h1 className="ml-3 text-xl font-bold">Trendy</h1>
              </div>
              <div className="hidden sm:ml-8 sm:flex sm:space-x-1">
                <a href="/" className="bg-accent text-foreground px-4 py-2 rounded-lg text-sm font-semibold">
                  Dashboard
                </a>
                <a href="/events" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Events
                </a>
                <a href="/analytics" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Analytics
                </a>
                <a href="/settings" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
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
          <h2 className="text-3xl font-bold">Dashboard</h2>
          <p className="mt-2 text-muted-foreground">Welcome back! Here's your event tracking overview.</p>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 mb-8">
          <Card className="p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="h-14 w-14 rounded-xl bg-gradient-to-br from-blue-500 to-blue-600 flex items-center justify-center text-white text-2xl shadow-md">
                  📊
                </div>
              </div>
              <div className="ml-5 flex-1">
                <dt className="text-sm font-medium text-muted-foreground truncate">Total Events</dt>
                <dd className="mt-1 text-3xl font-bold">{totalEvents}</dd>
                <dd className="mt-1 text-xs text-muted-foreground">All time</dd>
              </div>
            </div>
          </Card>

          <Card className="p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="h-14 w-14 rounded-xl bg-gradient-to-br from-purple-500 to-purple-600 flex items-center justify-center text-white text-2xl shadow-md">
                  🏷️
                </div>
              </div>
              <div className="ml-5 flex-1">
                <dt className="text-sm font-medium text-muted-foreground truncate">Event Types</dt>
                <dd className="mt-1 text-3xl font-bold">{eventTypesCount}</dd>
                <dd className="mt-1 text-xs text-muted-foreground">Categories</dd>
              </div>
            </div>
          </Card>

          <Card className="p-6">
            <div className="flex items-center">
              <div className="flex-shrink-0">
                <div className="h-14 w-14 rounded-xl bg-gradient-to-br from-green-500 to-green-600 flex items-center justify-center text-white text-2xl shadow-md">
                  ⚡
                </div>
              </div>
              <div className="ml-5 flex-1">
                <dt className="text-sm font-medium text-muted-foreground truncate">Quick Add</dt>
                <dd className="mt-2">
                  <Button size="sm" onClick={handleAddEvent} className="w-full">
                    <Plus className="h-4 w-4 mr-1" />
                    New Event
                  </Button>
                </dd>
              </div>
            </div>
          </Card>
        </div>

        {/* Event Type Bubbles (like iOS app) */}
        {eventTypes.length > 0 && (
          <Card className="p-6 mb-8">
            <h3 className="text-lg font-semibold mb-4">Quick Track</h3>
            <p className="text-sm text-muted-foreground mb-4">
              Tap an event type to quickly record an event
            </p>
            <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-6 gap-4">
              {eventTypes.map((eventType) => {
                const Icon = getIconByName(eventType.icon)
                return (
                  <button
                    key={eventType.id}
                    onClick={() => handleBubbleClick(eventType.id)}
                    className="flex flex-col items-center gap-2 p-4 rounded-lg border-2 border-transparent hover:border-primary transition-all hover:scale-105"
                  >
                    <div
                      className="h-16 w-16 rounded-full flex items-center justify-center text-white shadow-lg"
                      style={{ backgroundColor: eventType.color }}
                    >
                      <Icon className="h-8 w-8" />
                    </div>
                    <span className="text-sm font-medium text-center line-clamp-2">
                      {eventType.name}
                    </span>
                  </button>
                )
              })}
            </div>
          </Card>
        )}

        {/* Recent Activity */}
        <Card className="p-6">
          <div className="flex justify-between items-center mb-4">
            <h3 className="text-lg font-semibold">Recent Activity</h3>
            {events.length > 0 && (
              <a href="/events" className="text-sm text-primary hover:underline">
                View all
              </a>
            )}
          </div>

          {events.length === 0 ? (
            <div className="text-center py-12">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-muted rounded-full mb-4">
                <span className="text-3xl">📝</span>
              </div>
              <p className="text-muted-foreground text-sm">No events yet</p>
              <p className="text-muted-foreground/60 text-xs mt-1">
                Start tracking your first event to see it here
              </p>
              {eventTypes.length === 0 ? (
                <Button
                  className="mt-4"
                  onClick={() => navigate('/settings')}
                >
                  Create Event Type First
                </Button>
              ) : (
                <Button
                  className="mt-4"
                  onClick={handleAddEvent}
                >
                  Add Your First Event
                </Button>
              )}
            </div>
          ) : (
            <div className="space-y-3">
              {events.slice(0, 5).map((event) => {
                const Icon = event.event_type ? getIconByName(event.event_type.icon) : null
                return (
                  <div
                    key={event.id}
                    className="flex items-center gap-3 p-3 rounded-lg hover:bg-accent transition"
                  >
                    {event.event_type && Icon && (
                      <div
                        className="h-10 w-10 rounded-lg flex items-center justify-center text-white shrink-0"
                        style={{ backgroundColor: event.event_type.color }}
                      >
                        <Icon className="h-5 w-5" />
                      </div>
                    )}
                    <div className="flex-1 min-w-0">
                      <p className="font-medium truncate">
                        {event.event_type?.name || 'Unknown'}
                      </p>
                      <p className="text-sm text-muted-foreground">
                        {format(new Date(event.timestamp), 'MMM d, yyyy • h:mm a')}
                      </p>
                    </div>
                  </div>
                )
              })}
            </div>
          )}
        </Card>
      </main>

      {/* Event Form Dialog */}
      <EventForm
        open={isFormOpen}
        onOpenChange={setIsFormOpen}
        defaultEventTypeId={selectedEventTypeId}
        onSubmit={handleSubmit}
        loading={createMutation.isPending}
      />
    </div>
  )
}
