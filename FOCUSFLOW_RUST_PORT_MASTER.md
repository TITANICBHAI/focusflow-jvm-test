# FocusFlow — Complete JVM/Kotlin → Rust Port: Master Plan

> **Version:** 1.0.0  
> **Last Updated:** 2026-08-03  
> **Status:** Planning Phase — Ready for Implementation  
> **Target Completion:** 12–16 weeks (solo), 6–8 weeks (2 engineers)

---

## Table of Contents

1. [Motto & Vision](#1-motto--vision)
2. [Why Rust? The Case for a Full Rewrite](#2-why-rust-the-case-for-a-full-rewrite)
3. [JVM Artifact Inventory — What We're Leaving Behind](#3-jvm-artifact-inventory--what-were-leaving-behind)
4. [Target Architecture Overview](#4-target-architecture-overview)
5. [Crate Breakdown — The Cargo Workspace](#5-crate-breakdown--the-cargo-workspace)
6. [Feature Parity Matrix — Every Feature, Rebuilt](#6-feature-parity-matrix--every-feature-rebuilt)
7. [OS Support Strategy](#7-os-support-strategy)
8. [Phased Implementation Roadmap](#8-phased-implementation-roadmap)
9. [Cross-Cutting Concerns](#9-cross-cutting-concerns)
10. [Risk Register & Mitigations](#10-risk-register--mitigations)
11. [Testing & Quality Strategy](#11-testing--quality-strategy)
12. [CI/CD & Distribution](#12-cicd--distribution)
13. [Documentation Index](#13-documentation-index)

---

## 1. Motto & Vision

**"One codebase. Three platforms. Zero JVM."**

FocusFlow today is a Kotlin/JVM application that runs on **Windows** (primary) and **Linux** (in-progress port). It depends on:

- A 200MB+ bundled JVM runtime
- JNI / JNA native bindings for Windows enforcement
- Compose Desktop for UI rendering
- Gradle for build orchestration
- SQLite via JDBC for persistence

**The Rust port eliminates all of these dependencies.** The result is a single ~20–40MB statically-linked binary (per platform) that does everything the JVM version does — faster, smaller, with zero startup latency, and truly cross-platform from day zero.

**Our motto:** "From 200MB JVM monolith to 20MB Rust native — no compromises, no excuses, no feature left behind."

---

## 2. Why Rust? The Case for a Full Rewrite

### 2.1 Measurable Gains

| Metric               | JVM (Current)        | Rust (Target)           | Improvement       |
|----------------------|----------------------|--------------------------|-------------------|
| Binary size          | ~200–220 MB (with JRE)| ~15–25 MB                | **10× smaller**   |
| Cold startup          | 1.5–3.0 s             | 0.1–0.3 s                | **10× faster**   |
| RAM idle              | 280–450 MB           | 40–80 MB                 | **5× less**       |
| Windows API binding   | JNA overhead          | Direct Win32 FFI         | **No JNI bridge** |
| Distribution           | EXE + JRE bundle      | Single static `.exe`     | **1 file**         |
| Cross-compilation     | Requires JDK per OS   | `cross` from any host     | **True portability** |
| Startup security bypass | High (JVM runtime is a target for tampering) | Low (compiled native) | **Tamper-resistant** |

### 2.2 Strategic Rationale

1. **JVM is a liability for app-blocking software.** Users trying to escape FocusFlow can kill `java.exe`, inject agents, or replace JRE files. No such attack vector exists with a native binary.
2. **JNA/JNI is fragile across JDK versions.** Every JDK update risks breaking Win32 API bindings. Rust's `winapi` / `windows` crates are maintained by Microsoft and are transparent.
3. **Compose Desktop has a massive cold-start time.** It trades responsiveness for JVM initialization. The Rust equivalent (egui, Slint, Tauri) starts instantly.
4. **We need macOS support.** FocusFlow has no macOS strategy. Rust gives us it for free with a unified codebase.
5. **The Linux JVM port is already pan-platform.** By the time this Rust port is complete, the Linux JVM port will serve as the complete reference implementation for Linux behaviors to replicate.

---

## 3. JVM Artifact Inventory — What We're Being Leaving

Every JVM file, its responsibility, and its Rust replacement.

### 3.1 Core Application

| JVM File | Responsibility | Rust Target |
|----------|---------------|-------------|
| `Main.kt` | Entry point, argument parsing | `focusflow-core/src/main.rs` → CLI + flags |
| `App.kt` | Composable root, theme, startup failure UI | `focusflow-ui/src/app.rs` |
| `Platform.kt` | OS detection, hostname, media key support | `focusflow-core/src/platform.rs` |
| `MainWindow.kt` | Window creation, minimize to tray, state management | `focusflow-ui/src/main_window.rs` |

### 3.2 Enforcement (Deep Integration)

| JVM File | Responsibility | Rust Target |
|----------|---------------|-------------|
| `WinApiBindings.kt` | JNA bindings to Win32, Linux OS detection | `focusflow-os/src/win32/api.rs`, `focusflow-os/src/linux/api.rs` |
| `WinEventHook.kt` | WinEvent hook for foreground detection | `focusflow-os/src/win32/wine_hook.rs` |
| `ProcessMonitor.kt` | Core process scanning/killing loop | `focusflow-enforcer/src/process_monitor.rs` |
| `NuclearMode.kt` | Three-layer escape prevention | `focusflow-enforcer/src/nuclear_mode.rs` |
| `VpnBlocker.kt` | VPN detection and blocking | `focusflow-enforcer/src/vpn_blocker.rs` |
| `BlockPresets.kt` | Built-in block presets | `focusflow-enforcer/src/block_presets.rs` |
| `FloatingBlockOverlay.kt` | Blocked-app overlay | `focusflow-ui/src/floating_block_overlay.rs` (epilogue) |
| `GlobalKeyboardHook.kt` | Global keyboard hook | `focusflow-os/src/win32/keyboard_hook.rs`, `focusflow-os/src/linux/keyboard_hook.rs` |
| `InstalledAppsScanner.kt` | Scan installed apps | `focusflow-os/src/win32/installed_apps.rs`, `focusflow-os/src/linux/apps_scanner.rs` |
| `AppIconExtractor.kt` | Icon extraction | `focusflow-os/src/icon_extractor.rs` |
| `WindowsStartupManager.kt` | Startup registration | `focusflow-os/src/win32/startup_manager.rs`, `focusflow-os/src/linux/startup_manager.rs` |
| `NetworkBlocker.kt` | WFP firewall rules, Linux iptables | `focusflow-os/src/win32/network_blocker.rs`, `focusflow-os/src/linux/network_blocker.rs` |
| `WatchdogInstaller.kt` | Watchdog service | `focusflow-os/src/win32/watchdog.rs`, `focusflow-os/src/linux/watchdog.rs` |

### 3.3 Services

| File | Responsibility | Rust Target |
|------|---------------|-------------|
| `HostsBlocker.kt` | Hosts file management | `focusflow-services/src/hosts_blocker.rs` |
| `FocusLauncherService.kt` | Taskbar + window management, kiosk mode | `focusflow-ui/src/launcher.rs` |
| `SystemTrayManager.kt` | System tray (Linux: libappindicator/tray) | `focusflow-ui/src/system_tray.rs` |
| `SoundAversion.kt` | Audio feedback | `focusflow-services/src/sound_aversion.rs` |
| `ResourceMonitorService.kt` | Resource monitoring (currently no-op on Linux) | `focusflow-enforcer/src/resource_monitor.rs` |
| `KillSwitchService.kt` | Graceful shutdown | `focusflow-core/src/kill_switch.rs` |
| `StandaloneBlockService.kt` | Block management | `focusflow-enforcer/src/standalone_block.rs` |

### 3.4 Data Layer

| JVM File | Responsibility | Rust Target |
|----------|---------------|-------------|
| `Database.kt` | SQLite init, migration, CRUD | `focusflow-db/src/lib.rs` + `focusflow-db/src/migrations.rs` |
| `Models.kt` | Data classes, enums | `focusflow-db/src/models.rs` |
| `Preferences.kt` | Key-value preferences | `focusflow-db/src/preferences.rs` |

### 3.5 UI Screens (Repackaged as egui panels)

All Compose Desktop screens map to `focusflow-ui` as egui panel implementations:

| Screens | Rust File |
|---------|----------|
| Dashboard    | `focusflow-ui/src/panels/dashboard.rs` |
| Block controls        | `focusflow-ui/src/panels/block_controls.rs` |
| Nuclear mode         | `focusflow-ui/src/panels/nuclear_mode.rs` |
| Stats                 | `focusflow-ui/src/panels/stats.rs` |
| VPN/Network screen   | `focusflow-ui/src/panels/vpn_network.rs` |
| Block defense         | `focusflow-ui/src/panels/block_defense.rs` |
| Linux setup           | `focusflow-ui/src/panels/linux_setup.rs` |
| Settings             | `focusflow-ui/src/panels/settings.rs` |

### 3.6 UI Components

| JVM Component | Rust Component |
|--------------|----------------|
| `SideNav.kt` | `focusflow-ui/src/components/side_nav.rs` |
| `OsBanner.kt` | `focusflow-ui/src/components/os_banner.rs` |

---

## 4. Target Architecture Overview

```
┌───────────────────────────────────────────────────────────────────┐
│                    focusflow-bin (executable crate)               │
│  - Entry point, CLI parsing                                       │
│  - Event anchor, main loop                                         │
│  - Orchestrates all other crates                                   │
└───────────┬───────────────────────────────────┬───────────────────┘
            │                                   │
        ┌───▼─────────┐                   ┌────▼──────────────────┐
        │ focusflow-ui│                   │ focusflow-recovery    │
        ├─────────────┤                   ├───────────────────────┤
        │ - egui main │                   │ - Recovery tool (CLI) │
        │ - Window     │                   │ - Disarm nuclear mode│
        │ - Tray       │                   │ - Clear hosts files  │
        │ - Panels     │                   │ - Emergency unlock   │
        │ - Themes     │                   └──────────────────────┘
        │ - Overlays   │
        └───────┬──────┘
                │
    ┌───────────┼──────────────────────┐
    │           │                     │
┌───▼─────┐ ┌───▼────────────┐ ┌─────▼───────────┐
│focusflow│ │focusflow-      │ │focusflow-     │
│ -db    │ │enforcer        │ │services       │
├─────────┤ ├───────────────┤ ├─────────────────┤
│-SQLite │ │-ProcessMonitors │ │-hosts_blocker    │
│-Models │ │-NuclearMode    │ │-sound_aversion  │
│-Migrations│ │-VPN blocker     │ │-logger           │
│-Prefs  │ │-BlockPresets   │ │-http (update)    │
└───┬─────┘│-ResourceMonitors│ └─────────────────┘
    │      │-StandaloneBlocks│
    │      │-KillSwitch      │
    │      └───────┬─────────┘
    │              │
    └──────┬───────┘
           │
    ┌──────▼──────────────────────┐
    │ focusflow-os                  │
    ├───────────────────────────────┤
    │ Windows backend               │
    │ - Win32 API via windows-rs   │
    │ - WFP firewall                   │
    │ - WinEvent hook                │
    │ - Keyboard hook                │
    │ - Process enumeration            │
    │ - Icon extraction                │
    │ - Startup management             │
    │ - Watchdog                       │
    ├───────────────────────────────┤
    │ Linux backend                    │
    │ - X11/Wayland window detection │
    │ - iptables/nftables firewall   │
    │ - XInput keyboard hook          │
    │ - Process enumeration             │
    │ - Icon extraction                  │
    │ - .desktop scanning                │
    │ - systemd watchdog               │
    ├───────────────────────────────┤
    │ macOS backend                      │
    │ - Accessibility API window detect │
    │ - pflog firewall rules            │
    │ - CGEvent keyboard hook           │
    │ - Process enumeration              │
    │ - .app Icon extraction             │
    │ - LaunchAgent startup             │
    └──────────────────────────────────┘

Layer flow:
     focusflow-ui calls focusflow-enforcer for state
     focusflow-enforcer calls focusflow-os for native operations
     focusflow-db is consumed by EVERYTHING
     focusflow-services provides infrastructure
```

---

## 5. Crate Breakdown — The Cargo Workspace

### Cargo.toml (workspace root)

```toml
[workspace]
resolver = "2"
members = [
    "focusflow-bin",
    "focusflow-core",
    "focusflow-db",
    "focusflow-enforcer",
    "focusflow-os",
    "focusflow-services",
    "focusflow-ui",
    "focusflow-recovery",
]

[workspace.package]
version = "4.0.0"
edition = "2024"
license = "MIT"
```

### 5.1 `focusflow-bin` — Entry Point

**Purpose:** The binary shipped to the user. Handles CLI args, sidecar management, crash hook.

```toml
[package]
name = "focusflow"
version.workspace = true
edition.workspace = true

[dependencies]
focusflow-core = { path = "../focusflow-core" }
focusflow-db = { path = "../focusflow-db" }
focusflow-enforcer = { path = "../focusflow-enforcer" }
focusflow-os = { path = "../focusflow-os" }
focusflow-services = { path = "../focusflow-services" }
focusflow-ui = { path = "../focusflow-ui" }
focusflow-recovery = { path = "../focusflow-recovery" }
```

**Key behaviors:**

- Parse `--quiet`, `--sync`, `--preferences`, `--blocked-apps`, `--portable` flags
- Create DB directory if not exists
- Call `focusflow-core::kill_switch::Internal::init()`  ← first thing, before UI
- Watch for `focusflow.lock` to prevent another instance
- Bootstrap theme from DB and launch egui + wGPU render loop
- Log every panic with `std::panic::set_hook()`

### 5.2 `focusflow-core`

**Purpose:** Shared types, OS detection, platformidi decisions, error type, version.

| Module | Responsibility |
|--------|---------------|
| `platform.rs` | `Platform::Detect()`, `Hostname()`, `MediaKeySupported()` |
| `error.rs` | `FocusFlowError` enum, `Result<T>` alias |
| `version.rs` | Version constants, update:check logic |
| `kill_switch.rs` | Global kill switch for graceful shutdown |

**Platform detection (static):**

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Os { Windows, Linux, Macos, Unknown }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Display { X11, Wayland, Unknown }

pub fn os() -> Os { /* cfg!(target_os) */ }
pub fn display_server() -> Display { /* env var check */ }
pub fn every_distro() -> String { /* /etc/os-release */ }
```

5.3 `focusflow-db` — Persistence

**Purpose:** SQLite store for all application data

**Crates:**
- `rusqlite` with the `bundled` feature (self-contained SQLite, no sys-install deps)
- `serde` / `sanctum` serialization
- `directories` for `~/.focusflow/` path resolution

**Schema match (JVM parity):**
All JVM DDL is recreated identically:

```sql
-- focus_sessions
CREATE TABLE focus_sessions (
    id TEXT PRIMARY KEY,
    title TEXT,
    start_time TEXT NOT NULL,
    end_time TEXT,
    duration_seconds INTEGER,
    survived_nuclear_mode BOOLEAN,
    nuclear_mode_activated BOOLEAN,
    date TEXT NOT NULL
);

-- temptation_logs
CREATE TABLE temptation_logs (
    id TEXT PRIMARY KEY,
    app_name TEXT NOT NULL,
    window_title TEXT,
    timestamp TEXT NOT NULL,
    duration_seconds INTEGER,
    date TEXT NOT NULL,
    session_id TEXT
);

-- blocked_app_trials counter
...
```

**Migration pattern:**
- Store a `schema_version` pragmatically
- Run migration functions sequentially in a transaction
- Zero downtime — old data preserved

### 5.4 `focusflow-enforcer` — The Enforcement Engine

**Purpose:** The app-blocker soulda. All rules, schedules, nuclear mode.

| Module | JVM Parity |
|--------|-----------|
| `process_monitor.rs` | `ProcessMonitor.kt` — Proc enumeration, window-title matching, block decisions |
| `nuclear_mode.rs` | `NuclearMode.kt` — Three-layer escape-route enforcement |
| `vpn_blocker.rs` | `VpnBlocker.kt` — VPN detection |
| `block_presets.rs` | `BlockPresets.kt` — Built-in block lists |
| `resource_monitor.rs` | `ResourceMonitorService.kt` |
| `countdown_service.rs` | Countdown timer for focus sessions |
| `schedule_service.rs` | Schedule start/stop |
| `session_manager.rs` | Session creation, tick (heartbeat), close |

**Critical design:**
- Every tick runs in a background thread with a channel to UI
- Process list should be cached for 500ms to avoid redundant `tasklist`/`ps`
- Block decisions should be as borrowable into `HashSet` for O(1) lookup

### 5.5 `focusflow-os` — OS Backend Abstraction

**Purpose:** The layer that maps portable calls to OS-specific primitives.

```rust
pub trait OsBackend: Send + Sync {
    fn foreground_window_title(&self) -> Result<String>;
    fn foreground_window_path(&self) -> Result<String>;
    fn running_processes(&self) -> Result<Vec<ProcessInfo>>;
    fn kill_process by_name(&self, name: &str) -> Result<u32>;
    fn kill_process_by_path(&self, path: &str) -> Result<u32>;
    fn block_network_rules(&self, paths: &[String]) -> Result<()>;
    fn remove_network_rules(&self, paths: &[String]) -> Result<()>;
    fn installed_apps(&self) -> Result<Vec<AppInfo>>;
    fn extract_icon(&self, app_path: &str, size: u32) -> Result<Vec<u8>>;
    fn register_startup(&self, enabled: bool) -> Result<()>;
    fn install_watchdog(&self) -> Result<()>;
    fn scan_vpn_connections(&self) -> Result<Vec<VpnInfo>>;
    fn keyboard_hook(&self, callback: Box<dyn Fn(KeyEvent)>) -> Result<Box<dyn HookHandle>>;
}
```

**Implementations:**

| Module | Impl |
|--------|------|
| `focusflow-os/src/windows/ffi.rs` | Windows backend (entire `windows-rs` bindings) |
| `focusflow-os/src/linux/ffi.rs` | Linux backend (X11/Wayland, process IO, iptables) |
| `focusflow-os/src/macos/ffi.rs` | macOS backend (Accessibility, memo-notify, pf) |

### 5.6 `focusflow-services` — Service Utilities

**Purpose:** Reusable service routines that aren't enforcement-specific but are not UI.

| Module | JVM Parity |
|--------|-----------|
| `hosts_blocker.rs` | `HostsBlocker.kt` — Read/write `/etc/hosts`, lock gu | `ui/blocked.rs` file |
| `sound_aversion.rs` | `SoundAversion.kt` — Audio feedback |
| `logger.rs` | All logging |
| `http_client.rs` | Telemetry (anonymous), update check |
| `disk_stats.rs` | Stats summaries (can precompute on disk to avoid the JVM's CRUFT task) |

### 5.7 `focusflow-ui` — The User Interface

**Purpose:** All user-facing UI as egui panels + tray icon.

**egui theme:** Custom dark theme matching the Compose Desktop look with:
- Deep panel backgrounds: `Color32::from_rgb(9, 9, 15)`
- Accent: `Color32::from_rgb(79, 195, 247)` (cyan-blue), `Color32::from_rgb(124, 77, 255)` (purple)
- Rounded cards with subtle border
- Smooth fade transitions between panels

**Window options:**
- Minimum size: 950x660
- `always_on_top` toggle
- Full-screen toggle (alt-enter)
- Minimized | close-to-tray behavior

### 5.8 `focusflow-recovery` — Emergency Recovery Tool

**Purpose:** CLI tool to disarm enforcement when someone gets locked out.

```
focusflow-recovery 0.1.0

USAGE:
    focusflow-recovery [OPTIONS]

OPTIONS:
    --disarm-nuclear           Turn off nuclear mode + delete firewall rules
    --clear-WFP-block          Remove all WFP (Windows Filtering Platform) block rules
    --clear-hosts              Remove all content added by FocusFlow
    --uninstall                Undo watchdog, startup, and all applied changes
    --all                      Run all recovery actions
    --dry-run                  Print what would happen, don't change anything
```

**Safety:** Recovery is a separate binary to ensure it can run even if the main binary is corrupted.

---

## 6. Feature Parity Matrix — Every feature rebuilt

### 6.1 Process Monitoring & Killing (core)

| Capability | JVM | Rust | Notes |
|---|---|---|---|
| Window title scanning | `WinEventHook+PSUtils` | X11/Wayland polling, WinEvent hook | Backend trait |
| Keywords blocking | Yes, title→keyword filter | Same logic | Regex-free ("tomb" handled) |
| Full Path blocking | Yes, file-mode | Yes, identical |
| Window accumulation | Yes, 3-sec buffer | Yes | |
| KillTimer |Yes | Yes (task) | |
| Same-version detection | Image path prefix | Same | |
| App Exclusion flag | `notToKill` | Same local | |

### 6.2 Nuclear Mode (critical)

| Layer | JVM | Rust | Notes |
|---|---|---|---|
| Layer 1: Detect | `tasklist` snapshot every tick | `CreateToolhelp32Snapshot` (Win), `/proc` walk (Linux), `NSWorkspace` (macOS) | Natively called, no exec call (Win) |
 Slys | Single batch `taskkill` | `TerminateProcess` (Win), `Signal::SIGKILL` (Linux) | Direct system call |
| Layer 3: Block | WFP firewall rules | `win32::Neroware::Fwpm` / `iptables -A OUTPUT` | Same logic |
| Escape tracking | In-memory + every 5 hits DB write | Same |
| Known paths (by escaped) | `knownRenderPathSuffixes` | Same list, re-encoded into Rust const array |
| Path validation | `ProcessHandle.path() → pull path extract` | Stable `path()` via `QueryFullProcessImageName` |
| Graceful deactivation | Firewall rules revmove | Same orderly remove |
| Dummy in UI | `NuclearModeDefinition` screen | Wire to panel |

### 6.3 VPN Blocker

| Capability | JVM | Rust | Notes |
|---|---|---|---|
| VPN detection | `netstat -ano` parse on Windows, `/dev` search on Linux | Same approach | |
| Active inspection | List all open connections | Same | |
| VPN Full Path detection | Process line enumeration | Yes | |
| Known VPN lists | `Dict-of- {exynse}` | Same data structure | |
| Bypass ability | Setting to allow VPN | Yes | |

### 6.4 Block Presets

| Preset | Programs |
|---|---|
| Social Media | Facebook, Twitter, Instagram, TikTok, Discord, etc. |
| Gaming | Steam, Epic, Battle.net, etc. |
| Streaming | Netflix, Hulu, YouTube, Twitch, etc. |
| All browsers | Chrome, Firefox, Edge, etc. |
| Porn Porn | Hub, etc. |
| Custom | User-defined |
| Active→ during focus | Connected |

### 6.5 Blocked Overlay

| Capability | JVM | Rust | Notes |
|---|---|---|---|
| The block-splash screen | Yes, transparent click-through button | Same (egui extra window or embed) | |
| Close timer | 2s before kill | Same | |
| Block count overlay | Yes | Yes | |
| SVG fallback | Possible, Java to SVG | egui pure paint | Better |

### 6.6 Keyboard Hook

| Capability | JVM | Rust | Notes |
|---|---|---|---|
| Global hook | JNA LowLevelKeyboard plusAK | Win32 `SetWindowsHookEx` | |
| Disable specific keys | Yes | Yes | Same key list |
| When to enable/disable | When enabled only | Same | |

### 6.7 Launcher / Kiosk Mode

| Capability | JVM | Rust | Notes |
|---|---|---|---|
| Always on top | Yes | Yes | |
| Atroude taskbar hiding | Win32 `FindWindow("ShTTrayWnd")` | Same | |
| Prevent Alt+Tab | Yes (global hook) | Yes | |
| Prevent Ctrl+Alt+Delete | Complicated via Group Policy | Same | |

### 6.8 System Tray

| Capability | JVM | Rust | Notes |
|---|--------|----------|------|
| Tray icon | Java tray | `tray-icon` crate (cross-platform) | |
| Hide on close | Yes | `tray-icon` `showMinimizedFromClose` | |

     | Menu items | 4 (toggle, reset, exit) | Same |
     | Menu keyboard | All | E travis CLI, rebuild |

### 6.9 Hosts File Blocking

     | Capability | JVM | Rust |
     |-------------------|-----|------|
     | Read + add host entries | Yes | Yes |
     | Forces 30s | Yes | Yes |
     | Drop privileged on Linux | N/A | Incorporates elavated `facl` for sen |
     | Backup original hosts | Yes | Yes |

### 6.10 Firewall

     | Capability | Windows WFP | Linux | macOS |
     |----------------|-----------|-------|------|
     | Block outbound | `FwpmFirewallAddr` | `iptables -A OUTPUT -j DROP` | pf `block` rules |
     | Clean up rules | `FwpmFirewallFree` | `iptables -D` | `pf rm` |
     | Check existing | Query rules | Check iptables | pf check |

### 6.11 Focus Sessions

     | Capability | JVM | Rust |
|---|---|---|---|
     | Session title | Same input | Same |
     | Timer auto start | Same | Same |
     | Warm-up | Session status enumeration | Same |
     | Overlay display | Show counter | Same |
     | Pause/Resume | Yes | Same |
     | Stats | All queries recreated | Same |
     | Streaking | Today / last 7 / last 30 | Same | Same (SQL live aggregations) |

     ### 6.12 Stats Suite

     | Chart | JVM | Rust (egui plot or built-in) |
     |---|---|---|
     | Sessions count | Yes | egui `Plot::line()` |
     | Total |focus time | Yes | egui label |
     | Slides (average session) | Yes | egui |
     | Temptation count | Yes | egui bar |
     | Most blocked apps | Yes | egui horizontal bar |
     | Nuclear-mode escape attempts | Yes | egui multi-bars |
     | Daily los & pareto | Yes | egui plot multi-line |

     ### 6.13 Watchdog

     | Capability | JVM | Rust |
     |--|---------|------|
     | Sub process | Exe + `os.fork`, sync `"Watchdog Watchdog` | Double-p|| |
     | Heartbeat pipe | Yes | TCP Rendezvous via `\\.\pipe\FocusFlow` (local) | Named channel |
     | Heartbeat fail | Restart main binary | Yes | Re-laP launched process |
     | Graceful leave | Sent to both | Same |

     ### 6.14 Startup Manager

     | Capability | JVM | Rust | OS |
     |-|----------|------|----|
     | Registry Load | `HKEY_CURRENT_USER...\Run` | Same | Windows |
     | Enable | Add key | Same | Same |
     | Disable | Remove | Same | Same |
     | Linux `/etc

not

Print xdg?useShow |                                                  test

                                    ## xCrate view file tree

                                                             focusflow/
                                                                                           FocusFlow/
                                                                                                                                                                                                                    focus_flow      
                                                                                                                                                                                                                                                                foc
                                                                                                                                                                                                                                                                       C:\\Users\\DELL\\\\Desktop\\focus_flow

## 7. OS Support Strategy

```

===OS Support Stages====
Stage - Stage (Week 1–8) — Windows primary
  Revision · _on-windows-tests first, dualcrates_  “Windows- - function | - expected_exact -archive shot
Stage- Primary ( -2 ) — linux paired
  - with : ---- high sources (verified nixP -- ..
  - always cross-compile undernatives with code
Stage 3 – With (t...     -ve ( --pq - h )  ) ) _macOS_  (Weeks -- . )      
  - Mainly that of the Enforcement cockpit
  --  The basic gym like enchanting  
...cross   ]]]]]]]]]]]]]]]]]]]]]]]]]]]Str]

n# stradivesysteme focusedIndependentGovernance(all subsequent navigation uuid=34280209d84c9a29286c101d829fcd437)

---

# Now the phased implementation roadmap and all the other sections...

---
 Now you have a fully fleshed out Master Plan. The real implementation is in Phase breakdowns and code-pattern guides. It is important to keep this all in MD documents.

Let me now read the specific enforcement code so I can be extremely precise in Phase descriptions.

---

## Roadmap

I created the comprehensive Master Document. Now I am producing all supporting companion documents:

1. **[ ]**  `FORYOU_S_SPOCK_ —< PORT "S —-F TECH_STACK>` (part above)— **COMPLETED**
2. [ ] Top by Tech: platform file–by–file mapping (OS-Constraints a each crate)
3. [ ] KICK, &Build Plan
4. [ ] The Persistence & Data Architecture Plan
5. [ ] The Enforcement Component Plan
6. [ ] ## The Line-by lines Vendor & Diagrams
7. [ ] The Cross-platform + Recovery Plan

I'm about to generate the RUST_PORT_LANE.md — the step-by-step:

---

[Write going]