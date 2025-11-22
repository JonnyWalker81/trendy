import { format as formatDate } from 'date-fns'
import type { Event, PropertyValue } from '../types'

export type ExportFormat = 'csv' | 'json'

/**
 * Format a property value for export based on its type
 */
function formatPropertyValue(propValue: PropertyValue): string {
  const { type, value } = propValue

  if (value === null || value === undefined) {
    return ''
  }

  switch (type) {
    case 'date':
      return value instanceof Date
        ? formatDate(value, 'yyyy-MM-dd')
        : typeof value === 'string'
        ? value
        : String(value)
    case 'boolean':
      return value ? 'true' : 'false'
    case 'duration':
      // Assume duration is stored as minutes
      return `${value} min`
    default:
      return String(value)
  }
}

/**
 * Extract all unique property keys from events
 */
function extractPropertyKeys(events: Event[]): string[] {
  const keysSet = new Set<string>()
  events.forEach((event) => {
    if (event.properties) {
      Object.keys(event.properties).forEach((key) => keysSet.add(key))
    }
  })
  return Array.from(keysSet).sort()
}

/**
 * Escape CSV value (handle commas, quotes, newlines)
 */
function escapeCsvValue(value: string | undefined | null): string {
  if (value === null || value === undefined) {
    return ''
  }

  const stringValue = String(value)

  // If the value contains comma, quote, or newline, wrap in quotes and escape quotes
  if (
    stringValue.includes(',') ||
    stringValue.includes('"') ||
    stringValue.includes('\n')
  ) {
    return `"${stringValue.replace(/"/g, '""')}"`
  }

  return stringValue
}

/**
 * Format ISO timestamp to local date/time string
 */
function formatTimestampToLocal(isoString: string): string {
  const date = new Date(isoString)
  return formatDate(date, 'yyyy-MM-dd h:mm a')
}

/**
 * Export events to CSV format with flattened properties
 */
export function exportToCSV(events: Event[], includeProperties = true): string {
  if (events.length === 0) {
    return 'No events to export'
  }

  // Extract property keys if including properties
  const propertyKeys = includeProperties ? extractPropertyKeys(events) : []

  // Build CSV header
  const headers = [
    'Event Type',
    'Timestamp',
    'All Day',
    'End Date',
    'Notes',
    'Source',
    'Original Title',
    ...propertyKeys.map((key) => `Property: ${key}`),
    'Created At',
    'Updated At',
  ]

  const csvRows: string[] = []
  csvRows.push(headers.map(escapeCsvValue).join(','))

  // Build CSV rows
  events.forEach((event) => {
    const row = [
      event.event_type?.name || '',
      formatTimestampToLocal(event.timestamp),
      event.is_all_day ? 'true' : 'false',
      event.end_date ? formatTimestampToLocal(event.end_date) : '',
      event.notes || '',
      event.source_type,
      event.original_title || '',
    ]

    // Add property values in the same order as headers
    if (includeProperties) {
      propertyKeys.forEach((key) => {
        const propValue = event.properties?.[key]
        row.push(propValue ? formatPropertyValue(propValue) : '')
      })
    }

    row.push(formatTimestampToLocal(event.created_at), formatTimestampToLocal(event.updated_at))

    csvRows.push(row.map(escapeCsvValue).join(','))
  })

  return csvRows.join('\n')
}

/**
 * Export events to JSON format
 */
export function exportToJSON(events: Event[]): string {
  // Create a clean export format
  const exportData = events.map((event) => ({
    id: event.id,
    event_type: {
      id: event.event_type_id,
      name: event.event_type?.name || '',
      color: event.event_type?.color || '',
      icon: event.event_type?.icon || '',
    },
    timestamp: event.timestamp,
    is_all_day: event.is_all_day,
    end_date: event.end_date,
    notes: event.notes,
    source_type: event.source_type,
    external_id: event.external_id,
    original_title: event.original_title,
    properties: event.properties,
    created_at: event.created_at,
    updated_at: event.updated_at,
  }))

  return JSON.stringify(exportData, null, 2)
}

/**
 * Generate a filename with timestamp
 */
export function generateFilename(format: ExportFormat): string {
  const timestamp = formatDate(new Date(), 'yyyy-MM-dd-HHmmss')
  const extension = format === 'csv' ? 'csv' : 'json'
  return `trendy-events-${timestamp}.${extension}`
}

/**
 * Trigger browser download of file
 */
export function downloadFile(
  content: string,
  filename: string,
  mimeType: string
): void {
  const blob = new Blob([content], { type: mimeType })
  const url = URL.createObjectURL(blob)

  const link = document.createElement('a')
  link.href = url
  link.download = filename
  link.style.display = 'none'

  document.body.appendChild(link)
  link.click()

  // Cleanup
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

/**
 * Main export function - handles the full export process
 */
export function exportEvents(
  events: Event[],
  format: ExportFormat,
  includeProperties = true
): void {
  const content =
    format === 'csv'
      ? exportToCSV(events, includeProperties)
      : exportToJSON(events)

  const mimeType = format === 'csv' ? 'text/csv;charset=utf-8;' : 'application/json'
  const filename = generateFilename(format)

  downloadFile(content, filename, mimeType)
}
