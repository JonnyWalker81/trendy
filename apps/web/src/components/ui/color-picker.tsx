import { cn } from "@/lib/utils"
import { PRESET_COLORS } from "./color-constants"

interface ColorPickerProps {
  value: string
  onChange: (color: string) => void
  className?: string
}

export function ColorPicker({ value, onChange, className }: ColorPickerProps) {
  return (
    <div className={cn("grid grid-cols-6 gap-2", className)}>
      {PRESET_COLORS.map((color) => (
        <button
          key={color.value}
          type="button"
          onClick={() => onChange(color.value)}
          className={cn(
            "h-10 w-10 rounded-md border-2 transition-all hover:scale-110",
            value === color.value
              ? "border-primary ring-2 ring-primary ring-offset-2"
              : "border-transparent"
          )}
          style={{ backgroundColor: color.value }}
          title={color.name}
          aria-label={`Select ${color.name} color`}
        />
      ))}
    </div>
  )
}
