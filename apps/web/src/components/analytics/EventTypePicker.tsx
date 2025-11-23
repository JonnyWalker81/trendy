import { EventType } from '@/types'
import { getIconByName } from '@/components/ui/icon-constants'

interface EventTypePickerProps {
  eventTypes: EventType[]
  selectedEventType: EventType | null
  onSelectEventType: (eventType: EventType) => void
}

export function EventTypePicker({
  eventTypes,
  selectedEventType,
  onSelectEventType,
}: EventTypePickerProps) {
  return (
    <div className="overflow-x-auto pb-2">
      <div className="flex gap-3 min-w-max">
        {eventTypes.map((eventType) => {
          const Icon = getIconByName(eventType.icon)
          const isSelected = selectedEventType?.id === eventType.id

          return (
            <button
              key={eventType.id}
              onClick={() => onSelectEventType(eventType)}
              className="flex items-center gap-2 px-4 py-2 rounded-full transition-all whitespace-nowrap"
              style={{
                backgroundColor: isSelected ? eventType.color : 'hsl(var(--card))',
                color: isSelected ? 'white' : 'hsl(var(--foreground))',
                border: isSelected ? 'none' : '1px solid hsl(var(--border))',
              }}
            >
              <Icon className="h-4 w-4" />
              <span className="text-sm font-medium">{eventType.name}</span>
            </button>
          )
        })}
      </div>
    </div>
  )
}
