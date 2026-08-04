# Linux Compliance — What to Remove & Replace

## General Rules: What Doesn't Belong in a Linux App

| Category | Should NOT have | Linux alternative |
|----------|----------------|-------------------|
| **Registry** | `Advapi32`, `WinReg`, `reg.exe`, Group Policy keys | `/etc` files, `dconf`/`gsettings`, XDG config dirs |
| **Win32 APIs** | `User32`, `Kernel32`, `Psapi`, JNA `StdCallLibrary` | `ProcessHandle`, X11/XCB (`xdotool`, `wmctrl`), `/proc` |
| **Process killing** | `taskkill /F /PID`, `taskkill /IM *.exe` | `ProcessHandle.destroy()`, `kill -9 <pid>` |
| **Firewall** | `netsh advfirewall`, `New-NetFirewallRule` (PowerShell) | `iptables`/`nftables`/`firewalld` |
| **Taskbar control** | `FindWindow("Shell_TrayWnd")`, `ShowWindow` | `xdotool`, `wmctrl`, DE-specific DBUS |
| **Startup/autorun** | Task Scheduler (`schtasks`), `HKCU\Run` registry | `~/.config/autostart/*.desktop`, `systemd --user` |
| **Keyboard hooks** | `WH_KEYBOARD_LL`, `SetWindowsHookEx` | `evdev`/`libinput`, `XGrabKey` (X11) |
| **App discovery** | Uninstall registry, `.lnk`/`.exe` scanning | `/usr/share/applications/*.desktop`, `~/.local/share/applications` |
| **Icons** | `Shell32.ExtractIconEx`, `.ico` files | XDG icon theme, `.desktop` `Icon=` field, `.png`/`.svg` |
| **Paths** | `%APPDATA%`, `%LOCALAPPDATA%`, `C:\...` | `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `~/.config/`, `~/.local/share/` |
| **VPN detection** | `.exe` process names (nordvpn.exe, protonvpn.exe) | Binary names without extension (`nordvpnd`, `protonvpn`) |
| **PowerShell** | Any `pwsh`/`powershell` shell-out | `bash`, `sh`, native Java APIs |

---

## Our Codebase — What to Remove / Replace

### 🗑 Remove Entirely (no Linux equivalent needed)

| File | What | Why |
|------|------|-----|
| `enforcement/WinEventHook.kt` | `WinHookUser32`, `WinEventProc`, `startWindows`, `stopWindows` | Win32 message-pump hook — Linux path already exists in same file |
| `enforcement/RegistryLockdown.kt` | Entire class | Windows Group Policy lockdown has no Linux concept; already no-ops on Linux |
| `enforcement/GlobalKeyboardHook.kt` | Entire class | `WH_KEYBOARD_LL`/user32 — no portable Linux equivalent; `XGrabKey` would need a full rewrite |
| `services/FocusLauncherService.kt` | `emergencyRestoreWindows()`, `FindWindow`/`ShowWindow` helpers | Shell_TrayWnd is Windows-only |
| `enforcement/WinApiBindings.kt` | `User32Extra`, `Psapi`, `getForegroundProcessNameWindows`, `isRunningAsAdmin` | Win32/JNA — Linux paths exist elsewhere in the same file |

### 🔄 Replace (Linux alternative exists or must be built)

| File | What | Replace with |
|------|------|--------------|
| `enforcement/WindowsStartupManager.kt` | Registry/`reg.exe` startup registration | XDG autostart `.desktop` file in `~/.config/autostart/` |
| `enforcement/WatchdogInstaller.kt` | `installTaskbarGuard`, `schtasks` methods, call to `WindowsStartupManager.resolveExePath()` on Linux | Use `ProcessHandle.current()` or `/proc/self/exe` for path; systemd user timer already implemented |
| `enforcement/NetworkBlocker.kt` | All `netsh`/PowerShell firewall functions, `syncFromFirewall()` | `iptables -A OUTPUT`/`nftables` rules (needs `pkexec` or `sudo`) |
| `enforcement/NuclearMode.kt` | Windows Firewall enforcement/cleanup thread | Linux firewall backend (iptables/nftables) with same enable/disable interface |
| `enforcement/InstalledAppsScanner.kt` | Windows uninstall-registry + `.exe`/`.lnk` scanner | `.desktop` file scanner already stubbed in same file — complete it |
| `enforcement/AppIconExtractor.kt` | Shell32 `.ico` extraction, Windows executable icon path | XDG icon theme lookup + `.desktop` `Icon=` field |
| `enforcement/ProcessMonitor.kt` | `.exe` suffix normalisation, Windows foreground-window assumptions | X11 `_NET_ACTIVE_WINDOW` via `xdotool getactivewindow getwindowpid`; Wayland: `wlr-foreign-toplevel` |
| `enforcement/VpnBlocker.kt` | `windowsVpnProcesses` list (`.exe` names) | Linux VPN daemon names: `nordvpnd`, `protonvpn`, `openvpn`, `mullvad-daemon` |
| `Main.kt` | Unconditional `RegistryLockdown.disable()`, `WatchdogInstaller.install()`, `NetworkBlocker.syncFromFirewall()` at startup | Wrap each in `if (IS_LINUX)` / `if (IS_WINDOWS)` guards; Linux equivalents TBD |

### ✅ Already Guarded — Low Risk (keep, no action needed now)

- `HostsBlocker.kt` — dual Windows/Linux paths, both implemented
- `WinEventHook.kt` Linux polling branch — active on Linux
- `InstalledAppsScanner.kt` Linux `.desktop` scanner — returns early on Linux
- `WinApiBindings.kt` Linux kill path (`ProcessHandle`) — active on Linux
- `WatchdogInstaller.kt` systemd timer branch — implemented, just broken by wrong exe-path call

---

## Priority Order for Cleanup

1. **`Main.kt`** — remove unconditional Windows startup calls (5-min fix, high blast radius if left)
2. **`WatchdogInstaller.kt`** — fix `resolveExePath()` → `ProcessHandle`/`/proc/self/exe`
3. **`RegistryLockdown.kt`** — delete file or stub it out entirely
4. **`NetworkBlocker.kt`** — add real iptables/nftables Linux backend
5. **`WindowsStartupManager.kt`** — extract Linux XDG autostart into its own class
6. Everything else in the Replace table above
