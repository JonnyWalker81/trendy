import { Pencil, Trash2 } from 'lucide-react'
import { Card } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { getIconByName } from '@/components/ui/icon-constants'
import type { EventType } from '@/types'
import { cn } from '@/lib/utils'

interface EventTypeCardProps {
  eventType: EventType
  onEdit: (eventType: EventType) => void
  onDelete: (eventType: EventType) => void
  className?: string
}

export function EventTypeCard({ eventType, onEdit, onDelete, className }: EventTypeCardProps) {
  const Icon = getIconByName(eventType.icon)

  return (
    <Card
      className={cn(
        "group relative overflow-hidden transition-all hover:shadow-md",
        className
      )}
    >
      <div className="p-4">
        <div className="flex items-start justify-between gap-3">
          {/* Icon and Color */}
          <div
            className="flex h-12 w-12 items-center justify-center rounded-lg text-white"
            style={{ backgroundColor: eventType.color }}
          >
            <Icon className="h-6 w-6" />
          </div>

          {/* Actions */}
          <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
            <Button
              size="icon"
              variant="ghost"
              onClick={() => onEdit(eventType)}
              className="h-8 w-8"
            >
              <Pencil className="h-4 w-4" />
            </Button>
            <Button
              size="icon"
              variant="ghost"
              onClick={() => onDelete(eventType)}
              className="h-8 w-8 text-destructive hover:text-destructive"
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
        </div>

        {/* Name */}
        <h3 className="mt-3 font-semibold text-lg">{eventType.name}</h3>
      </div>
    </Card>
  )
}
