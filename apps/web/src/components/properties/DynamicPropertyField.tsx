import { PropertyDefinition, PropertyValue } from '@/types'

interface DynamicPropertyFieldProps {
  definition: PropertyDefinition
  value?: PropertyValue
  onChange: (value: PropertyValue) => void
  onRemove?: () => void
}

export function DynamicPropertyField({
  definition,
  value,
  onChange,
  onRemove,
}: DynamicPropertyFieldProps) {
  const handleChange = (newValue: string | number | boolean | Date) => {
    onChange({
      type: definition.property_type,
      value: newValue,
    })
  }

  const renderInput = () => {
    const inputValue = value?.value ?? definition.default_value ?? ''

    switch (definition.property_type) {
      case 'text':
        return (
          <input
            type="text"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={inputValue as string}
            onChange={(e) => handleChange(e.target.value)}
            placeholder={definition.label}
          />
        )

      case 'number':
        return (
          <input
            type="number"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={inputValue as number}
            onChange={(e) => handleChange(parseFloat(e.target.value) || 0)}
            placeholder={definition.label}
          />
        )

      case 'boolean':
        return (
          <div className="mt-2">
            <label className="inline-flex items-center">
              <input
                type="checkbox"
                className="rounded border-input text-blue-600 shadow-sm focus:border-blue-500 focus:ring-blue-500"
                checked={inputValue as boolean}
                onChange={(e) => handleChange(e.target.checked)}
              />
              <span className="ml-2 text-sm text-muted-foreground">
                {definition.label}
              </span>
            </label>
          </div>
        )

      case 'date':
        return (
          <input
            type="date"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={
              inputValue instanceof Date
                ? inputValue.toISOString().split('T')[0]
                : inputValue && typeof inputValue !== 'boolean'
                ? new Date(inputValue).toISOString().split('T')[0]
                : ''
            }
            onChange={(e) => handleChange(new Date(e.target.value))}
          />
        )

      case 'select':
        return (
          <select
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={inputValue as string}
            onChange={(e) => handleChange(e.target.value)}
          >
            <option value="">Select {definition.label}</option>
            {definition.options?.map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        )

      case 'duration': {
        // Duration in seconds, display as HH:MM:SS
        const seconds = (inputValue as number) || 0
        const hours = Math.floor(seconds / 3600)
        const minutes = Math.floor((seconds % 3600) / 60)
        const secs = seconds % 60

        return (
          <input
            type="time"
            step="1"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={`${String(hours).padStart(2, '0')}:${String(minutes).padStart(2, '0')}:${String(secs).padStart(2, '0')}`}
            onChange={(e) => {
              const [h, m, s] = e.target.value.split(':').map(Number)
              handleChange(h * 3600 + m * 60 + (s || 0))
            }}
          />
        )
      }

      case 'url':
        return (
          <input
            type="url"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={inputValue as string}
            onChange={(e) => handleChange(e.target.value)}
            placeholder={`https://example.com`}
          />
        )

      case 'email':
        return (
          <input
            type="email"
            className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
            value={inputValue as string}
            onChange={(e) => handleChange(e.target.value)}
            placeholder={`email@example.com`}
          />
        )

      default:
        return null
    }
  }

  return (
    <div className="space-y-1">
      {definition.property_type !== 'boolean' && (
        <div className="flex items-center justify-between">
          <label className="block text-sm font-medium text-foreground">
            {definition.label}
          </label>
          {onRemove && (
            <button
              type="button"
              onClick={onRemove}
              className="text-sm text-red-600 hover:text-red-800"
            >
              Remove
            </button>
          )}
        </div>
      )}
      {renderInput()}
      {onRemove && definition.property_type === 'boolean' && (
        <button
          type="button"
          onClick={onRemove}
          className="mt-1 text-sm text-red-600 hover:text-red-800"
        >
          Remove
        </button>
      )}
    </div>
  )
}
