package com.focusflow.enforcement

/**
 * Runtime probes for optional Linux system tools.
 *
 * Each probe runs `which <tool>` in a short-lived subprocess.
 * Safe to call from any coroutine on Dispatchers.IO — never the UI thread.
 */
object LinuxToolsChecker {

    data class ToolStatus(
        val name: String,
        val installed: Boolean,
        /** The single-line command the user can paste to install the tool. */
        val installHint: String
    )

    /** Check whether a command-line tool is on PATH. */
    fun isInstalled(tool: String): Boolean = try {
        ProcessBuilder("which", tool)
            .redirectErrorStream(true)
            .start()
            .waitFor() == 0
    } catch (_: Exception) {
        false
    }

    /** Probe all tools FocusFlow uses on Linux and return their statuses. */
    fun checkAll(): List<ToolStatus> = listOf(
        ToolStatus(
            name        = "xdotool",
            installed   = isInstalled("xdotool"),
            installHint = "sudo apt install xdotool   # or: sudo dnf install xdotool   # or: sudo pacman -S xdotool"
        ),
        ToolStatus(
            name        = "wmctrl",
            installed   = isInstalled("wmctrl"),
            installHint = "sudo apt install wmctrl    # or: sudo dnf install wmctrl    # or: sudo pacman -S wmctrl"
        ),
        ToolStatus(
            name        = "pkexec",
            installed   = isInstalled("pkexec"),
            installHint = "sudo apt install policykit-1   # or: sudo dnf install polkit"
        ),
        ToolStatus(
            name        = "notify-send",
            installed   = isInstalled("notify-send"),
            installHint = "sudo apt install libnotify-bin   # or: sudo dnf install libnotify"
        ),
    )
}
