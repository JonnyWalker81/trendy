import { useState } from 'react'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { EventCard } from '@/components/events/EventCard'
import { EventForm } from '@/components/events/EventForm'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import {
  useEvents,
  useCreateEvent,
  useUpdateEvent,
  useDeleteEvent,
} from '@/hooks/api/useEvents'
import type { Event } from '@/types'

export function EventList() {
  const [isFormOpen, setIsFormOpen] = useState(false)
  const [selectedEvent, setSelectedEvent] = useState<Event | null>(null)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [eventToDelete, setEventToDelete] = useState<Event | null>(null)

  const { data: events = [], isLoading } = useEvents()
  const createMutation = useCreateEvent()
  const updateMutation = useUpdateEvent()
  const deleteMutation = useDeleteEvent()

  const handleCreate = () => {
    setSelectedEvent(null)
    setIsFormOpen(true)
  }

  const handleEdit = (event: Event) => {
    setSelectedEvent(event)
    setIsFormOpen(true)
  }

  const handleDelete = (event: Event) => {
    setEventToDelete(event)
    setDeleteDialogOpen(true)
  }

  const confirmDelete = async () => {
    if (eventToDelete) {
      await deleteMutation.mutateAsync(eventToDelete.id)
    }
  }

  const handleSubmit = async (data: {
    event_type_id: string
    timestamp: string
    notes?: string
    is_all_day?: boolean
    end_date?: string
  }) => {
    if (selectedEvent) {
      await updateMutation.mutateAsync({
        id: selectedEvent.id,
        data,
      })
    } else {
      await createMutation.mutateAsync(data)
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
                  <span className="text-xl">📊</span>
                </div>
                <h1 className="ml-3 text-xl font-bold">Trendy</h1>
              </div>
              <div className="hidden sm:ml-8 sm:flex sm:space-x-1">
                <a href="/" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Dashboard
                </a>
                <a href="/events" className="bg-accent text-foreground px-4 py-2 rounded-lg text-sm font-semibold">
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
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-7xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        <div className="mb-8 flex justify-between items-center">
          <div>
            <h2 className="text-3xl font-bold">Events</h2>
            <p className="mt-2 text-muted-foreground">View and manage all your tracked events</p>
          </div>
          <Button onClick={handleCreate}>
            <Plus className="h-4 w-4 mr-2" />
            Add Event
          </Button>
        </div>

        <div className="bg-card rounded-lg border p-6">
          {isLoading ? (
            <div className="text-center py-12 text-muted-foreground">Loading...</div>
          ) : events.length === 0 ? (
            <div className="text-center py-12">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-muted rounded-full mb-4">
                <span className="text-3xl">📋</span>
              </div>
              <p className="text-muted-foreground text-sm">No events to display</p>
              <p className="text-muted-foreground/60 text-xs mt-1">Events you create will appear here</p>
            </div>
          ) : (
            <div className="grid gap-4">
              {events.map((event) => (
                <EventCard
                  key={event.id}
                  event={event}
                  onEdit={handleEdit}
                  onDelete={handleDelete}
                />
              ))}
            </div>
          )}
        </div>
      </main>

      {/* Dialogs */}
      <EventForm
        open={isFormOpen}
        onOpenChange={setIsFormOpen}
        event={selectedEvent}
        onSubmit={handleSubmit}
        loading={createMutation.isPending || updateMutation.isPending}
      />

      <ConfirmDialog
        open={deleteDialogOpen}
        onOpenChange={setDeleteDialogOpen}
        title="Delete Event"
        description={`Are you sure you want to delete this event? This action cannot be undone.`}
        confirmLabel="Delete"
        variant="destructive"
        onConfirm={confirmDelete}
        loading={deleteMutation.isPending}
      />
    </div>
  )
}
