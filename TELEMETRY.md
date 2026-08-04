# FocusFlow — Telemetry & Crash Reporting

## Overview

FocusFlow has two telemetry systems. One has been **removed** (ResourceMonitorService).
The other (CrashReporter) is **kept but opt-in only** — no data is sent until the user
explicitly enables it.

---

## 1. CrashReporter *(kept — opt-in only)*

**File:** `src/main/kotlin/com/focusflow/services/CrashReporter.kt`

### What it does
Captures uncaught exceptions from all threads (Java/Kotlin, AWT Event Dispatch Thread,
Kotlin coroutines) and:

1. **Writes a local crash log** to one of these locations (in priority order):
   - `~/Desktop/FocusFlow-crash-<timestamp>.log`
   - `~/.focusflow/crash-<timestamp>.log`
   - System temp dir

2. **Sends a Discord embed** (only if the user has opted in) containing:
   - OS name / version / arch
   - JVM name, version, vendor
   - Heap and physical RAM usage at crash time
   - Thread count / GC stats
   - Full exception chain with stack traces
   - FocusFlow enforcement state (session active, blocked processes, nuclear mode, etc.)
   - Database file metadata (path, size, WAL presence)
   - Full thread dump of all live threads

### What it never sends
- User home directory path, username, or any PII
- Task names, session content, or blocked-app lists
- IP address or any network identifier

### Safety cleanup on crash
After logging, `safetyCleanup()` runs regardless of opt-in status. This is purely
local — it restores the Windows taskbar, disables registry lockdown, ends the active
session, and clears enforcement state so the PC is never left in a locked state after
a crash. Nothing is sent over the network by this step.

### Privacy default
**`crash_reports_enabled` defaults to `false`.**  
No data is ever sent until the user explicitly enables "Anonymous crash reports" in
Settings → Privacy, or accepts the consent prompt that appears after first launch.

The `TelemetryConsentDialog` is shown once (on the 2nd launch after onboarding).
The toggle is also available at any time in **Settings → Privacy & Diagnostics**.

### Opt-out
Set `crash_reports_enabled = false` in Settings. Immediately stops all Discord
reporting. Local crash logs are always written regardless of this setting (they
are only on the user's own machine).

---

## 2. ResourceMonitorService *(removed)*

**File:** `src/main/kotlin/com/focusflow/services/ResourceMonitorService.kt`  
**Status:** Deleted. No longer started or called anywhere.

### What it did (for historical reference)
- Background daemon thread, sampled JVM/OS metrics every 60 seconds
- Sent a **Discord embed heartbeat** once per hour containing:
  - Heap usage (used / allocated / max, peak over the period)
  - Non-heap memory, physical RAM free/total
  - Live thread count (peak, daemon, period peak)
  - GC collection count and cumulative pause time
  - OS name + Java version + app version
- Sent **immediate alerts** when heap > 75% (warning) or > 90% (critical) of max
- Sent **immediate alerts** when live thread count > 150
- Also fired one-shot **mode-event embeds** whenever the user triggered significant
  enforcement actions (start/stop sessions, enable nuclear mode, take emergency break,
  configure pomodoro, etc.)

### Why it was removed
- Sent data on every app launch without an explicit consent check before first launch
- Mode-event embeds reported user behaviour patterns (how often they use nuclear mode,
  when they take emergency breaks, which onboarding presets they chose, etc.)
- The periodic heartbeat provided developer visibility into JVM health but at the
  cost of sending data from every installed instance, regardless of opt-in timing
- All useful crash-time diagnostics are already captured by CrashReporter, which is
  triggered only when something actually goes wrong

---

## 3. Consent flow

| Event | Behaviour |
|---|---|
| First launch | `crash_reports_enabled` = `null` (not set). No data sent. |
| Second launch (post-onboarding) | `TelemetryConsentDialog` shown. User picks Yes/No. |
| User picks Yes | `crash_reports_enabled = "true"`. Crash reports enabled. |
| User picks No | `crash_reports_enabled = "false"`. Nothing is ever sent. |
| Null (never answered) | Treated as **false** — no data sent. |
| Settings toggle | Updates `crash_reports_enabled` at any time. |

---

## 4. Database keys

| Key | Values | Meaning |
|---|---|---|
| `crash_reports_enabled` | `"true"` / `"false"` / `null` | Opt-in flag. Null = not yet answered = treated as false. |
| `last_crash_version` | version string | App version at time of last crash. Used for next-launch recovery dialog. |
| `last_crash_ts` | ISO timestamp | Wall-clock time of last crash. |
