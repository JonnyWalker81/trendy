import { format } from 'date-fns'
import { Calendar, Clock, Pencil, Trash2, FileText } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { getIconByName } from '@/components/ui/icon-constants'
import type { Event } from '@/types'
import { cn } from '@/lib/utils'

interface EventCardProps {
  event: Event
  onEdit: (event: Event) => void
  onDelete: (event: Event) => void
  className?: string
}

export function EventCard({ event, onEdit, onDelete, className }: EventCardProps) {
  const Icon = event.event_type ? getIconByName(event.event_type.icon) : Calendar

  const formatEventDate = () => {
    const date = new Date(event.timestamp)

    if (event.is_all_day) {
      if (event.end_date) {
        const endDate = new Date(event.end_date)
        return `${format(date, 'MMM d')} - ${format(endDate, 'MMM d, yyyy')}`
      }
      return format(date, 'MMMM d, yyyy')
    }

    return format(date, 'MMM d, yyyy • h:mm a')
  }

  return (
    <Card
      className={cn(
        "group relative overflow-hidden transition-all hover:shadow-md",
        className
      )}
    >
      <div className="p-4">
        <div className="flex items-start gap-3">
          {/* Icon with event type color */}
          {event.event_type && (
            <div
              className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg text-white"
              style={{ backgroundColor: event.event_type.color }}
            >
              <Icon className="h-5 w-5" />
            </div>
          )}

          {/* Content */}
          <div className="flex-1 min-w-0">
            {/* Event Type Name */}
            <h3 className="font-semibold text-base truncate">
              {event.event_type?.name || 'Unknown Type'}
            </h3>

            {/* Timestamp */}
            <div className="flex items-center gap-1.5 mt-1 text-sm text-muted-foreground">
              {event.is_all_day ? (
                <Calendar className="h-3.5 w-3.5" />
              ) : (
                <Clock className="h-3.5 w-3.5" />
              )}
              <span>{formatEventDate()}</span>
            </div>

            {/* Notes */}
            {event.notes && (
              <div className="flex items-start gap-1.5 mt-2 text-sm text-muted-foreground">
                <FileText className="h-3.5 w-3.5 mt-0.5 shrink-0" />
                <p className="line-clamp-2">{event.notes}</p>
              </div>
            )}

            {/* Source type indicator */}
            {event.source_type === 'imported' && event.original_title && (
              <div className="mt-2 text-xs text-muted-foreground">
                Imported: {event.original_title}
              </div>
            )}
          </div>

          {/* Actions */}
          <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
            <Button
              size="icon"
              variant="ghost"
              onClick={() => onEdit(event)}
              className="h-8 w-8"
            >
              <Pencil className="h-4 w-4" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onClick={() => onDelete(event)}
              className="h-8 w-8 text-destructive hover:text-destructive"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
        </div>
      </div>
    </Card>
  )
}
