---
created: 2026-01-19T17:21
title: Move sync widget above tab bar
area: ui
files:
  - apps/ios/trendy/Views/Components/SyncIndicator/SyncIndicatorView.swift
  - apps/ios/trendy/Views/MainTabView.swift
---

## Problem

The floating sync indicator widget is currently positioned at the bottom of the screen, covering the tab bar. This obscures the tabs and makes navigation harder when the sync indicator is visible.

## Solution

Reposition the sync indicator to sit just above the tab bar instead of at the very bottom of the screen. Maintain the passthrough behavior so taps on the indicator area still reach the content below it (allowsHitTesting(false) or similar).

Key changes:
- Adjust the overlay/ZStack positioning in MainTabView.swift or SyncIndicatorView.swift
- Use safe area insets or tab bar height calculation to position correctly above tabs
- Ensure passthrough tap behavior is preserved
