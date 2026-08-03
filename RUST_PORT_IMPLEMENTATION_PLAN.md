# FocusFlow → Rust: Tactical Implementation Plan

> **Companion to:** `FOCUSFLOW_RUST_PORT_MASTER.md`  
> **Purpose:** Week-by-week execution plan with exact file creation order, dependency trees, and completion gates.  
> **Audience:** Engineers executing the port.

---

## Table of Contents

1. [Prerequisites & Toolchain Setup](#1-prerequisites--toolchain-setup)
2. [Phase 0: Workspace Scaffold (Week 1)](#2-phase-0-workspace-scaffold)
3. [Phase 1: Core Types & OS Detection (Week 1–2)](#3-phase-1-core-types--os-detection)
4. [Phase 2: Data Layer — SQLite & Migrations (Week 2–3)](#4-phase-2-data-layer--sqlite--migrations)
5. [Phase 3: OS Backend — Windows (Week 3–5)](#5-phase-3-os-backend--windows)
6. [Phase 4: Enforcement Engine (Week 5–7)](#6-phase-4-enforcement-engine)
7. [Phase 5: Services Layer (Week 7–8)](#7-phase-5-services-layer)
8. [Phase 6: egui UI — Panels & Theme (Week 8–10)](#8-phase-6-egui-ui--panels--theme)
9. [Phase 7: Linux Backend (Week 10–12)](#9-phase-7-linux-backend)
10. [Phase 8: macOS Backend (Week 12–14)](#10-phase-8-macos-backend)
11. [Phase 9: Recovery Tool & Watchdog (Week 13–14)](#11-phase-9-recovery-tool--watchdog)
12. [Phase 10: CI/CD, Packaging, Shipping (Week 14–16)](#12-phase-10-cicd-packaging-shipping)

---

## 1. Prerequisites & Toolchain Setup

### 1.1 Toolchain

```bash
# Rust stable
rustup default stable
rustup update

# Cross-compilation for Linux from Windows/macOS
cargo install cross --git https://github.com/cross-rs/cross

# Windows build dependencies (visual studio build tools, not needed for cross compile)
# On Windows: install Visual Studio Build Tools 2022 (C++ workload)

# Linux target
rustup target add x86_64-unknown-linux-gnu

# macOS target (only from macOS, x64 + ARM)
rustup target add x86_64-apple-darwin
rustup target add aarch64-apple-darwin

# Verify
rustc --version && cargo --version
```

### 1.2 Required System Crates (listed per crate in each phase)

Every crate uses `edition = "2024"`, `rust-version = "1.85"`.

### 1.3 Git Strategy

```
main
  ├── phase-0-workspace        (merge into main after completion)
  ├── phase-1-core             (merge into phase-1-core → main)
  ├── phase-2-db               (merge)
  ├── phase-3-win-backend      (merge)
  ├── phase-4-enforcer         (merge)
  ...
```

Each phase is a branch. Merges are squash-merge to `main`. Tests must pass on the target platform before merge.

---

## 2. Phase 0: Workspace Scaffold (Week 0)

**Goal:** Create an empty, compilable, cargo workspace with all 8 crates defined.

### 2.1 Directory Structure

```
focusflow/              ← New project root (separate from JVM repo)
├── Cargo.toml          ← Workspace root
├── .gitignore
├── README.md
├── CLAUDE.md           ← Agent instruction file for future Claude sessions
├── focusflow-bin/
│   ├── Cargo.toml
│   └── src/
│       └── main.rs     ← "Hello, FocusFlow" → println!("...") + `focusflow_core::version()`
├── focusflow-core/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-db/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-enforcer/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-os/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-services/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-ui/
│   ├── Cargo.toml
│   └── src/lib.rs      ← stub
├── focusflow-recovery/
│   ├── Cargo.toml
│   └── src/main.rs     ← stub (separate binary)
```

### 2.2 Completion criteria

- `cargo build` compiles all 8 targets with zero warnings
- `cargo run --bin focusflow` prints the version
- `cargo run --bin focusflow-recovery` prints "Recovery tool running"
- Each crate has `#[deny(unsafe_code)]` by default (excluding `focusflow-os` where unsafe OS FFI is intended)
- Each crate has `#![deny(missing_docs)]` (soft enforcement for docs)
- `cargo clippy -- -A clippy::all` passes

---

## 3. Phase 1: Core Types & OS Detection (Week 1–2)

### 3.1 Deliverables

#### `focusflow-core/src/lib.rs` → re-exports all modules

| File | Contents |
|------|----------|
| `focusflow-core/src/platform.rs` | OS + display server detection |
| `focusflow-core/src/error.rs` | `FocusFlowError` enum |
| `focusflow-core/src/version.rs` | constants |
| `focusflow-core/src/kill_switch.rs` | Global kill switch with `AtomicBool` |

#### 3.1.1 `platform.rs` — Exact Port from `Platform.kt`

```rust
// Public statics
pub(crate) fn os() -> Os { /* cfg!(target_os = "windows") etc. */ }
pub(crate) fn display_server() -> Display { /* env["XDG_SESSION_TYPE","WAYLAND_DISPLAY"] */ }
pub(crate) fn distro_name() -> String { /* /etc/os-release or "Windows/macOS" */ }
pub(crate) fn hostname() -> String { /* gethostname() */ }
pub(crate) fn media_key_handler() -> Option<MediaKey>  // Fn→ hardware key→ FocusFlow "skip" callback
```

#### 3.1.2 `error.rs`

```rust
#[derive(Debug, thiserror::Error)]
pub enum FocusFlowError {
    #[error("OS backend not supported: {0}")]
    UnsupportedPlatform(String),
    #[error("DB error: {0}")]
    Database(#[from] rusqlite::Error),
    #[error("I/O error: {0}")]
    Io(#[from] std::io::Error),
    #[error("Permission denied: {0}")]
    PermissionDenied(String),
    #[error("Enforcement error: {0}")]
    Enforcement(String),
}
- public type Result<T> = std::result::Result<T, FocusFlowError>;
```

#### 3.1.3 `version.rs`

```rust
pub const VERSION: &str = "4.0.0";
pub const BUILD_DATE: &str = env!("VERGEN_GIT_COMMIT_DATE", "...");
pub const GIT_COMMIT: &str = env!("VERGEN_GIT_SHA", "...");

pub(crate) fn full_version() -> String { format!("FocusFlow v{VERSION} ({GIT_COMMIT})") }
```

#### 3.1.4 `kill_switch.rs`

```rust
use std::sync::atomic::{AtomicBool, Ordering};
pub(crate) struct KillSwitch(AtomicBool);

impl KillSwitch {
    pub fn new() -> Self { KillSwitch(AtomicBool::new(false)) }
    pub fn arm(&self) { self.0.store(true, Ordering::Release); }
    pub fn should_terminate(&self) -> bool { self.0.load(Ordering::Acquire) }
}
```

### 3.2 Exit Criteria

- `cargo run` detects OS and prints to stdout
- All tests pass (`cargo test`)
- Compilation on Windows, Linux (via WSL), and macOS (via GitHub Runner)

---

## 4. Phase 2: Data Layer → SQLite & Migrations (Week 2–3)

### 4.1 Deliverables

**Reference:** `Database.kt` (1281 lines) → the golden schema source.

| File | Purpose |
|------|--------|
| `focusflow-db/src/models.rs` | All Rust structs matching Kotlin data classes |
| `focusflow-db/src/migrations.rs` | Migration versioning |
| `focusflow-db/src/lib.rs` | Database struct with CRUD methods |

#### 4.1.1 Models (from `Models.kt`)

```rust
// Each Kotlin data class → Rust struct + serde Serialize/Deserialize + rusqlite FromRow

use serde::{Serialize, Deserialize};
use time::OffsetDateTime;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FocusSession {
    pub id: String,                        // UUID v4
    pub title: String,
    pub start_time: OffsetDateTime,         // ISO 8601
    pub end_time: Option<OffsetDateTime>,
    pub duration_seconds: i64,
    pub survived_nuclear_mode: bool,
    pub nuclear_mode_activated: bool,
    pub date: String,                       // YYYY-MM-DD
}

// Repeat for: TemptationLog, BlockedApp, Preference, PresetItem, etc.

// Enums
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum BlockMode { FileBacked, Keyword, PathBlocked }

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SessionStatus { WarmingUp, Running, Paused, Finished }
```

#### 4.2.3 Database.create

Identical schema to JVM:

```rust
// focusflow-db/src/lib.rs
use rusqlite::{Connection, params};
use std::sync::Mutex;

type pool = rasalite_ Connection
pub struct Database {
    conn_name:: rusparktrace_pool:Mutex<Connection>,
}

impl Database {
    pub fn open() -> Result<Self> {
        // Path: believe to home → .focusflow/focusflow.db
        // If directory doesn't exist: create it
        // SQLITE_BUSY errors handled by busy_timeout = 10_000
    }

    fn migrate(&self) -> Result<()> {
        // Run each migration transaction
        // Create schema_version table if doesn't exist
        // Run only missing migrations
    }

    // All CRUD methods match JVM exactly:
    pub fn insert_focus_session(&self, session: &FocusSession) -> Result<()> {..}
    pub fn get_today_temptations(&self) -> Result<u64> {…}
    pub fn get_nuclear_escape_attempts(&self) -> Result or counts by process → {}
    …
}
```

#### 4.2.4 Dependency

```toml
[dependencies] = { vec : [ 'rusqlite/features= ["bundled,sqlcipher'] ', serde got json , 'sanctum', 'directories', 'chrono' [time crate], 'uuid' ] }
```

### 4.2 Exit Criteria

- Open, create, insert, query from sqlite in integration test
- Migrations passing sequentially
- No `unwrap()` in the data layer — all result patterns

---

## 5. Phase 3: OS Backend — Windows (Week 3–5)

### 5.1 Goal

Provide the concrete Windows OS backend that enables every enforcement feature.

### 5.2 Files

```
focusflow-os/
├── Cargo.toml
├── src/
│   ├── lib.rs                  ← re-exports `OsBackend` trait
│   ├── os_backend.rs           ← trait definition
│   ├── process_info.rs         ← ProcessInfo struct
│   └── windows/
│       ├── mod.rs              ← backend construction
│       ├── process.rs          ← CreateToolhelp32Snapshot, TerminateProcess, QueryFullProcessImageName
│       ├── window_proxt.rs     ← GetForegroundWindow+GetWindowText+GetWindowThreadProcessId
│       ├── keyboard_hook.rs    ← SetWindowsHookExW(WH_KEYBOARD_LL)
│       ├── firewall.rs          ← WFP → INetFwPolicy2 / IPersist  COM interface
│       ├── installed_apps.rs   ← Read Start Menu, Registry, Auto Junk
│       ├── icon_extractor.rs     ← shell32:ExtractIconEx, IExtractIcon
│       ├── startup_manager.rs ← Registry key HKCU → → start → → YT for all launch
│       └── watchdog_installer.rs  ← WinService via sc.exe or pump temp
```

### 5.3 OS Key APIs / Examples

#### 5.3.1 Process Snapshot

```rust
// process.rs
use windows::Win32::System::ProcessStatus::{K32GetProcessImageFileNameW, K32GetProcessMemoryInfo,
   ProcessId};
use windows::Win32::System::Thread::CreateToolhelp32Snapshot;
use windows::Win32::System::Thread::{PROCESSENTRY32, TH32CS_SNAPROCESS};

pub fn enumerate_processes() -> Result<Vec<ProcessInfo>> {
    unsafe {
        let snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPROCESS, 0)?;
        let mut pe: PROCESSENTRY32 = Default::default();
        pe.dwSize = std::mem::size_of::<PROCESSENTRY32>() as u32;
        // iterate via Process32FirstW / Process32NextW
        // For each: OpenProcess + QueryFullProcessImageName → path
        // Build → Vec<ProcessInfo>
    }
}
```

#### 5.3.2 Process Kill

```rust
pub fn kill__multiple(names: &[String],) -> Result<u32> {
    unsafe {
        for pup - resAll -> processes list → matching the name → open process → `TerminateProcess`
    }
}
```

#### 5.3.3 Firewall Rules (WFP)

```rust
// Involves com::create_instance::<INetFwPolicy2> → iterate FwRule
pub fn add_outgoing_block_rules(&self, quit_program_paths: &[String]) -> Result<()> {
    for path in paths {
        // rule{} Name = FocusFlow Block (path):program", Path = path
        // rule→Action = Block;
        // policy2.Rules.Add②→rule)
    }
}
```

### 5.4 Exit Criteria

- `cargo test` passes all Windows tests (CTRL + F5) practice
- Process can be enumerated
- Kill process works
- Firewall rules add and remove (check via netsh or WFP PowerShell)
- Keyboard hook: game key that fires debug log
- FORE ground window title returned correctly

---

## 6. Phase 4: Enforcement Engine (Week 5–7)

### 6.1 Files

| File | JVM Parity |
|------|-----------|
| `focusflow-enforcer/src/process_monitor.rs` | Complete rewriting of `ProcessMonitor.kt` |
| `focusflow-enforcer/src/nuclear_mode.rs` | `NuclearMode.kt` |
| `focusflow-enforcer/src/vpn_blocker.rs` | `VpnBlocker.kt` |
| `focusflow-enforcer/src/block_presets.rs` | `BlockPresets.kt` |
| `focusflow-enforcer/src/session_timer.rs` | Countdown / session management |
| `focusflow-enforcer/src/schedule_manager.rs` | Scheduler guard |

### 6.2 Process Monitor

```rust
// The core loop
pub fn tick(
    enforcer: &EnforcerState,
    platforms: &Box<dyn OsBackend>,
    db: &Database,
) -> Result<TickResult> {
    let fg_window = os_backend..foreground_window_title()?;
    let fg_path = os_backend.foreground_window_path()?;

    // Same logic as JVM:
    … 1/ check if title→any keyword present
    … 2/ check path→in block set
    … 3/ accumulate window time (3s)
    … 4/ schedule kill if exceeding threshold

    // State: kernel →can block for per app
    // profile kill count
    // if nuclear spells→ -> try immediate kill
}
```

### 6.3 Nuclear Mode (`nuclear_mode.rs`)

```
// same behavior from JVM → Section 2 of this plan
// Escape process set → const array (same width as Kotlin)
// For each scan → match against known\path full name + suffix
// If kill by process name → batch kill
// Apply firewall rule
// Deactivation → housekeeping removal
```

### 6.4 Key Design Pattern

**Trait-bound architecture for testability** — not magic:

```rust
pub trait ProcessBehavior {
    fn tick(&self) -> TickResult;  //pure → computation, passthroughFS input around time
}

/// Each enforcer method takes `&impl OsBackend` so we can mock it for testing
```

### 6.5 Exit Criteria

- Process scanning finds foreground window
- Keyword blocking triggers correctly
- Block overlay decision returned for UI
- Nuclear mode activation and deactivation works in automated tests with mock backend

---

## 7. Phase 5: Services Layer (Week 7–8)

### 7.1 Files

| File | Purpose |
|------|--------|
| `hosts_blocker/mod.rs` | Hosts edit with backup |
| hosts` + backup  | remove all FocusFlow content |
| `logger.rs` | log/tracing crate |
| `http_client.rs` | update checks |
| `sound_aversion.rs` | system sound feedback |

### 7.2 Hosts Blocker Behavior (from `HostsBlocker.kt`)

```rust
/// Paths: Linux: /etc/hosts, Windows: system32..hosts, macOS: /private/etc/hosts
pub struct HostsBlocker { backup: &'static ← backup script}
fn add_entry(domain: &str) → error
fn clear_all”→“ then the blocking content only”
fn backup_preserve”
```

### 7.3 Exit Criteria

- Integration tests based: add domain, verify hosts file modified
- Restore returns original hosts file intact
- Permissions correctly handled with error messages on Linux if non-root

---

## 8. Phase 6: egui UI — Panels, Theme, Tray (Week 8–10)

### 8.1 UI dependency

```toml
[dependencies]
eframe = "0.31"
egui = "0.31"
egui_extras = { version = "0.31", features = ["image"] }
egui_plot = "0.31"
tray-icon = "0.19"
```

### 8.2 Architecture

Main window contains:
  - Left nav panel (Side navigation)
  - Content area (right) → each panel
  - Bottom OS banner

Rust's key module layout:

```
focusflow-ui/src
├── lib.rs → router
├── theme.rs (Java-theme emulation colors)
├── main_window.rs (creation, sizing, top-most toggle)         ├── system_tray.rs→ menu with toggle/hide/restart
├── components/              ├── side_bar.rs
│                              └── os_banner.rs
├── panels/                  ├── dashboard.rs
│                              ├ block_controls/...
│                              ...
                                                                            ... ...
├── floating_block_overlay  → { BlockNotice screen, blockingWhenLike.active}
```

### 8.3 Panel Features per Screen

| Panel | Submenu | Implements |
|---|---|---|
| Dashboard         | Start session / pause   | time tick, progress arc (egui custom paint) |
| Block controls | Add/edit blocked app, import preset, keyword panel | interactive list, dropdown pick |
| Nuclear mode | Activation, Arm deactivation, timed | checkbox, danger confirm dialog |
| Stats              | Charts (Plot), history, databases | plot panel |
| VPN Network | VPN check → toggle, scanner |
| Block defense  | Device config, kiosk mode, keyboard et | similar JVM screen |
| Linux setup         | Only if-is linux
  Linux Portion States |
| Settings   | startup → toggle            | egui preferences panel |

  ### 8.4 System Tray

 Uses `tray-icon` crate:

```rust
let icon=include "icon.ico" → load
let tray = TrayIconBuilder::new()
    .with_tooltip("FocusFlow")
    .with_menu(tray_menu)
    .on_menu_event(|app, event| {
        match event.id.as_ref() {
            "show" => sp.resize vista Window shown},
            "exit" => kill switch fire,
            _ => ()
        }
    })
    .build()
```

  ### 8.5 Floating Block Overlay

**TLD**: Keep another low epoch window painted full-path inboard.

For each block → display version by the deprecated J V. → Missing point
represented UI full screen `Overlays`.

---

## 9. Phase 7: Linux Backend (Week 10–12)

The **linux content is basically already described in LINUX_PORT_PLAN.md** → the same for Rust:

### 9.1 Key differences over Windows

| Method | Implementation |
|--------|----------------|
|Window titles| Poll xdotool, set up xia |,' give wayland watcher indicator| 
|Process list | Read OS/proc via `/proc/[pid]/` |
| Firewall | `iptables -A OUTPUT -j DROP -p tcp --dport <port>` |
| Keyboard hook  | Wait for X XInput2 `XI_Key` The event |
| InstalledApps | Parse /usr/share/applications/**.desktop |
| Icon | Look up `.desktop` file → get Icon → xdg- (cache-pn-- gake) |
| Startup | Set up systemd user service in ~/.config/systemd |

### 9.2 Works Wit Mac → @Most abstracted via OsBackendImpl for each OS

---

## 10. Phase 8: macOS Backend (Week 12–14)

### 10.1 Differences from Windows

| Method | Apple macOS |
|----------|-------------|
| Foreground Window | NSWorkspace.shared.foregroundApplication() → localized name, path |
| ProcessList | `sysctl` or directly use rust library: `procfs` or `sysinfo` |
| Keyboard Hook | CGEvent.tapCreate keyboard type listener (requires accessibility → user grant) |
| Firewall | launchctl load /Library sandbox Smart PARAM |
| Icon extraction | app.bundle NSImage iconForFile via sips |
| Launch Agent | Launchd agents → ~/Library/LaunchAgents/com.FocusFlow.plist |

**Note for user:** For macOS keyboard hook: You must accept "Universal Key Press Notice" from Settings＞Accessibility in order for hook to work, and we must show visual guide if accessibility is not granted.

---

## 11. Phase 9: Recovery Tool & Watchdog (Week 13–14)

### 11.1 Recovery Tool

Complete implementation as a separate CLI binary per the master doc:

```
Commands:
├── --disarm-nuclear
├── --clear-firewall
├── --clear-hosts
├── --uninstall
├── --all
└── --dry-run
```

All test by integration test.

### 11.2 Watchdog Management

Same as JVM: when main binary start → backup watchdog process → heartbeats via named pipe (Win) / Unix socket (Linux) / AF_LOCAL (macOS).

---

## 12. Phase 10: CI/CD, Packaging, Shipping (Week 13–16)

### 12.1 GitHub Actions Workflows

- `build-windows.yml` — Exe + MSI (via wix) + EXE zip  
- `build-linux.yml` — AppImage + `dpkg»+`rpm + tar.xz  
- `build-macos.yml` — .dmg + .app bundle + (signing)  
- `test.yml` — Clippy + test + coverage (all crates on all OSes)
- `release.yml` — Rust binary upload + store upload

### 12.2 Packaging

| Platform | Format |
|-----------|---------|
| Windows | WiX MSI (+exe standalone) |
| Linux   | AppImage (best) + .deb |
| macOS    | .dmg (be signed) |

Each CRT must be signed with appropriate branding, metadata, icon.

### 12.3 Auto-update

Consider `signpost-update` via the focusflow via to verify that the hash.

---

## Completion Checklist (Final Verification)

- [ ] Systemic system is an application for `Focus Flow` running on Windows, Linux, and macOS natively (identical binary output)
- [ ] Binary size ≤ 35 MB
- [ ] Cold start ≤ 500ms
- [ ] All JVM features covered
- [ ] Undoes kill switch works
- [ ] Kills work and restore clear rule
- [ ] Recovery tool tested on all 3 OSes
- [ ] Midnight migration from test from JVM JSON export path

---

**Next Document:** `RUST_PORT_ENFORCEMENT_DEEP_DIVE.md` — Detailed code patterns & the exact Win API migration surf from Kotlin→Rust line-by-rust with annotations.