---
created: 2026-01-26T00:00
title: Add iOS file logging with device retrieval
area: ios
files:
  - apps/ios/trendy/Utilities/Logger.swift
---

## Problem

Currently iOS logs use Apple's unified logging (os.Logger) which is great for real-time debugging via Console.app but has limitations:
- Logs are difficult to retrieve from user devices when debugging production issues
- Users can't easily share logs when reporting bugs
- No persistent log files that survive app restarts for post-mortem analysis
- Remote debugging of user-reported issues is challenging

Need a way to:
1. Persist logs to files on device storage
2. Provide an easy mechanism for users/testers to export logs (share sheet, email, etc.)
3. Manage log file rotation to prevent unbounded storage growth

## Solution

TBD — Consider:
- Add file logging destination alongside os.Logger
- Implement log file rotation (by size or date)
- Add Settings UI to view/export logs
- Potentially use CocoaLumberjack or custom file logger
- Include log level filtering for file output
- Add "Export Logs" button in Settings or Debug menu
