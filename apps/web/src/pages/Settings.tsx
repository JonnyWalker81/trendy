import { useState } from 'react'
import { Plus } from 'lucide-react'
import { Button } from '@/components/ui/button'
import { EventTypeCard } from '@/components/event-types/EventTypeCard'
import { EventTypeForm } from '@/components/event-types/EventTypeForm'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import {
  useEventTypes,
  useCreateEventType,
  useUpdateEventType,
  useDeleteEventType,
} from '@/hooks/api/useEventTypes'
import type { EventType } from '@/types'

export function Settings() {
  const [isFormOpen, setIsFormOpen] = useState(false)
  const [selectedEventType, setSelectedEventType] = useState<EventType | null>(null)
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [eventTypeToDelete, setEventTypeToDelete] = useState<EventType | null>(null)

  const { data: eventTypes = [], isLoading } = useEventTypes()
  const createMutation = useCreateEventType()
  const updateMutation = useUpdateEventType()
  const deleteMutation = useDeleteEventType()

  const handleCreate = () => {
    setSelectedEventType(null)
    setIsFormOpen(true)
  }

  const handleEdit = (eventType: EventType) => {
    setSelectedEventType(eventType)
    setIsFormOpen(true)
  }

  const handleDelete = (eventType: EventType) => {
    setEventTypeToDelete(eventType)
    setDeleteDialogOpen(true)
  }

  const confirmDelete = async () => {
    if (eventTypeToDelete) {
      await deleteMutation.mutateAsync(eventTypeToDelete.id)
    }
  }

  const handleSubmit = async (data: { name: string; color: string; icon: string }) => {
    if (selectedEventType) {
      await updateMutation.mutateAsync({
        id: selectedEventType.id,
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
                <h1 className="ml-3 text-xl font-bold">TrendSight</h1>
              </div>
              <div className="hidden sm:ml-8 sm:flex sm:space-x-1">
                <a href="/" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Dashboard
                </a>
                <a href="/events" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Events
                </a>
                <a href="/analytics" className="text-muted-foreground hover:text-foreground hover:bg-accent px-4 py-2 rounded-lg text-sm font-medium transition">
                  Analytics
                </a>
                <a href="/settings" className="bg-accent text-foreground px-4 py-2 rounded-lg text-sm font-semibold">
                  Settings
                </a>
              </div>
            </div>
          </div>
        </div>
      </nav>

      {/* Main Content */}
      <main className="max-w-4xl mx-auto py-8 px-4 sm:px-6 lg:px-8">
        <div className="mb-8">
          <h2 className="text-3xl font-bold">Settings</h2>
          <p className="mt-2 text-muted-foreground">Manage your event types and preferences</p>
        </div>

        {/* Event Types Section */}
        <div className="bg-card rounded-lg border p-6 mb-6">
          <div className="flex justify-between items-center mb-6">
            <h3 className="text-lg font-semibold">Event Types</h3>
            <Button onClick={handleCreate}>
              <Plus className="h-4 w-4 mr-2" />
              Add Type
            </Button>
          </div>

          {isLoading ? (
            <div className="text-center py-8 text-muted-foreground">Loading...</div>
          ) : eventTypes.length === 0 ? (
            <div className="text-center py-8">
              <div className="inline-flex items-center justify-center w-16 h-16 bg-muted rounded-full mb-4">
                <span className="text-3xl">🏷️</span>
              </div>
              <p className="text-muted-foreground text-sm">No event types yet</p>
              <p className="text-muted-foreground/60 text-xs mt-1">Create your first event type to get started</p>
            </div>
          ) : (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {eventTypes.map((eventType) => (
                <EventTypeCard
                  key={eventType.id}
                  eventType={eventType}
                  onEdit={handleEdit}
                  onDelete={handleDelete}
                />
              ))}
            </div>
          )}
        </div>

      </main>

      {/* Dialogs */}
      <EventTypeForm
        open={isFormOpen}
        onOpenChange={setIsFormOpen}
        eventType={selectedEventType}
        onSubmit={handleSubmit}
        loading={createMutation.isPending || updateMutation.isPending}
      />

      <ConfirmDialog
        open={deleteDialogOpen}
        onOpenChange={setDeleteDialogOpen}
        title="Delete Event Type"
        description={`Are you sure you want to delete "${eventTypeToDelete?.name}"? This will also delete all events of this type.`}
        confirmLabel="Delete"
        variant="destructive"
        onConfirm={confirmDelete}
        loading={deleteMutation.isPending}
      />
    </div>
  )
}
