import {
  LineChart,
  Line,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  ComposedChart,
} from 'recharts'
import { format, parseISO } from 'date-fns'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import type { TimeSeriesDataPoint } from '@/types'

interface FrequencyChartProps {
  data: TimeSeriesDataPoint[]
  color: string
  timeRange: 'week' | 'month' | 'year'
}

export function FrequencyChart({ data, color, timeRange }: FrequencyChartProps) {
  const formatXAxis = (dateStr: string) => {
    const date = parseISO(dateStr)
    switch (timeRange) {
      case 'week':
        return format(date, 'EEE') // Mon, Tue, Wed
      case 'month':
        return format(date, 'MMM d') // Jan 1, Jan 8
      case 'year':
        return format(date, 'MMM') // Jan, Feb, Mar
      default:
        return format(date, 'MMM d')
    }
  }

  // Convert hex color to RGB for opacity
  const hexToRgb = (hex: string) => {
    const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex)
    return result
      ? {
          r: parseInt(result[1], 16),
          g: parseInt(result[2], 16),
          b: parseInt(result[3], 16),
        }
      : { r: 59, g: 130, b: 246 } // Fallback to blue
  }

  const rgb = hexToRgb(color)
  const fillColor = `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, 0.2)`

  if (data.length === 0) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>Frequency Over Time</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="h-64 flex items-center justify-center text-muted-foreground">
            <div className="text-center">
              <p className="text-sm">No data available for this time range</p>
            </div>
          </div>
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Frequency Over Time</CardTitle>
      </CardHeader>
      <CardContent>
        <ResponsiveContainer width="100%" height={250}>
          <ComposedChart data={data} margin={{ top: 5, right: 20, left: 0, bottom: 5 }}>
            <defs>
              <linearGradient id="colorCount" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor={color} stopOpacity={0.3} />
                <stop offset="95%" stopColor={color} stopOpacity={0.05} />
              </linearGradient>
            </defs>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" />
            <XAxis
              dataKey="date"
              tickFormatter={formatXAxis}
              stroke="hsl(var(--muted-foreground))"
              style={{ fontSize: '12px' }}
            />
            <YAxis
              stroke="hsl(var(--muted-foreground))"
              style={{ fontSize: '12px' }}
              allowDecimals={false}
            />
            <Tooltip
              contentStyle={{
                backgroundColor: 'hsl(var(--popover))',
                border: '1px solid hsl(var(--border))',
                borderRadius: '8px',
                color: 'hsl(var(--popover-foreground))',
              }}
              labelFormatter={(value) => format(parseISO(value as string), 'PPP')}
              formatter={(value: number) => [value, 'Events']}
            />
            <Area
              type="monotone"
              dataKey="count"
              stroke="none"
              fill="url(#colorCount)"
            />
            <Line
              type="monotone"
              dataKey="count"
              stroke={color}
              strokeWidth={2}
              dot={{ fill: color, r: 4 }}
              activeDot={{ r: 6 }}
            />
          </ComposedChart>
        </ResponsiveContainer>
      </CardContent>
    </Card>
  )
}
