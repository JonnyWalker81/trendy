import {
  Coffee,
  Dumbbell,
  Book,
  Briefcase,
  Heart,
  Music,
  Utensils,
  Plane,
  ShoppingBag,
  Home,
  Users,
  Star,
  Camera,
  Laptop,
  Pill,
  Car,
  Bike,
  Film,
  Gamepad,
  Paintbrush,
  GraduationCap,
  Calendar,
  Phone,
  Mail,
  type LucideIcon,
} from 'lucide-react'
import { cn } from "@/lib/utils"

// 24 commonly used icons for event types (matching iOS app SF Symbols)
export const PRESET_ICONS: { name: string; icon: LucideIcon }[] = [
  { name: 'coffee', icon: Coffee },
  { name: 'dumbbell', icon: Dumbbell },
  { name: 'book', icon: Book },
  { name: 'briefcase', icon: Briefcase },
  { name: 'heart', icon: Heart },
  { name: 'music', icon: Music },
  { name: 'utensils', icon: Utensils },
  { name: 'plane', icon: Plane },
  { name: 'shopping-bag', icon: ShoppingBag },
  { name: 'home', icon: Home },
  { name: 'users', icon: Users },
  { name: 'star', icon: Star },
  { name: 'camera', icon: Camera },
  { name: 'laptop', icon: Laptop },
  { name: 'pill', icon: Pill },
  { name: 'car', icon: Car },
  { name: 'bike', icon: Bike },
  { name: 'film', icon: Film },
  { name: 'gamepad', icon: Gamepad },
  { name: 'paintbrush', icon: Paintbrush },
  { name: 'graduation-cap', icon: GraduationCap },
  { name: 'calendar', icon: Calendar },
  { name: 'phone', icon: Phone },
  { name: 'mail', icon: Mail },
]

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

// Helper to get icon component by name
export function getIconByName(name: string): LucideIcon {
  const iconData = PRESET_ICONS.find((i) => i.name === name)
  return iconData?.icon || Star
}
