import { cn } from "@/lib/utils"
import { PRESET_ICONS } from "./icon-constants"

interface IconPickerProps {
  value: string
  onChange: (iconName: string) => void
  className?: string
}

export function IconPicker({ value, onChange, className }: IconPickerProps) {
  return (
    <div className={cn("grid grid-cols-6 gap-2", className)}>
      {PRESET_ICONS.map(({ name, icon: Icon }) => (
        <button
          key={name}
          type="button"
          onClick={() => onChange(name)}
          className={cn(
            "flex h-12 w-12 items-center justify-center rounded-md border-2 transition-all hover:scale-110 hover:bg-accent",
            value === name
              ? "border-primary bg-accent ring-2 ring-primary ring-offset-2"
              : "border-transparent bg-background"
          )}
          title={name}
          aria-label={`Select ${name} icon`}
        >
          <Icon className="h-5 w-5" />
        </button>
      ))}
    </div>
  )
}

