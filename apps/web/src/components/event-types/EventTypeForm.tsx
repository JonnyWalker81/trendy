import { useState, useEffect } from 'react'
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
import { ColorPicker } from '@/components/ui/color-picker'
import { PRESET_COLORS } from '@/components/ui/color-constants'
import { IconPicker } from '@/components/ui/icon-picker'
import { PRESET_ICONS } from '@/components/ui/icon-constants'
import type { EventType } from '@/types'

interface EventTypeFormProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  eventType?: EventType | null
  onSubmit: (data: { name: string; color: string; icon: string }) => Promise<void>
  loading?: boolean
}

export function EventTypeForm({
  open,
  onOpenChange,
  eventType,
  onSubmit,
  loading = false,
}: EventTypeFormProps) {
  const [name, setName] = useState('')
  const [color, setColor] = useState(PRESET_COLORS[0].value)
  const [icon, setIcon] = useState(PRESET_ICONS[0].name)

  // Reset form when dialog opens/closes or eventType changes
  useEffect(() => {
    if (open) {
      if (eventType) {
        setName(eventType.name)
        setColor(eventType.color)
        setIcon(eventType.icon)
      } else {
        setName('')
        setColor(PRESET_COLORS[0].value)
        setIcon(PRESET_ICONS[0].name)
      }
    }
  }, [open, eventType])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!name.trim()) return

    await onSubmit({ name: name.trim(), color, icon })
    onOpenChange(false)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>
            {eventType ? 'Edit Event Type' : 'Create Event Type'}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit}>
          <div className="space-y-6">
            {/* Name */}
            <div className="space-y-2">
              <Label htmlFor="name">Name</Label>
              <Input
                id="name"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="e.g., Work, Exercise, Reading"
                required
                autoFocus
              />
            </div>

            {/* Color Picker */}
            <div className="space-y-2">
              <Label>Color</Label>
              <ColorPicker value={color} onChange={setColor} />
            </div>

            {/* Icon Picker */}
            <div className="space-y-2">
              <Label>Icon</Label>
              <IconPicker value={icon} onChange={setIcon} />
            </div>
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
            <Button type="submit" disabled={loading || !name.trim()}>
              {loading ? 'Saving...' : eventType ? 'Update' : 'Create'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
