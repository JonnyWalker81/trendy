import { LucideIcon, TrendingUp, TrendingDown, Minus } from 'lucide-react'
import { Card } from '@/components/ui/card'

interface StatisticCardProps {
  title: string
  value: string | number
  icon: LucideIcon
  trend?: 'increasing' | 'decreasing' | 'stable'
  subtitle?: string
}

export function StatisticCard({ title, value, icon: Icon, trend, subtitle }: StatisticCardProps) {
  const getTrendIcon = () => {
    switch (trend) {
      case 'increasing':
        return <TrendingUp className="h-4 w-4 text-green-500" />
      case 'decreasing':
        return <TrendingDown className="h-4 w-4 text-red-500" />
      case 'stable':
        return <Minus className="h-4 w-4 text-muted-foreground" />
      default:
        return null
    }
  }

  return (
    <Card className="p-4">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <div className="flex items-center gap-2 mb-1">
            <Icon className="h-4 w-4 text-muted-foreground" />
            <span className="text-sm font-medium text-muted-foreground">{title}</span>
          </div>
          <div className="flex items-baseline gap-2">
            <span className="text-2xl font-bold">{value}</span>
            {trend && getTrendIcon()}
          </div>
          {subtitle && (
            <span className="text-xs text-muted-foreground mt-1 block">{subtitle}</span>
          )}
        </div>
      </div>
    </Card>
  )
}
