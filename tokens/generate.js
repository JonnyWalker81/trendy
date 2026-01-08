#!/usr/bin/env node
/**
 * Token Generator for Trendy Design System
 *
 * Generates platform-specific color definitions from tokens/colors.json:
 * - Web: apps/web/src/styles/tokens.css (CSS variables)
 * - iOS: apps/ios/trendy/DesignSystem/Colors.swift (SwiftUI)
 *
 * Run: node tokens/generate.js
 */

const fs = require('fs');
const path = require('path');

// Load tokens
const tokensPath = path.join(__dirname, 'colors.json');
const tokens = JSON.parse(fs.readFileSync(tokensPath, 'utf8'));
const { colors } = tokens;

/**
 * Convert hex to HSL string for CSS
 */
function hexToHsl(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) throw new Error(`Invalid hex color: ${hex}`);

  let r = parseInt(result[1], 16) / 255;
  let g = parseInt(result[2], 16) / 255;
  let b = parseInt(result[3], 16) / 255;

  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  let h, s, l = (max + min) / 2;

  if (max === min) {
    h = s = 0;
  } else {
    const d = max - min;
    s = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    switch (max) {
      case r: h = ((g - b) / d + (g < b ? 6 : 0)) / 6; break;
      case g: h = ((b - r) / d + 2) / 6; break;
      case b: h = ((r - g) / d + 4) / 6; break;
    }
  }

  return `${Math.round(h * 360)} ${Math.round(s * 100)}% ${Math.round(l * 100)}%`;
}

/**
 * Convert camelCase to kebab-case
 */
function toKebabCase(str) {
  return str.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
}

/**
 * Convert camelCase to PascalCase
 */
function toPascalCase(str) {
  return str.charAt(0).toUpperCase() + str.slice(1);
}

// ============================================
// Generate CSS tokens for web
// ============================================
function generateWebTokens() {
  let css = `/**
 * Trendy Design System - Color Tokens
 * Generated from tokens/colors.json
 * DO NOT EDIT DIRECTLY - Run: node tokens/generate.js
 */

:root {
`;

  // Dark mode by default (matches current setup)
  for (const [name, value] of Object.entries(colors)) {
    const cssName = toKebabCase(name);
    css += `  --${cssName}: ${hexToHsl(value.dark)};\n`;
  }

  css += `  --radius: 0.5rem;
}

.light {
`;

  for (const [name, value] of Object.entries(colors)) {
    const cssName = toKebabCase(name);
    css += `  --${cssName}: ${hexToHsl(value.light)};\n`;
  }

  css += `}

@media (prefers-color-scheme: light) {
  :root:not(.dark) {
`;

  for (const [name, value] of Object.entries(colors)) {
    const cssName = toKebabCase(name);
    css += `    --${cssName}: ${hexToHsl(value.light)};\n`;
  }

  css += `  }
}
`;

  return css;
}

// ============================================
// Generate Swift colors for iOS
// ============================================
function generateSwiftColors() {
  let swift = `//
//  Colors.swift
//  trendy
//
//  Design System Color Tokens
//  Generated from tokens/colors.json
//  DO NOT EDIT DIRECTLY - Run: node tokens/generate.js
//

import SwiftUI
import UIKit

/// Semantic color tokens for the Trendy design system
/// These colors automatically adapt to light/dark mode
extension Color {
`;

  for (const [name, value] of Object.entries(colors)) {
    const swiftName = name;
    const lightHex = value.light;
    const darkHex = value.dark;

    swift += `    /// ${value.description}
    static let ds${toPascalCase(name)} = Color(light: "${lightHex}", dark: "${darkHex}")

`;
  }

  swift += `}

// MARK: - Color Initializer with Light/Dark Support

extension Color {
    /// Creates a color that adapts to light/dark mode
    init(light: String, dark: String) {
        self.init(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(hex: dark) ?? .clear
                : UIColor(hex: light) ?? .clear
        })
    }
}

// MARK: - UIColor Hex Initializer

extension UIColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let red = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let green = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let blue = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}
`;

  return swift;
}

// ============================================
// Write files
// ============================================
const webTokensPath = path.join(__dirname, '..', 'apps', 'web', 'src', 'styles', 'tokens.css');
const iosColorsPath = path.join(__dirname, '..', 'apps', 'ios', 'trendy', 'DesignSystem', 'Colors.swift');

// Ensure directories exist
fs.mkdirSync(path.dirname(webTokensPath), { recursive: true });
fs.mkdirSync(path.dirname(iosColorsPath), { recursive: true });

// Generate and write files
const webTokens = generateWebTokens();
const swiftColors = generateSwiftColors();

fs.writeFileSync(webTokensPath, webTokens);
fs.writeFileSync(iosColorsPath, swiftColors);

console.log('Generated:');
console.log(`  - ${webTokensPath}`);
console.log(`  - ${iosColorsPath}`);
console.log('\nDone!');
