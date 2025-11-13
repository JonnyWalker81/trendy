import { useState, useEffect } from 'react'
import { format } from 'date-fns'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'
import { Textarea } from '@/components/ui/textarea'
import { Checkbox } from '@/components/ui/checkbox'
import { useEventTypes } from '@/hooks/api/useEventTypes'
import { DynamicPropertyFields } from '@/components/properties/DynamicPropertyFields'
import type { Event, PropertyValue } from '@/types'

interface EventFormProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  event?: Event | null
  defaultEventTypeId?: string
  onSubmit: (data: {
    event_type_id: string
    timestamp: string
    notes?: string
    is_all_day?: boolean
    end_date?: string
    properties?: Record<string, PropertyValue>
  }) => Promise<void>
  loading?: boolean
}

export function EventForm({
  open,
  onOpenChange,
  event,
  defaultEventTypeId,
  onSubmit,
  loading = false,
}: EventFormProps) {
  const { data: eventTypes = [] } = useEventTypes()

  const [eventTypeId, setEventTypeId] = useState('')
  const [date, setDate] = useState('')
  const [time, setTime] = useState('')
  const [isAllDay, setIsAllDay] = useState(false)
  const [endDate, setEndDate] = useState('')
  const [notes, setNotes] = useState('')
  const [properties, setProperties] = useState<Record<string, PropertyValue>>({})

  // Reset form when dialog opens/closes or event changes
  useEffect(() => {
    if (open) {
      if (event) {
        // Editing existing event
        setEventTypeId(event.event_type_id)
        const eventDate = new Date(event.timestamp)
        setDate(format(eventDate, 'yyyy-MM-dd'))
        setTime(format(eventDate, 'HH:mm'))
        setIsAllDay(event.is_all_day)
        setEndDate(event.end_date ? format(new Date(event.end_date), 'yyyy-MM-dd') : '')
        setNotes(event.notes || '')
        setProperties(event.properties || {})
      } else {
        // Creating new event
        setEventTypeId(defaultEventTypeId || (eventTypes[0]?.id || ''))
        const now = new Date()
        setDate(format(now, 'yyyy-MM-dd'))
        setTime(format(now, 'HH:mm'))
        setIsAllDay(false)
        setEndDate('')
        setNotes('')
        setProperties({})
      }
    }
  }, [open, event, defaultEventTypeId, eventTypes])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!eventTypeId || !date) return

    // Build timestamp
    let timestamp: string
    if (isAllDay) {
      // For all-day events, use noon UTC to avoid timezone issues
      timestamp = new Date(`${date}T12:00:00Z`).toISOString()
    } else {
      // Combine date and time
      timestamp = new Date(`${date}T${time}`).toISOString()
    }

    // Build the request data
    const data: any = {
      event_type_id: eventTypeId,
      timestamp,
      notes: notes.trim() || undefined,
      is_all_day: isAllDay,
    }

    // Add end date if it's an all-day event and end date is provided
    if (isAllDay && endDate) {
      data.end_date = new Date(`${endDate}T12:00:00Z`).toISOString()
    }

    // Add properties if any
    if (Object.keys(properties).length > 0) {
      data.properties = properties
    }

    await onSubmit(data)
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>
            {event ? 'Edit Event' : 'Create Event'}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit}>
          <div className="space-y-4">
            {/* Event Type */}
            <div className="space-y-2">
              <Label htmlFor="event-type">Event Type</Label>
              <Select
                id="event-type"
                value={eventTypeId}
                onChange={(e) => setEventTypeId(e.target.value)}
                required
              >
                <option value="">Select event type</option>
                {eventTypes.map((type) => (
                  <option key={type.id} value={type.id}>
                    {type.name}
                  </option>
                ))}
              </Select>
            </div>

            {/* All-day checkbox */}
            <div className="flex items-center space-x-2">
              <Checkbox
                id="all-day"
                checked={isAllDay}
                onChange={(e) => setIsAllDay(e.target.checked)}
              />
              <Label htmlFor="all-day" className="cursor-pointer">
                All-day event
              </Label>
            </div>

            {/* Date */}
            <div className="space-y-2">
              <Label htmlFor="date">Date</Label>
              <Input
                id="date"
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                required
              />
            </div>

            {/* Time (only if not all-day) */}
            {!isAllDay && (
              <div className="space-y-2">
                <Label htmlFor="time">Time</Label>
                <Input
                  id="time"
                  type="time"
                  value={time}
                  onChange={(e) => setTime(e.target.value)}
                  required
                />
              </div>
            )}

            {/* End Date (only for all-day events) */}
            {isAllDay && (
              <div className="space-y-2">
                <Label htmlFor="end-date">End Date (optional)</Label>
                <Input
                  id="end-date"
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  min={date}
                />
              </div>
            )}

            {/* Notes */}
            <div className="space-y-2">
              <Label htmlFor="notes">Notes (optional)</Label>
              <Textarea
                id="notes"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                placeholder="Add any additional details..."
                rows={3}
              />
            </div>

            {/* Custom Properties */}
            {eventTypeId && (
              <div className="space-y-2">
                <Label>Properties</Label>
                <DynamicPropertyFields
                  eventTypeId={eventTypeId}
                  properties={properties}
                  onChange={setProperties}
                />
              </div>
            )}
          </div>

          <DialogFooter className="mt-6">
            <Button
              type="button"
              variant="outline"
              onClick={() => onOpenChange(false)}
              disabled={loading}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={loading || !eventTypeId || !date}>
              {loading ? 'Saving...' : event ? 'Update' : 'Create'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
