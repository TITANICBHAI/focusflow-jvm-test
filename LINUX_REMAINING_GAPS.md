# Linux Remaining Gaps — 3 Items

The app is Linux-ready. Core enforcement (process kill, hosts blocking, focus sessions,
keyword detection, foreground-window polling via xdotool, Nuclear Mode escape lists)
is fully implemented and guarded. The progress tracker in `LINUX_PORT_PROGRESS.md` is
stale — all those `[ ]` items are already done in the code.

Only three small gaps remain:

---

## 1. `Main.kt` — Two unconditional Windows calls at startup

**Files:** `src/main/kotlin/com/focusflow/Main.kt` (lines ~34, ~84)

```kotlin
// Line ~34 — runs on Linux even though it's a no-op
try { RegistryLockdown.disable() } catch (_: Throwable) {}

// Line ~84 — runs on Linux, syncs nothing (no Windows Firewall)
NetworkBlocker.syncFromFirewall()
```

**Fix:** wrap both in `if (IS_WINDOWS)`:

```kotlin
if (IS_WINDOWS) try { RegistryLockdown.disable() } catch (_: Throwable) {}
// ...
if (IS_WINDOWS) NetworkBlocker.syncFromFirewall()
```

Both callees already no-op internally on Linux, so this is cosmetic/correctness only.
No runtime crash risk.

---

## 2. `WatchdogInstaller.kt` — Linux path calls Windows registry code for exe path

**File:** `src/main/kotlin/com/focusflow/enforcement/WatchdogInstaller.kt` (~line 70)

```kotlin
// Inside installLinuxWatchdog() — wrong on Linux
val exePath = WindowsStartupManager.resolveExePath()  // hits Advapi32 registry
```

**Fix:** use the Linux-native process path instead:

```kotlin
val exePath = ProcessHandle.current().info().command().orElse(null)
    ?: "/proc/self/exe".let { java.nio.file.Files.readSymbolicLink(java.nio.file.Path.of(it)).toString() }
    ?: return  // can't determine path, skip watchdog silently
```

The systemd user timer unit itself is already correctly implemented below this line.
This one call is the only reason the Linux watchdog silently does nothing.

---

## 3. `NetworkBlocker.kt` — Linux branch is in-memory only (no real iptables)

**File:** `src/main/kotlin/com/focusflow/enforcement/NetworkBlocker.kt`

The Linux branch records blocked domains in a `Set` but never writes actual firewall rules.
Hosts-file blocking (`HostsBlocker.kt`) **does** work on Linux and covers most use cases.
Network-layer blocking (firewall) is not enforced on Linux.

**Fix (when needed):**

```bash
# Block outbound to domain (requires pkexec / sudo)
pkexec iptables -A OUTPUT -m string --string "example.com" --algo bm -j REJECT
# or resolve to IP first, then:
pkexec iptables -A OUTPUT -d <ip> -j REJECT
```

Kotlin wrapper skeleton:

```kotlin
private fun blockLinux(domain: String) {
    if (!isLinux) return
    val resolved = resolveToIps(domain)   // InetAddress.getAllByName()
    resolved.forEach { ip ->
        Runtime.getRuntime().exec(arrayOf("pkexec", "iptables", "-A", "OUTPUT",
            "-d", ip.hostAddress, "-j", "REJECT"))
    }
}
```

**Note:** `HostsBlocker` already handles the common case. This gap only matters when a
determined user edits `/etc/hosts` manually to bypass blocks.

---

## Summary

| # | File | Risk without fix | Effort |
|---|------|-----------------|--------|
| 1 | `Main.kt` | None (both calls no-op) | 2 lines |
| 2 | `WatchdogInstaller.kt` | Watchdog never installs on Linux | ~5 lines |
| 3 | `NetworkBlocker.kt` | No firewall blocking on Linux (hosts-file still works) | ~30 lines |
