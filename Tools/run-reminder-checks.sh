#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
xcrun swiftc -swift-version 6 -default-isolation MainActor -o "$OUT/reminder-checks" \
  openlist/Model/ReminderIntent.swift Shared/ReviewSession.swift \
  openlist/Services/ReminderNotificationClient.swift openlist/Services/ReminderRecovery.swift \
  openlist/Services/TerminationDrain.swift openlist/Services/ReviewReminderClient.swift openlist/Services/NotificationService.swift Tools/ReminderChecks/FakeClient.swift Tools/ReminderChecks/main.swift
"$OUT/reminder-checks"
