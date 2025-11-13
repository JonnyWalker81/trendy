import { useState } from 'react'
import { PropertyType } from '@/types'
import {
  usePropertyDefinitions,
  useCreatePropertyDefinition,
  useDeletePropertyDefinition,
} from '@/hooks/api/usePropertyDefinitions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select } from '@/components/ui/select'

interface PropertyDefinitionManagerProps {
  eventTypeId: string
}

export function PropertyDefinitionManager({
  eventTypeId,
}: PropertyDefinitionManagerProps) {
  const { data: propertyDefs = [], isLoading } =
    usePropertyDefinitions(eventTypeId)
  const createMutation = useCreatePropertyDefinition()
  const deleteMutation = useDeletePropertyDefinition()

  const [showAddForm, setShowAddForm] = useState(false)
  const [newKey, setNewKey] = useState('')
  const [newLabel, setNewLabel] = useState('')
  const [newType, setNewType] = useState<PropertyType>('text')
  const [newOptions, setNewOptions] = useState('')

  const handleAdd = async () => {
    if (!newKey || !newLabel) return

    await createMutation.mutateAsync({
      eventTypeId,
      data: {
        key: newKey,
        label: newLabel,
        property_type: newType,
        options: newType === 'select' ? newOptions.split(',').map((s) => s.trim()).filter(Boolean) : undefined,
        display_order: propertyDefs.length,
      },
    })

    setShowAddForm(false)
    setNewKey('')
    setNewLabel('')
    setNewType('text')
    setNewOptions('')
  }

  const handleDelete = async (id: string) => {
    if (!confirm('Are you sure you want to delete this property?')) return
    await deleteMutation.mutateAsync({ id, eventTypeId })
  }

  if (isLoading) {
    return <div className="text-sm text-muted-foreground">Loading properties...</div>
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h3 className="text-lg font-medium">Property Definitions</h3>
        {!showAddForm && (
          <Button
            onClick={() => setShowAddForm(true)}
            variant="outline"
            size="sm"
          >
            + Add Property
          </Button>
        )}
      </div>

      {/* Property List */}
      {propertyDefs.length > 0 ? (
        <div className="space-y-2">
          {propertyDefs.map((def) => (
            <div
              key={def.id}
              className="flex items-center justify-between rounded-lg border border-border bg-card p-3"
            >
              <div>
                <div className="font-medium text-foreground">{def.label}</div>
                <div className="text-sm text-muted-foreground">
                  {def.key} • {def.property_type}
                  {def.property_type === 'select' &&
                    def.options &&
                    ` • ${def.options.join(', ')}`}
                </div>
              </div>
              <Button
                onClick={() => handleDelete(def.id)}
                variant="ghost"
                size="sm"
                className="text-red-600 hover:text-red-800"
              >
                Delete
              </Button>
            </div>
          ))}
        </div>
      ) : (
        <p className="text-sm text-muted-foreground">
          No properties defined. Add properties that users can fill when
          creating events of this type.
        </p>
      )}

      {/* Add Form */}
      {showAddForm && (
        <div className="rounded-lg border border-border bg-muted p-4 space-y-3">
          <h4 className="text-sm font-medium">Add Property Definition</h4>

          <div>
            <Label htmlFor="prop-key">Key</Label>
            <Input
              id="prop-key"
              value={newKey}
              onChange={(e) =>
                setNewKey(e.target.value.replace(/\s+/g, '_').toLowerCase())
              }
              placeholder="property_key"
            />
            <p className="mt-1 text-xs text-muted-foreground">
              Unique identifier (no spaces, lowercase)
            </p>
          </div>

          <div>
            <Label htmlFor="prop-label">Label</Label>
            <Input
              id="prop-label"
              value={newLabel}
              onChange={(e) => setNewLabel(e.target.value)}
              placeholder="Property Name"
            />
          </div>

          <div>
            <Label htmlFor="prop-type">Type</Label>
            <Select
              id="prop-type"
              value={newType}
              onChange={(e) => setNewType(e.target.value as PropertyType)}
            >
              <option value="text">Text</option>
              <option value="number">Number</option>
              <option value="boolean">Boolean</option>
              <option value="date">Date</option>
              <option value="select">Select (Dropdown)</option>
              <option value="duration">Duration</option>
              <option value="url">URL</option>
              <option value="email">Email</option>
            </Select>
          </div>

          {newType === 'select' && (
            <div>
              <Label htmlFor="prop-options">Options</Label>
              <Input
                id="prop-options"
                value={newOptions}
                onChange={(e) => setNewOptions(e.target.value)}
                placeholder="Option 1, Option 2, Option 3"
              />
              <p className="mt-1 text-xs text-muted-foreground">
                Comma-separated list of options
              </p>
            </div>
          )}

          <div className="flex space-x-2">
            <Button
              onClick={handleAdd}
              disabled={!newKey || !newLabel || createMutation.isPending}
            >
              {createMutation.isPending ? 'Adding...' : 'Add Property'}
            </Button>
            <Button
              variant="outline"
              onClick={() => {
                setShowAddForm(false)
                setNewKey('')
                setNewLabel('')
                setNewType('text')
                setNewOptions('')
              }}
            >
              Cancel
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
