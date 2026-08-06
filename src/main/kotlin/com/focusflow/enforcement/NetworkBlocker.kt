package com.focusflow.enforcement

/**
 * NetworkBlocker — three-layer Windows Firewall enforcement
 *
 * Layer 1 — Resolve exe path:
 *   First tries `Get-Process` (process must be running). If the process is not
 *   currently running, falls back to a directory search across the five most
 *   common Windows install locations (Program Files, ProgramFiles(x86), AppData,
 *   LocalAppData, System32). Resolved paths are cached so subsequent calls skip
 *   the search entirely.
 *
 * Layer 2 — Apply + verify:
 *   Creates the outbound-deny firewall rule via `New-NetFirewallRule`, then
 *   immediately calls `Get-NetFirewallRule` to confirm the rule exists and is
 *   enabled. Only marks the rule as active if verification passes.
 *
 * Layer 3 — Sync from firewall state on startup:
 *   [syncFromFirewall] reads all existing FocusFlow rules from the Windows
 *   Firewall and populates [activeRules]. This survives app restarts — rules
 *   created in a previous session are recognised and not double-applied.
 */
object NetworkBlocker {

    private const val RULE_PREFIX = "FocusFlow_Block_"

    // iptables comment tag — used to identify and remove our rules on Linux
    private const val IPTABLES_TAG = "focusflow"

    /** Tracks which process names have an active firewall rule. */
    private val activeRules: MutableSet<String> =
        java.util.Collections.synchronizedSet(mutableSetOf())

    /**
     * Cache: baseName (no .exe, lowercase) → resolved absolute exe path.
     * Avoids repeated directory searches for the same process.
     */
    private val resolvedPaths = java.util.concurrent.ConcurrentHashMap<String, String>()

    /**
     * Processes for which we have a pending rule (path not yet resolved).
     * ProcessMonitor retries these on the next block cycle.
     */
    private val pendingRules: MutableSet<String> =
        java.util.Collections.synchronizedSet(mutableSetOf())

    /**
     * Linux: per-process set of IPs that have been blocked via iptables.
     * Keyed by lowercase process name.  Used to remove the exact same rules
     * on removeRule() / removeAllRules() without a costly iptables -L parse.
     */
    private val linuxBlockedIps =
        java.util.concurrent.ConcurrentHashMap<String, MutableSet<String>>()

    // ── Layer 1: Path resolution ─────────────────────────────────────────────

    /**
     * Resolves the absolute exe path for [baseName] (process name without ".exe").
     *
     * Resolution order:
     *   1. In-memory cache (instant)
     *   2. Running process via Get-Process (most accurate)
     *   3. Common install directories (handles pre-emptive blocks before process runs)
     */
    private fun resolveExePath(baseName: String): String? {
        // Fast path — already resolved; ConcurrentHashMap read is lock-free.
        resolvedPaths[baseName]?.let { return it }

        // Serialise resolution per map instance.
        // Without this guard two concurrent addRule("chrome.exe") calls both see a
        // cache miss and both spawn an expensive PowerShell process for the same name.
        // The synchronized block is cheap: resolution is at most once-per-process-name,
        // so contention on this lock is negligible in practice.
        return synchronized(resolvedPaths) {
            // Re-read inside the lock — another thread may have resolved while we waited.
            resolvedPaths[baseName] ?: run {
                val resolved = resolveExePathUncached(baseName)
                // Only cache on success; null means the process isn't running yet.
                // Leaving it out of the cache lets retryPendingRules() try again later.
                if (resolved != null) resolvedPaths[baseName] = resolved
                resolved
            }
        }
    }

    private fun resolveExePathUncached(baseName: String): String? {
        // 2. Running process
        val fromProcess = runPowerShellAndRead(
            "(Get-Process -Name '$baseName' -ErrorAction SilentlyContinue " +
            "| Select-Object -First 1 -ExpandProperty Path)"
        )?.trim()?.takeIf { it.isNotBlank() && !it.equals("null", ignoreCase = true) }
        if (fromProcess != null) return fromProcess

        // 3. Directory search — try bare exe name, then one level deep
        val searchRoots = listOfNotNull(
            System.getenv("ProgramFiles"),
            System.getenv("ProgramFiles(x86)"),
            System.getenv("LOCALAPPDATA"),
            System.getenv("APPDATA"),
            "C:\\Windows\\System32",
            "C:\\Windows\\SysWOW64"
        )
        return searchRoots.firstNotNullOfOrNull { root ->
            val direct = java.io.File(root, "$baseName.exe")
            if (direct.exists()) return@firstNotNullOfOrNull direct.absolutePath
            java.io.File(root).listFiles()?.firstNotNullOfOrNull { sub ->
                val nested = java.io.File(sub, "$baseName.exe")
                if (nested.exists()) nested.absolutePath else null
            }
        }
    }

    // ── Layer 2: Apply + verify ──────────────────────────────────────────────

    /**
     * Block all outbound traffic for [processName] (e.g. "chrome.exe").
     *
     * Returns true  — rule created and verified.
     * Returns false — no admin, not Windows, or path could not be resolved
     *                 (rule is queued in [pendingRules] for retry).
     */
    fun addRule(processName: String): Boolean {
        if (isLinux) return addLinuxRule(processName)
        if (!isWindows || !isRunningAsAdmin()) return false

        val lower    = processName.lowercase()
        val baseName = processName.removeSuffix(".exe").trim()
        val ruleName = RULE_PREFIX + baseName

        if (activeRules.contains(lower)) return true   // Already applied

        val exePath = resolveExePath(baseName)
        if (exePath == null) {
            pendingRules.add(lower)
            return false
        }

        // Remove any stale rule with the same name before creating fresh
        runPowerShell(
            "Remove-NetFirewallRule -DisplayName '$ruleName' -ErrorAction SilentlyContinue"
        )

        runPowerShell("""
            New-NetFirewallRule `
                -DisplayName '$ruleName' `
                -Direction Outbound `
                -Action Block `
                -Program '$exePath' `
                -Enabled True `
                -ErrorAction SilentlyContinue | Out-Null
        """.trimIndent())

        // Verify the rule actually exists in the firewall
        val verified = verifyRuleExists(ruleName)
        if (verified) {
            activeRules.add(lower)
            pendingRules.remove(lower)
        }
        return verified
    }

    // ── Linux iptables support ──────────────────────────────────────────────

    /**
     * Block outbound traffic for [processName] on Linux.
     *
     * Strategy (layered, all run on a background thread so the enforcement
     * loop is never stalled):
     *   1. Register intent immediately — same-session double-blocks are skipped.
     *   2. Find all running PIDs for this process name via ProcessHandle.
     *   3. For each PID read /proc/<pid>/net/tcp[6] to collect ESTABLISHED
     *      remote IPs (loopback and private ranges are skipped).
     *   4. Add an iptables OUTPUT REJECT rule per IP, tagged with a comment
     *      so rules can be identified and removed cleanly on session end.
     *   5. Domain-level blocking via HostsBlocker remains the primary layer;
     *      this adds a second layer against /etc/hosts edits or DoH bypasses.
     */
    private fun addLinuxRule(processName: String): Boolean {
        val lower = processName.lowercase()
        if (activeRules.contains(lower)) return true
        activeRules.add(lower)
        pendingRules.remove(lower)

        Thread({
            val blocked = linuxBlockedIps.getOrPut(lower) {
                java.util.Collections.synchronizedSet(mutableSetOf())
            }
            // Locate all running PIDs whose executable basename matches
            val pids = ProcessHandle.allProcesses()
                .filter { ph ->
                    val cmd  = ph.info().command().orElse("")
                    val base = cmd.substringAfterLast('/')
                    base.equals(lower, ignoreCase = true) ||
                    base.equals(lower.removeSuffix(".exe"), ignoreCase = true) ||
                    base.equals(processName, ignoreCase = true)
                }
                .map { it.pid() }
                .toList()

            // Collect established remote IPs from /proc/<pid>/net/tcp[6]
            val ips = mutableSetOf<String>()
            for (pid in pids) {
                ips += parseLinuxProcNetTcp(pid, "tcp")
                ips += parseLinuxProcNetTcp(pid, "tcp6")
            }

            // Add an iptables rule for each new IP
            for (ip in ips) {
                if (blocked.add(ip)) linuxIptablesExec("-A", ip, lower)
            }
        }, "FocusFlow-LinuxNetBlock-$lower").also { it.isDaemon = true }.start()

        return true
    }

    /**
     * Block outbound traffic to [domain] on Linux via iptables.
     * Resolves the domain to IPs first and inserts per-IP OUTPUT REJECT rules.
     * Requires pkexec (polkit) or root for privilege elevation.
     *
     * NOTE: HostsBlocker already covers the common case. This layer only adds
     * value against a user who edits /etc/hosts to bypass blocks.
     */
    private fun blockLinux(domain: String) {
        if (!isLinux) return
        try {
            val ips = java.net.InetAddress.getAllByName(domain)
            for (ip in ips) {
                linuxIptablesExec("-A", ip.hostAddress, domain)
            }
        } catch (_: Exception) {
            // Silently skip if pkexec is unavailable or resolution fails;
            // HostsBlocker remains the primary Linux blocking layer.
        }
    }

    // ── Linux helpers ───────────────────────────────────────────────────────

    /**
     * Parse /proc/[pid]/net/tcp or tcp6 and return remote IPs of ESTABLISHED
     * connections (state byte 01).  Loopback and unroutable addresses skipped.
     */
    private fun parseLinuxProcNetTcp(pid: Long, proto: String): Set<String> {
        return try {
            val f = java.io.File("/proc/$pid/net/$proto")
            if (!f.canRead()) return emptySet()
            f.readLines().drop(1)   // skip header
                .mapNotNull { line ->
                    val cols = line.trim().split(Regex("\\s+"))
                    if (cols.size < 4) return@mapNotNull null
                    if (cols[3] != "01") return@mapNotNull null    // ESTABLISHED only
                    val remoteHex = cols[2].split(":").firstOrNull() ?: return@mapNotNull null
                    if (proto == "tcp6") parseHexIpv6(remoteHex)
                    else                 parseHexIpv4(remoteHex)
                }
                .filterNot {
                    it.startsWith("127.") || it.startsWith("10.") ||
                    it.startsWith("192.168.") || it == "0.0.0.0" || it == "::1"
                }
                .toSet()
        } catch (_: Exception) { emptySet() }
    }

    /** Little-endian 8-char hex → dotted-decimal IPv4 (e.g. "0101A8C0" → "192.168.1.1"). */
    private fun parseHexIpv4(hex: String): String? {
        if (hex.length != 8) return null
        return try {
            val v = hex.toLong(16)
            "${v and 0xFF}.${v shr 8 and 0xFF}.${v shr 16 and 0xFF}.${v shr 24 and 0xFF}"
        } catch (_: Exception) { null }
    }

    /** Little-endian 32-char hex → abbreviated IPv6 string (best-effort). */
    private fun parseHexIpv6(hex: String): String? {
        if (hex.length != 32) return null
        return try {
            // /proc/net/tcp6 stores each 4-byte word in host (little-endian) byte order
            (0 until 8).joinToString(":") { i ->
                val word = hex.substring(i * 4, i * 4 + 4).toInt(16)
                val swapped = ((word and 0xFF) shl 8) or ((word shr 8) and 0xFF)
                swapped.toString(16)
            }
        } catch (_: Exception) { null }
    }

    /**
     * Run: (pkexec iptables | iptables) [op] OUTPUT -d [ip] -j REJECT
     *      -m comment --comment "focusflow-[tag]"
     * [op] is "-A" (append/add) or "-D" (delete).
     * Tries pkexec first; falls back to plain iptables (succeeds when already root).
     */
    private fun linuxIptablesExec(op: String, ip: String, tag: String) {
        val ruleArgs = arrayOf(
            op, "OUTPUT", "-d", ip, "-j", "REJECT",
            "-m", "comment", "--comment", "$IPTABLES_TAG-$tag"
        )
        for (prefix in listOf(arrayOf("pkexec", "iptables"), arrayOf("iptables"))) {
            try {
                val proc = Runtime.getRuntime().exec(prefix + ruleArgs)
                if (proc.waitFor() == 0) return
            } catch (_: Exception) {}
        }
    }

    private fun verifyRuleExists(ruleName: String): Boolean {
        val count = runPowerShellAndRead(
            "(Get-NetFirewallRule -DisplayName '$ruleName' -ErrorAction SilentlyContinue " +
            "| Where-Object { \$_.Enabled -eq 'True' } | Measure-Object).Count"
        )?.trim()?.toIntOrNull() ?: return false
        return count > 0
    }

    /**
     * Remove the outbound-block rule for [processName].
     */
    fun removeRule(processName: String) {
        if (isLinux) {
            val lower = processName.lowercase()
            activeRules.remove(lower)
            pendingRules.remove(lower)
            // Remove the actual iptables rules we inserted for this process
            Thread({
                val ips = linuxBlockedIps.remove(lower) ?: return@Thread
                for (ip in ips) linuxIptablesExec("-D", ip, lower)
            }, "FocusFlow-LinuxNetUnblock-$lower").also { it.isDaemon = true }.start()
            return
        }
        if (!isWindows) return
        val baseName = processName.removeSuffix(".exe").trim()
        val ruleName = RULE_PREFIX + baseName
        runPowerShell(
            "Remove-NetFirewallRule -DisplayName '$ruleName' -ErrorAction SilentlyContinue"
        )
        activeRules.remove(processName.lowercase())
        pendingRules.remove(processName.lowercase())
    }

    /**
     * Remove every FocusFlow-created firewall rule. Call on app exit / session end.
     */
    fun removeAllRules() {
        if (isLinux) {
            val snapshot = linuxBlockedIps.entries.map { it.key to it.value.toSet() }
            activeRules.clear()
            pendingRules.clear()
            linuxBlockedIps.clear()
            Thread({
                for ((tag, ips) in snapshot) {
                    for (ip in ips) linuxIptablesExec("-D", ip, tag)
                }
            }, "FocusFlow-LinuxNetFlush").also { it.isDaemon = true }.start()
            return
        }
        if (!isWindows) return
        runPowerShell("""
            Get-NetFirewallRule |
            Where-Object { ${'$'}_.DisplayName -like '$RULE_PREFIX*' } |
            Remove-NetFirewallRule -ErrorAction SilentlyContinue
        """.trimIndent())
        activeRules.clear()
        pendingRules.clear()
    }

    // ── Layer 3: Sync from actual firewall state ──────────────────────────────

    /**
     * Reads all existing FocusFlow firewall rules from Windows and populates
     * [activeRules] accordingly. Call once at app startup so rules created in a
     * previous session are recognised without being re-applied.
     */
    fun syncFromFirewall() {
        if (isLinux) {
            // Re-read existing focusflow-tagged iptables OUTPUT rules and
            // populate activeRules so a restarted session recognises prior blocks.
            try {
                val proc = Runtime.getRuntime().exec(
                    arrayOf("iptables", "-L", "OUTPUT", "-n")
                )
                val output = proc.inputStream.bufferedReader().readText()
                proc.waitFor()
                val prefix = "$IPTABLES_TAG-"
                output.lineSequence()
                    .filter { it.contains(prefix) }
                    .forEach { line ->
                        val tag = line.substringAfter(prefix)
                            .trim()
                            .takeWhile { it != ' ' && it != '"' }
                            .lowercase()
                        if (tag.isNotBlank()) activeRules.add(tag)
                    }
            } catch (_: Exception) {}
            return
        }
        if (!isWindows || !isRunningAsAdmin()) return
        val output = runPowerShellAndRead("""
            Get-NetFirewallRule |
            Where-Object { ${'$'}_.DisplayName -like '$RULE_PREFIX*' -and ${'$'}_.Enabled -eq 'True' } |
            Select-Object -ExpandProperty DisplayName
        """.trimIndent()) ?: return

        activeRules.clear()
        output.lineSequence()
            .map { it.trim() }
            .filter { it.isNotBlank() }
            .forEach { ruleName ->
                val baseName = ruleName.removePrefix(RULE_PREFIX).lowercase()
                activeRules.add("$baseName.exe")
            }
    }

    /**
     * Retry any rules that failed path resolution (process was not running at
     * block time). Called periodically from ProcessMonitor's enforcement loop.
     */
    fun retryPendingRules() {
        val pending = synchronized(pendingRules) { pendingRules.toSet() }
        pending.forEach { addRule(it) }
    }

    // ── Queries ───────────────────────────────────────────────────────────────

    fun isBlocked(processName: String): Boolean =
        activeRules.contains(processName.lowercase())

    fun activeRuleCount(): Int = activeRules.size

    fun pendingRuleCount(): Int = pendingRules.size

    // ── PowerShell helpers ────────────────────────────────────────────────────

    private fun runPowerShell(script: String) {
        try {
            ProcessBuilder(
                "powershell", "-NonInteractive", "-NoProfile",
                "-ExecutionPolicy", "Bypass", "-Command", script
            ).redirectErrorStream(true).start().waitFor()
        } catch (_: Exception) {}
    }

    private fun runPowerShellAndRead(script: String): String? {
        return try {
            val proc = ProcessBuilder(
                "powershell", "-NonInteractive", "-NoProfile",
                "-ExecutionPolicy", "Bypass", "-Command", script
            ).redirectErrorStream(true).start()
            val text = proc.inputStream.bufferedReader().readText()
            proc.waitFor()
            text.takeIf { it.isNotBlank() }
        } catch (_: Exception) { null }
    }
}
