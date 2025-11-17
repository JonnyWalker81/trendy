import { useState } from 'react'
import { format, subDays, subMonths, subYears } from 'date-fns'
import { Download, Loader2 } from 'lucide-react'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '../ui/dialog'
import { Button } from '../ui/button'
import { Label } from '../ui/label'
import { Input } from '../ui/input'
import { Checkbox } from '../ui/checkbox'
import { useExportEvents } from '@/hooks/api/useEvents'
import { useEventTypes } from '@/hooks/api/useEventTypes'
import { exportEvents, type ExportFormat } from '@/lib/export-utils'
import type { EventType } from '@/types'

interface ExportDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
}

type DateRangePreset = 'all' | 'last7' | 'last30' | 'lastYear' | 'custom'

export function ExportDialog({ open, onOpenChange }: ExportDialogProps) {
  const [format, setFormat] = useState<ExportFormat>('csv')
  const [dateRangePreset, setDateRangePreset] = useState<DateRangePreset>('all')
  const [customStartDate, setCustomStartDate] = useState('')
  const [customEndDate, setCustomEndDate] = useState('')
  const [selectedEventTypeIds, setSelectedEventTypeIds] = useState<string[]>([])
  const [includeProperties, setIncludeProperties] = useState(true)

  const { mutateAsync: fetchExportData, isPending } = useExportEvents()
  const { data: eventTypes = [] } = useEventTypes()

  const handleEventTypeToggle = (eventTypeId: string) => {
    setSelectedEventTypeIds((prev) =>
      prev.includes(eventTypeId)
        ? prev.filter((id) => id !== eventTypeId)
        : [...prev, eventTypeId]
    )
  }

  const handleExport = async () => {
    try {
      // Calculate date range based on preset
      let startDate: string | undefined
      let endDate: string | undefined

      const now = new Date()
      switch (dateRangePreset) {
        case 'last7':
          startDate = subDays(now, 7).toISOString()
          endDate = now.toISOString()
          break
        case 'last30':
          startDate = subDays(now, 30).toISOString()
          endDate = now.toISOString()
          break
        case 'lastYear':
          startDate = subYears(now, 1).toISOString()
          endDate = now.toISOString()
          break
        case 'custom':
          if (customStartDate) {
            startDate = new Date(customStartDate).toISOString()
          }
          if (customEndDate) {
            endDate = new Date(customEndDate).toISOString()
          }
          break
        case 'all':
        default:
          // No date filters
          break
      }

      // Fetch data from API
      const events = await fetchExportData({
        startDate,
        endDate,
        eventTypeIds:
          selectedEventTypeIds.length > 0 ? selectedEventTypeIds : undefined,
      })

      // Export using utility
      exportEvents(events, format, includeProperties)

      // Close dialog
      onOpenChange(false)

      // Reset form
      setDateRangePreset('all')
      setSelectedEventTypeIds([])
      setFormat('csv')
      setIncludeProperties(true)
      setCustomStartDate('')
      setCustomEndDate('')
    } catch (error) {
      console.error('Export failed:', error)
      // You could add toast notification here
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <div className="flex items-center gap-3">
            <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary/10">
              <Download className="h-5 w-5 text-primary" />
            </div>
            <DialogTitle>Export Events</DialogTitle>
          </div>
          <DialogDescription>
            Choose your export format and filters to download your event data.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-6 py-4">
          {/* Export Format */}
          <div className="space-y-3">
            <Label>Export Format</Label>
            <div className="flex gap-3">
              <button
                type="button"
                onClick={() => setFormat('csv')}
                className={`flex-1 px-4 py-3 rounded-md border-2 transition-colors ${
                  format === 'csv'
                    ? 'border-primary bg-primary/5'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <div className="font-medium">CSV</div>
                <div className="text-sm text-gray-500">
                  Opens in Excel, Google Sheets
                </div>
              </button>
              <button
                type="button"
                onClick={() => setFormat('json')}
                className={`flex-1 px-4 py-3 rounded-md border-2 transition-colors ${
                  format === 'json'
                    ? 'border-primary bg-primary/5'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <div className="font-medium">JSON</div>
                <div className="text-sm text-gray-500">
                  Structured data format
                </div>
              </button>
            </div>
          </div>

          {/* Date Range */}
          <div className="space-y-3">
            <Label>Date Range</Label>
            <div className="grid grid-cols-2 gap-2">
              {[
                { value: 'all', label: 'All Time' },
                { value: 'last7', label: 'Last 7 Days' },
                { value: 'last30', label: 'Last 30 Days' },
                { value: 'lastYear', label: 'Last Year' },
              ].map(({ value, label }) => (
                <button
                  key={value}
                  type="button"
                  onClick={() => setDateRangePreset(value as DateRangePreset)}
                  className={`px-3 py-2 text-sm rounded-md border transition-colors ${
                    dateRangePreset === value
                      ? 'border-primary bg-primary/5 font-medium'
                      : 'border-gray-200 hover:border-gray-300'
                  }`}
                >
                  {label}
                </button>
              ))}
              <button
                type="button"
                onClick={() => setDateRangePreset('custom')}
                className={`px-3 py-2 text-sm rounded-md border transition-colors ${
                  dateRangePreset === 'custom'
                    ? 'border-primary bg-primary/5 font-medium'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                Custom Range
              </button>
            </div>

            {dateRangePreset === 'custom' && (
              <div className="grid grid-cols-2 gap-3 pt-2">
                <div>
                  <Label htmlFor="start-date" className="text-xs">
                    Start Date
                  </Label>
                  <Input
                    id="start-date"
                    type="date"
                    value={customStartDate}
                    onChange={(e) => setCustomStartDate(e.target.value)}
                    max={customEndDate || format(new Date(), 'yyyy-MM-dd')}
                  />
                </div>
                <div>
                  <Label htmlFor="end-date" className="text-xs">
                    End Date
                  </Label>
                  <Input
                    id="end-date"
                    type="date"
                    value={customEndDate}
                    onChange={(e) => setCustomEndDate(e.target.value)}
                    min={customStartDate}
                    max={format(new Date(), 'yyyy-MM-dd')}
                  />
                </div>
              </div>
            )}
          </div>

          {/* Event Type Filter */}
          <div className="space-y-3">
            <Label>Event Types (optional)</Label>
            <div className="text-sm text-gray-500 mb-2">
              Leave empty to export all event types
            </div>
            <div className="border rounded-md p-3 max-h-48 overflow-y-auto space-y-2">
              {eventTypes.length === 0 && (
                <div className="text-sm text-gray-400 text-center py-2">
                  No event types found
                </div>
              )}
              {eventTypes.map((eventType: EventType) => (
                <label
                  key={eventType.id}
                  className="flex items-center gap-2 p-2 hover:bg-gray-50 rounded cursor-pointer"
                >
                  <Checkbox
                    checked={selectedEventTypeIds.includes(eventType.id)}
                    onChange={() => handleEventTypeToggle(eventType.id)}
                  />
                  <div
                    className="w-3 h-3 rounded-full"
                    style={{ backgroundColor: eventType.color }}
                  />
                  <span className="text-sm">{eventType.name}</span>
                </label>
              ))}
            </div>
          </div>

          {/* Include Properties */}
          <div className="flex items-center gap-2">
            <Checkbox
              id="include-properties"
              checked={includeProperties}
              onChange={(e) => setIncludeProperties(e.target.checked)}
            />
            <Label htmlFor="include-properties" className="cursor-pointer">
              Include dynamic properties in export
            </Label>
          </div>
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isPending}
          >
            Cancel
          </Button>
          <Button onClick={handleExport} disabled={isPending}>
            {isPending ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Exporting...
              </>
            ) : (
              <>
                <Download className="mr-2 h-4 w-4" />
                Export
              </>
            )}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
