interface TimeRangePickerProps {
  value: 'week' | 'month' | 'year'
  onChange: (value: 'week' | 'month' | 'year') => void
}

export function TimeRangePicker({ value, onChange }: TimeRangePickerProps) {
  const options: Array<{ value: 'week' | 'month' | 'year'; label: string }> = [
    { value: 'week', label: 'Week' },
    { value: 'month', label: 'Month' },
    { value: 'year', label: 'Year' },
  ]

  return (
    <div className="inline-flex rounded-lg bg-muted p-1 gap-1">
      {options.map((option) => (
        <button
          key={option.value}
          onClick={() => onChange(option.value)}
          className={`px-4 py-2 text-sm font-medium rounded-md transition-all ${
            value === option.value
              ? 'bg-primary text-primary-foreground shadow-sm'
              : 'text-muted-foreground hover:text-foreground'
          }`}
        >
          {option.label}
        </button>
      ))}
    </div>
  )
}
