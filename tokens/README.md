# Trendy Design System - Color Tokens

This directory contains the single source of truth for the Trendy app's color system, shared across iOS (SwiftUI) and Web (React + Tailwind).

## Quick Start

### Changing Colors

1. Edit `colors.json` in this directory
2. Run the generator: `node tokens/generate.js`
3. Verify accessibility: `node tokens/check-contrast.js`

### Files

| File | Purpose |
|------|---------|
| `colors.json` | Single source of truth - edit this file |
| `generate.js` | Generates platform-specific files |
| `check-contrast.js` | WCAG AA contrast checker |

### Generated Files

Do not edit these directly - they are generated from `colors.json`:

- **Web**: `apps/web/src/styles/tokens.css` (CSS variables)
- **iOS**: `apps/ios/trendy/DesignSystem/Colors.swift` (SwiftUI)

## Color Token Reference

### Core Tokens

| Token | Purpose |
|-------|---------|
| `background` | Main app background |
| `foreground` | Primary text color |
| `card` | Card/elevated surface background |
| `cardForeground` | Text on cards |
| `muted` | Subtle background distinction |
| `mutedForeground` | Secondary/muted text |

### Interactive Tokens

| Token | Purpose |
|-------|---------|
| `primary` | Primary brand color (buttons, focus) |
| `primaryForeground` | Text on primary backgrounds |
| `secondary` | Secondary buttons, less prominent |
| `secondaryForeground` | Text on secondary backgrounds |
| `accent` | Highlights, hover states |
| `accentForeground` | Text on accent backgrounds |

### Semantic Tokens

| Token | Purpose |
|-------|---------|
| `destructive` | Danger/error states, destructive actions |
| `destructiveForeground` | Text on destructive backgrounds |
| `success` | Success states, confirmations |
| `successForeground` | Text on success backgrounds |
| `warning` | Warning states, cautions |
| `warningForeground` | Text on warning backgrounds |
| `link` | Distinct link text color |

### Utility Tokens

| Token | Purpose |
|-------|---------|
| `border` | Default border color |
| `input` | Input field borders |
| `ring` | Focus ring color |
| `chart1-5` | Chart/data visualization colors |

## Usage

### Web (React + Tailwind)

```tsx
// Using Tailwind classes
<button className="bg-primary text-primary-foreground">
  Primary Button
</button>

<button className="bg-destructive text-destructive-foreground">
  Delete
</button>

<span className="text-muted-foreground">
  Secondary text
</span>

<a href="#" className="text-link hover:text-link/80">
  Click here
</a>
```

### iOS (SwiftUI)

```swift
// Using Color extensions
Button("Primary") { }
    .buttonStyle(.borderedProminent)
    .tint(.dsPrimary)

Text("Error message")
    .foregroundStyle(.dsDestructive)

Text("Secondary text")
    .foregroundStyle(.dsMutedForeground)

Link("Click here", destination: url)
    .foregroundStyle(.dsLink)
```

## Modifying Colors

### Step 1: Edit colors.json

Each color has light and dark mode values:

```json
{
  "primary": {
    "description": "Primary brand color",
    "light": "#2563EB",
    "dark": "#60A5FA"
  }
}
```

### Step 2: Regenerate

```bash
node tokens/generate.js
```

This updates:
- `apps/web/src/styles/tokens.css`
- `apps/ios/trendy/DesignSystem/Colors.swift`

### Step 3: Verify Accessibility

```bash
node tokens/check-contrast.js
```

This checks that all text/background combinations meet WCAG AA (4.5:1 contrast ratio).

If any checks fail, adjust the colors and re-run.

## Accessibility Requirements

All color combinations must meet WCAG AA contrast ratios:

- **Normal text**: 4.5:1 minimum
- **Large text (18pt+)**: 3:1 minimum

The `contrastPairs` array in `colors.json` defines which combinations are checked:

```json
{
  "contrastPairs": [
    { "foreground": "foreground", "background": "background", "minRatio": 4.5 },
    { "foreground": "primaryForeground", "background": "primary", "minRatio": 4.5 }
  ]
}
```

## Design Principles

1. **Semantic naming**: Use tokens by purpose, not by color (e.g., `destructive` not `red`)
2. **Contrast first**: All text combinations meet WCAG AA
3. **Mode-agnostic**: Light/dark values defined together
4. **Single source**: Edit only `colors.json`, never generated files

## Troubleshooting

### Colors not updating on web
1. Make sure you ran `node tokens/generate.js`
2. Restart the dev server (`just dev-web`)

### Colors not updating on iOS
1. Make sure you ran `node tokens/generate.js`
2. Clean build in Xcode (Cmd+Shift+K)
3. Rebuild the project

### Contrast check fails
Adjust the failing color pair in `colors.json`. Use a tool like [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) to find compliant values.

### Adding a new token
1. Add to `colors.json` with `light` and `dark` values
2. Run `node tokens/generate.js`
3. Add to `tailwind.config.js` if needed for web
4. Add any contrast pairs to `contrastPairs` array
