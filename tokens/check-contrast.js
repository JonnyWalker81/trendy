#!/usr/bin/env node
/**
 * WCAG Contrast Ratio Checker for Trendy Design System
 *
 * Validates that color pairs in tokens/colors.json meet WCAG AA standards.
 * Run: node tokens/check-contrast.js
 */

const fs = require('fs');
const path = require('path');

// Load tokens
const tokensPath = path.join(__dirname, 'colors.json');
const tokens = JSON.parse(fs.readFileSync(tokensPath, 'utf8'));

/**
 * Parse hex color to RGB values
 */
function hexToRgb(hex) {
  const result = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (!result) throw new Error(`Invalid hex color: ${hex}`);
  return {
    r: parseInt(result[1], 16),
    g: parseInt(result[2], 16),
    b: parseInt(result[3], 16)
  };
}

/**
 * Calculate relative luminance per WCAG 2.1
 * https://www.w3.org/WAI/GL/wiki/Relative_luminance
 */
function getRelativeLuminance(rgb) {
  const [rs, gs, bs] = [rgb.r, rgb.g, rgb.b].map(c => {
    const s = c / 255;
    return s <= 0.03928 ? s / 12.92 : Math.pow((s + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * rs + 0.7152 * gs + 0.0722 * bs;
}

/**
 * Calculate contrast ratio between two colors
 * https://www.w3.org/WAI/GL/wiki/Contrast_ratio
 */
function getContrastRatio(hex1, hex2) {
  const l1 = getRelativeLuminance(hexToRgb(hex1));
  const l2 = getRelativeLuminance(hexToRgb(hex2));
  const lighter = Math.max(l1, l2);
  const darker = Math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/**
 * Format contrast ratio for display
 */
function formatRatio(ratio) {
  return ratio.toFixed(2) + ':1';
}

/**
 * Check if ratio meets WCAG AA requirements
 */
function meetsWcagAA(ratio, isLargeText = false) {
  return isLargeText ? ratio >= 3.0 : ratio >= 4.5;
}

// Run contrast checks
console.log('\n=== Trendy Color System - WCAG AA Contrast Check ===\n');

const { colors, contrastPairs } = tokens;
let allPassed = true;
const results = [];

for (const pair of contrastPairs) {
  const fgColor = colors[pair.foreground];
  const bgColor = colors[pair.background];

  if (!fgColor || !bgColor) {
    console.error(`Missing color definition: ${pair.foreground} or ${pair.background}`);
    continue;
  }

  // Check both light and dark modes
  for (const mode of ['light', 'dark']) {
    const fg = fgColor[mode];
    const bg = bgColor[mode];
    const ratio = getContrastRatio(fg, bg);
    const passed = ratio >= pair.minRatio;

    if (!passed) allPassed = false;

    results.push({
      pair: `${pair.foreground} on ${pair.background}`,
      mode,
      fg,
      bg,
      ratio: formatRatio(ratio),
      required: `${pair.minRatio}:1`,
      passed
    });
  }
}

// Display results
const maxPairLen = Math.max(...results.map(r => r.pair.length));
const maxModeLen = 5;

for (const r of results) {
  const status = r.passed ? '\x1b[32mPASS\x1b[0m' : '\x1b[31mFAIL\x1b[0m';
  const pairPadded = r.pair.padEnd(maxPairLen);
  const modePadded = r.mode.padEnd(maxModeLen);
  console.log(`[${status}] ${pairPadded} | ${modePadded} | ${r.ratio.padStart(7)} (min: ${r.required})`);
}

// Summary
console.log('\n' + '='.repeat(70));
const passCount = results.filter(r => r.passed).length;
const totalCount = results.length;
console.log(`Results: ${passCount}/${totalCount} pairs passed WCAG AA\n`);

if (!allPassed) {
  console.log('\x1b[31mSome color combinations do not meet WCAG AA requirements.\x1b[0m');
  console.log('Please adjust the colors in tokens/colors.json\n');
  process.exit(1);
} else {
  console.log('\x1b[32mAll color combinations meet WCAG AA requirements!\x1b[0m\n');
  process.exit(0);
}
