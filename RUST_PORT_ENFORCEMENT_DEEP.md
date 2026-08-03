# FocusFlow → Rust: Enforcement Engine Deep Dive

> **JVM Reference Files:** `ProcessMonitor.kt`, `NuclearMode.kt`, `NetworkBlocker.kt`, `WinApiBindings.kt`, `WinEventHook.kt`  
> **Companion to:** `FOCUSFLOW_RUST_PORT_MASTER.md`

---

## 1. Process Monitor — The Core Loop

### 1.1 What It Does (JVM Behavior)

The `ProcessMonitor.kt` runs a polling loop every 500ms. Each tick:
1. Gets the foreground window title and executable path
2. Checks if the window title contains any blocked keyword (substring match, case-insensitive)
3. Checks if the executable path matches any blocked path
4. If matched, accumulates "seen" time for that window
5. After 3 seconds of accumulated time, kills the process and logs to DB

### 1.2 Rust Implementation

```rust
// focusflow-enforcer/src/process_monitor.rs
use std::collections::{HashMap, HashSet};
use std::time::{Duration, Instant};
use focusflow_os::OsBackend;
use focusflow_db::Database;

pub struct ProcessMonitor {
    /// Apps that have been seen and are accumulating toward kill threshold
    accumulated_windows: HashMap<String, WindowAccumulator>,
    /// Keywords to match in window titles (like "porn", "tomb", etc)
    blocked_keywords: HashSet<String>,
    /// Full exe paths to block
    blocked_paths: HashSet<String>,
    /// App exclusion flag — processes to NOT kill even if matched
    safe_list: HashSet<String>,
}

struct WindowAccumulator {
    first_seen: Instant,
    title: String, path: String,
    seconds_seen: f64,
}

impl ProcessMonitor {
    pub fn tick(&mut self, os: &dyn OsBackend, db: &Database) -> Result<TickResult> {
        let fg_title = os.foreground_window_title()?;
        let fg_path = os.foreground_window_path()?;

        // Check keyword blocking
        let keyword_match = self.match_block_keyword(&fg_title);

        // Check exact path blocking
        let path_match = self.match_blocked_path(&fg_path);

        if keyword_match || path_match {
            return self.handle_blocked_window(&fg_title, &fg_path, os, db);
        }

        // Window changed → reset accumulator
        Ok(TickResult::Clean)
    }

    fn handle_blocked_window(&mut self, title: &str, path: &str, os: &dyn OsBackend, db: &Database) -> Result<TickResult> {
        let acc = self.accumulated_windows.entry(path.to_string()).or_insert_with(|| {
            WindowAccumulator {
                first_seen: Instant::now(),
                title: title.to_string(),
                path: path.to_string(),
                seconds_accumulated: 0.0,
            }
        });

        acc.seconds_accumulated += 0.5; // 500ms tick interval
        if acc..seconds_accumulated >= 3.0 {
            // Kill the window
            os.kill_window_by_path(&acc.path)?;
            // Log to database
            db_.insert_temptation_log(&acc.title, &acc.path)?;
            self.accumulated_windows.remove(path);
            return Ok(TickResult::Killed { path: path.to_string(), title: title.to_string() });
        }

        Ok(TickResult::Accumulating { path: path.to_string(), remaining: 3.0 - acc..seconds_accumulated })
    }
}
```

### 1.3 Keyword Matching (Exact JVM Logic)

```rust
fn match_blocked_keyword(&self, window_title: &str) -> bool {
    let lower = window_title.to_lowercase();
    self.blocked_keywords.iter().any(|kw| lower.contains(&kw.to_lowercase()))
}
```

### 1.4 Path Matching

```rust
fn match_blocked_path(&self, path: &str) -> bool {
    let expanded_paths = expand_process_path(path);
    self.blocked_paths.iter().any(|b| expanded_paths.iter().any(|e| e.contains(b)))
}
```

---

## 2. Nuclear Mode — Three-Layer Escape Prevention

### 2.1 JVM Behavior (from NuclearMode.kt lines 33-100)

**Layer 1 — Detect:** One `tasklist /FO CSV /NH` call captures every running process name. Filter against `escapeProcesses` in memory.

**Layer 2 — Kill:** One `taskkill /F /IM proc1 /IM proc2 ...` call terminates all found escape processes.

**Layer 3 — Block:** Firewall rules block even renamed executables.

### 2.2 Escape Process List (Complete JVM → Rust mapping)

The exact set from `NuclearMode.kt` lines 36-80:

```rust
// focusflow-enforcer/src/nuclear_mode.rs

const WINDOWS_ESCAPE_PROCESSES: &[&str] = &[
    // Task management / process viewers
    "taskmgr.exe", "procexp.exe", "procexp64.exe", "procmon.exe", "procmon64.exe",
    "processhacker.exe", "processhacker2.exe", "systemexplorer.exe",
    "perfmon.exe", "resmon.exe",
    // Registry / config editors
    "regedit.exe", "regedt32.exe", "msconfig.exe",
    // Shells / terminals
    "cmd.exe", "powershell.exe", "powershell_ise.exe", "pwsh.exe",
    "wt.exe", "mintty.exe", "conemu64.exe", "conemu.exe", "cmder.exe",
    "bash.exe", "zsh.exe", "sh.exe",
    "ubuntu.exe", "debian.exe", "kali.exe", "wsl.exe", "wslhost.exe",
    // MMC snap-ins / admin tools
    "mmc.exe", "eventvwr.exe", "compmgmt.msc",
    "wscript.exe", "cscript.exe", "mshta.exe", "wmic.exe", "winrm.exe",
    // Installers
    "winget.exe", "msiexec.exe",
];

const LINUX_ESCAPE_PROCESSES: &[&str] = &[
   // Terminals
   "gnome-terminal", "gnome-terminal-server", "konsole", "xfce4-terminal",
   "xterm", "uxterm", "terminator", "terminology", "mate-terminal",
   "lxterminal", "qterminal", "tilix", "alacritty", "kitty",
   "sakura", "tilda", "guake", "rxvt",
   // Shells
   "bash", "zsh", "sh", "dash", "fish", "ksh", "csh", "tcsh",
   // System monitors
   "gnome-system-monitor", "ksysguard", "htop", "btop", "top", "glances",
   // Config editors
   "dconf-editor", "gconf-editor",
   // Task management / run dialogs
   "procman", "lxtask", "gnome-run", "krunner", "xfce4-appfinder",
   // Package managers
    "gnome-software", "discover", "synaptic", "aptitude",
];
```

### 2.3 Known Escape Path Suffixes (Layer 3)

From `NuclearMode.kt` lines 96-110:

```rust
const KNOWN_ESCAPE_PATHS: &[&str] = &[
    "\\windows\\system32\\taskmgr.exe",
    "\\windows\\syswow64\\taskmgr.exe",
    "\\windows\\regedit.exe",
    "\\windows\\system32\\regedt32.exe",
    "\\windows\\system32\\cmd.exe",
    "\\windows\\system32\\powershell.exe",
    "\\windows\\system32\\wscript.exe",
    "\\windows\\system32\\mshta.exe",
    "\\windows\\system32\\mmc.exe",
    "\\windows\\system32\\msconfig.exe",
    "\\windows\\system32\\perfmon.exe",
    "\\windows\\system32\\resmon.exe",
    "\\windows\\system32\\eventvwr.exe",
];
```

### 2.3 Nuclear Mode Core Implementation

```rust
pub struct NuclearMode {
    active: AtomicBool,
    escape_counts: Mutex<HashMap<String, u32>>,
    known_paths: HashSet<String>,
}

impl NuclearMode {
    pub fn activate(&self) {
        self.active.store(true, Ordering::Release);
    }

    pub fn disarm(&self) -> Result<()> {
        self.active.store(false, Ordering::Release);
        // Remove all firewall rules added during nuclear mode
        // Clear escape counts
        Ok(())
    }

    pub fn scan_and_kill(&self, os: &dyn OsBackend) -> Result<NuclearTickResult> {
        if !self.active.load(Ordering::Acquire) {
            return Ok(NuclearTickResult::Inactive);
        }

        // Layer 1: Detect
        let processes = os.running_processes()?;
        let escapes: Vec<&ProcessInfo> = processes.iter()
            .filter(|p| self.is_escape(p))
            .collect();

        if escapes.is_empty() {
            return Ok(NuclearTickResult::Clean);
        }

        // Layer 2: Kill
        for proc in &escapes {
            os..kill_process_by_name(&proc.process)?;   // SIGKILL or TerminateProcess
            // Increment escape counter (write to DB every 5 hits)
        }

        // Layer 3: Block firewall rules for known escape paths
        os.block_network_rules(&known_escape_paths)?;

        Ok(NuclearTickResult::EscapesKilled { count: escapes.len() as u32 })
    }

    fn is_escape(&self, proc: &ProcessInfo) -> bool {
        let name_lower = proc.name.to_lowercase();
        // Match by process name
        if ESCAPE_LIST.iter().any(|e| name_lower == *e) {
            return true;
        }
        // Match by known path suffix (renamed check)
        let path_lower = proc.path.to_lowercase();
        self.known_paths.iter().any(|s| path_lower.ends_with(s))
    }

}
```

### Escape Tracking with Cooldown

```rust
// Every 5hits DB write — saves DB cycles but keeps stats
let mut counts = self.escape_counts.lock().unwrap();
let entry = counts.entry(proc_name).or_insert(0);
*entry += 1;
if *entry % 5 == 0 {
    db.upsert_escape_count(proc_name, *entry)?;
}
```

---

## 4. Network Blocker — WFP Firewall Rules (Windows)

### 4.1 JVM Behavior

`NetworkBlocker.kt` uses COM (JNI) to call Windows Filtering Platform API:
- `INetFwPolicy2` to get firewall policy
- Add/create outbound block rules per executable path
- Remove rules on deactivation

### 4.2 Rust Implementation (Windows using windows-rs)

```rust
// focusflow-os/src/windows/firewall.rs
use windows::Win32::Networking::WinInet::*;
use windows::Win32::Security::*;

pub fn add_outgoing_block_rule(path: &str) -> Result<()> {
    unsafe {
        let fw_policy: INetFwPolicy2 = CoCreateInstance(&NetFwPolicy2 as *const _, None, CLSCTX_ALL)?;

        let rule: INetFwRule = CoCreateInstance(&NetFwRule as *const _, None, CLSCTX_ALL)?;
        rule.SetName(&format!("FocusFlow Block: {}", path))?;
        rule.SetApplicationName(path)?;
        rule.SetDirection(NET_FW_RULE_DIR_OUT)?;
        rule.SetAction(NET_FW_ACTION_BLOCK)?;
        rule.SetEnabled(true=TRUE)?;

        fw_policy..Rules()?.Add(rule)?;
        Ok(())
    }
}

pub fn remove_all_focusflow_rules() -> Result<u32> {
    unsafe {
        let fw_policy: INetFwPolicy2 = ...;
        let rules = fw_policy..Rules()?;
        let mut removed = 0;

        for r in rules.iter() {
            if r.Name()?.starts_with("FocusFlow Block:") {
                rules.Remove(r.Name()?)?;
                removed += 1;
            }
        }
        Ok(removed)
    }
}
```

---

## 5. VPN Blocker — Detection Patterns

### 5.1 JVM Approach

`VpnBlocker.kt` checks:
- Network connections: `netstat -ano` parsed output
- Known VPN process names & paths
- TAP/TUN adapters
- Linux: scans `/dev/tun*`, checks `iptables` NAT rules


### 5.2 Rust Implementation Pattern

```rust
// focusflow-enforcer/src/vpn_blocker.rs
pub struct VpnBlocker {
    known_vpn_processes: HashSet<String>,
    allowed_vpn: bool,  // user setting to bypass VPN block
}

impl VpnBlocker {
    pub fn scan(&self, os: &dyn OsBackend) -> Result<Vec<VpnInfo>> {
        let connections = os.scan_vpn_connections()?;
        let mut detected: Vec<VpnInfo> = vec![];

        for conn in connections {
            if self.known_vpn_processes.contains(&conn.process_name) {
                detected.push(VpnInfo {
                    process_name: conn.process_name,
                    pid: conn.pid,
                    remote_addr: conn.remote_address,
                });
            }
        }
        Ok(detected)
    }

    pub fn block(&self, vpn: &VpnInfo) -> Result<()> {
        if self.allowed_vpn { return Ok(()); }
        os.kill_process_by_pid(vpn.pid)?;
        // Optionally block firewall rule for VPN exe
        Os_backend.add_out_bounds_block_rules(&[vpn.process_path].to_file()))?;
        Ok(())
    } 
}
```

---

## 6. Keyboard Hook — Global Key Interception

### 6.1 Windows: SetWindowsHookExW

```rust
// focusflow-os/src/windows/keyboard_hook.rs
use windows::Win32::System::*;

#[derive(Debug)]
pub struct KeyEvent {
    pub vk_code: u32,
    pub pressed: bool,
    pub alt_down: bool,
    pub ctrl_down: bool,
}

pub fn install_hook(callback: Box<dyn Fn(KeyEvent) + Send + 'static>) -> Result<HookHandle> {
    let hook_proc = HHOOK::default();

    unsafe {
        let module = HINSTANCE::default(); // current module
        let hhook = SetWindowsHookExW(
            WH_KEYBOARD_LL,
            Some(keyboard_proc_fn),
            module,
            0, // global
        )?;

        // On hook proc callback: unmarshal KBDLLHOOKSTRUCT → KeyEvent → callback

        Ok(HookHandle { handle: hhook })
    }
}

/// List of keys to block when keyboard hook is active
const BLOCKED_KEYS: &[&str] = &[
    "Ctrl+Alt+Del",  "Alt+Tab", "Win+Tab", "Win+D", "Win+M",
    "Ctrl+Esc", "Win+E", "Win+R", "Ctrl+Shift+Esc",
    "Alt+F4" (focus on our own window handle), Vol Up, Vol, Mute
];
```

### 6.2 Linux: XInput2 (X11) hook

```rust
// focusflow-os/src/linux/keyboard_hook.rs
// Uses xcb-xkb (X11) or native Wayland with Xdg-desktop-portal
```

### 6.3 macOS: CGEventTap

```rust
// focusflow-os/src/macos/keyboard_hook.rs
// Uses CGEvent→TapCreate and system accessibility permission
```

---

## 7. Windows Event Hook — Foreground Detection

### 7.1 JVM → Rust Mapping

```kotlin
// WinEventHook.kt
user32.SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND, ...)
```

```rust
// focusflow-os/src/windows/event_hook.rs
use windows::Win32::Automation::UI::*;
use windows::Win32::System_EventHook::*;

fn install_foreground_hook() -> Result<HWINEVENTHOOK> {
    let hook: HWINEVENTHOOK = SetWinEventHook(
        EVENT_SYSTEM_FOREGROUND,
        EVENT_SYSTEM_FOREGROUND,
        Some(h_wineventproc),
        ),
        0, // all processes
        0,  // for existing threads
        WINEVENT_OUTOFCONTEXT,
    );

    Ok(hook)
}
```

---

## 8. Installed Apps Scanner

### 8.1 Windows: Registry \ Start Menu scan

```rust
// focusflow-os/src/windows/installed_apps.rs
// Read:
// - HKEY_LOCAL_MACHINE\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\
// - HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\
// - %AppData%\\Microsoft\\Windows\\Start Menu\\Programs\\*.lnk
```

### 8.2 Linux: `.desktop` file scan

```rust
// focusflow-os/src/linux/installed_apps.rs
// Read:
// - /usr/share/applications/*.desktop
// - ~/.local/share/applications/*.desktop
// Parse Name, Exec, Icon, Categories, etc from .desktop
```

### 8.3 macOS: `.app` scanning

```rust
// focusflow-os/src/macos/installed_apps.rs
// Read:
// /Applications/*.app (and ~/Applications)
// via NSDirectory enumerator and CFBundleInfo
```

---

## 9. App Icon Extraction

### 9.1 Windows: ExtractIconEx

```rust
// focusflow-os/src/windows/icon_extractor.rs
use windows::Win32::UI::Shell::*;

pub fn extract_icon(exe_path: &str, size: u32) -> Result<Vec<u8>> {
    let mut large_icon = HICON::default();
    let mut small_icon = HICON::default();
    unsafe {
        ExtractIconEx(exe_path, 0, &mut large_icon, &mut small_icon, 1);
        // Convert HICON→Bitmap→RGBA Vec<u8>
    }
}
```

**Linux:** Look up icon via `.desktop` → XDG icon cache or fallback.  
**macOS:** `[NSImage iconForFile:appPath size:size]` or fallback to `png`.

---

## 10. Startup Manager & Watchdog

### 10.1 Windows: Registry HKCU...\Run

```rust
// focusflow-os/src/windows/startup_manager.rs
use windows::Win32::Registry::*;

pub fn register_startup(enabled: bool) -> Result<()> {
    let exe_path = std::env::current_exe()?;
    let key = HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
    if enabled {
        write_registry("FocusFlow", exe_path)
    } else {
        delete_registry_value("FocusFlow")
    }
}
```

### 10.2 Linux: systemd User `~/.config/systemd/user/focusflow.service`

### 10.3 macOS: LaunchAgent `~/Library/LaunchAgents/com.focusflow.plist`

### 10.4 Watchdog: Heartbeat Named Pipe / Unix Socket

```rust
// Two-process architecture (same binary):
// MainFocusflow starts Watchdog subprocess as child
// Watchdog reads heartbeat messages from named pipe
// If heartbeat fails for >5 seconds → restart main.
// Graceful shutdown sends "exit" to both.
```

This can use `phyber_tasks::Command` on all platforms.

---

## Summary: JVM→Rust Enforcement Migration Checklist

- [ ] Process enumeration code (Win: CreateToolhelp32Snapshot, Linux: /proc, macOS: sysctl)
- [ ] Process kill code (TerminateProcess, sys::Signal, kill)
- [ ] Get Foreground window title per OS
- [ ] Foreground window executable path
- [ ] Keyword blocking (title contains match)
- [ ] Path blocking (exeCheck)
- [ ] Accumulation timer (3 sec before kill)
- [ ] Nuclear mode escape-process list (full set from Kotlin)
- [ ] Nuclear known-path suffix matching
- [ ] Firewall rule add/remove via INetFwPolicy2 (Win)
- [ ] Firewall iptables (Linux)
- [ ] Firewall pf rules (macOS)
- [ ] VPN detection scan
- [ ] Keyboard global hook (Win: SetWindowsHookExW, Linux: InputMultiPrototype, macOS: CGEvent)
- [ ] Installed apps enumeration
- [ ] App icon extraction
- [ ] Startup registration per OS
- [ ] Watchdog heartbeat

---

**Next Document:** `RUST_PORT_UI_MIGRATION.md` — Compose Desktop→egui panel-by-panel migration details.