import { useState } from 'react'
import { PropertyValue, PropertyType } from '@/types'
import { usePropertyDefinitions } from '@/hooks/api/usePropertyDefinitions'
import { DynamicPropertyField } from './DynamicPropertyField'

interface DynamicPropertyFieldsProps {
  eventTypeId: string
  properties: Record<string, PropertyValue>
  onChange: (properties: Record<string, PropertyValue>) => void
}

interface CustomProperty {
  key: string
  label: string
  type: PropertyType
}

export function DynamicPropertyFields({
  eventTypeId,
  properties,
  onChange,
}: DynamicPropertyFieldsProps) {
  const { data: propertyDefinitions = [], isLoading } =
    usePropertyDefinitions(eventTypeId)
  const [customProperties, setCustomProperties] = useState<CustomProperty[]>([])
  const [showAddForm, setShowAddForm] = useState(false)
  const [newPropertyKey, setNewPropertyKey] = useState('')
  const [newPropertyLabel, setNewPropertyLabel] = useState('')
  const [newPropertyType, setNewPropertyType] = useState<PropertyType>('text')

  const handlePropertyChange = (key: string, value: PropertyValue) => {
    onChange({
      ...properties,
      [key]: value,
    })
  }

  const handleRemoveCustomProperty = (key: string) => {
    const newProps = { ...properties }
    delete newProps[key]
    onChange(newProps)
    setCustomProperties(customProperties.filter((p) => p.key !== key))
  }

  const handleAddCustomProperty = () => {
    if (!newPropertyKey || !newPropertyLabel) return

    const customProp: CustomProperty = {
      key: newPropertyKey,
      label: newPropertyLabel,
      type: newPropertyType,
    }

    setCustomProperties([...customProperties, customProp])
    setShowAddForm(false)
    setNewPropertyKey('')
    setNewPropertyLabel('')
    setNewPropertyType('text')
  }

  if (isLoading) {
    return <div className="text-sm text-muted-foreground">Loading properties...</div>
  }

  const hasAnyProperties =
    propertyDefinitions.length > 0 || customProperties.length > 0

  return (
    <div className="space-y-4">
      {/* Event Type Schema Properties */}
      {propertyDefinitions.length > 0 && (
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-foreground">
            Event Type Properties
          </h4>
          {propertyDefinitions.map((def) => (
            <DynamicPropertyField
              key={def.id}
              definition={def}
              value={properties[def.key]}
              onChange={(value) => handlePropertyChange(def.key, value)}
            />
          ))}
        </div>
      )}

      {/* Custom (Ad-hoc) Properties */}
      {customProperties.length > 0 && (
        <div className="space-y-3">
          <h4 className="text-sm font-medium text-foreground">
            Custom Properties
          </h4>
          {customProperties.map((customProp) => (
            <DynamicPropertyField
              key={customProp.key}
              definition={{
                id: customProp.key,
                event_type_id: eventTypeId,
                user_id: '',
                key: customProp.key,
                label: customProp.label,
                property_type: customProp.type,
                display_order: 0,
                created_at: '',
                updated_at: '',
              }}
              value={properties[customProp.key]}
              onChange={(value) => handlePropertyChange(customProp.key, value)}
              onRemove={() => handleRemoveCustomProperty(customProp.key)}
            />
          ))}
        </div>
      )}

      {/* Add Custom Property Button/Form */}
      {!showAddForm ? (
        <button
          type="button"
          onClick={() => setShowAddForm(true)}
          className="flex items-center text-sm text-blue-600 hover:text-blue-800"
        >
          <span className="mr-1">+</span> Add Custom Property
        </button>
      ) : (
        <div className="rounded-lg border border-border bg-muted p-4 space-y-3">
          <h4 className="text-sm font-medium text-foreground">
            Add Custom Property
          </h4>

          <div>
            <label className="block text-sm font-medium text-foreground">
              Key
            </label>
            <input
              type="text"
              className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
              value={newPropertyKey}
              onChange={(e) =>
                setNewPropertyKey(e.target.value.replace(/\s+/g, '_'))
              }
              placeholder="property_name"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-foreground">
              Label
            </label>
            <input
              type="text"
              className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
              value={newPropertyLabel}
              onChange={(e) => setNewPropertyLabel(e.target.value)}
              placeholder="Property Name"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-foreground">
              Type
            </label>
            <select
              className="mt-1 block w-full rounded-md border border-input bg-background text-foreground px-3 py-2 shadow-sm focus:border-blue-500 focus:outline-none focus:ring-1 focus:ring-blue-500"
              value={newPropertyType}
              onChange={(e) => setNewPropertyType(e.target.value as PropertyType)}
            >
              <option value="text">Text</option>
              <option value="number">Number</option>
              <option value="boolean">Boolean</option>
              <option value="date">Date</option>
              <option value="duration">Duration</option>
              <option value="url">URL</option>
              <option value="email">Email</option>
            </select>
          </div>

          <div className="flex space-x-2">
            <button
              type="button"
              onClick={handleAddCustomProperty}
              className="rounded-md bg-blue-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-blue-500"
              disabled={!newPropertyKey || !newPropertyLabel}
            >
              Add Property
            </button>
            <button
              type="button"
              onClick={() => {
                setShowAddForm(false)
                setNewPropertyKey('')
                setNewPropertyLabel('')
                setNewPropertyType('text')
              }}
              className="rounded-md bg-background px-3 py-2 text-sm font-semibold text-foreground shadow-sm ring-1 ring-inset ring-border hover:bg-muted"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      {!hasAnyProperties && !showAddForm && (
        <p className="text-sm text-muted-foreground">
          No properties defined. Add custom properties using the button above.
        </p>
      )}
    </div>
  )
}
