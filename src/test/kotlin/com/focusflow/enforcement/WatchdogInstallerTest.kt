package com.focusflow.enforcement

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test
import java.io.File

class WatchdogInstallerTest {

    private val isLinux = System.getProperty("os.name", "").lowercase().contains("linux")
    private val home    = System.getProperty("user.home")
    private val systemdDir = File("$home/.config/systemd/user")

    @Test
    fun `service file is written on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        WatchdogInstaller.install()
        val f = File(systemdDir, "focusflow-watchdog.service")
        assertTrue(f.exists(), "focusflow-watchdog.service must exist after install()")
    }

    @Test
    fun `timer file is written on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        WatchdogInstaller.install()
        val f = File(systemdDir, "focusflow-watchdog.timer")
        assertTrue(f.exists(), "focusflow-watchdog.timer must exist after install()")
        assertTrue(f.readText().contains("OnUnitActiveSec=2min"), "Timer must fire every 2 minutes")
    }

    @Test
    fun `ExecStartPre uses inverted pgrep — no duplicate instances`() {
        assumeTrue(isLinux, "Linux-only test")
        WatchdogInstaller.install()
        val content = File(systemdDir, "focusflow-watchdog.service").readText()
        // Must use '! pgrep' so ExecStart is SKIPPED when FocusFlow is already running.
        // The old bug used '|| exit 0' which always exited 0, spawning a duplicate every tick.
        assertTrue(
            content.contains("! pgrep -f focusflow"),
            "ExecStartPre must use '! pgrep -f focusflow' to avoid spawning duplicates.\nActual service:\n$content"
        )
        assertFalse(
            content.contains("|| exit 0"),
            "Old inverted logic '|| exit 0' must be gone.\nActual service:\n$content"
        )
    }

    @Test
    fun `ExecStart contains a real command not just empty`() {
        assumeTrue(isLinux, "Linux-only test")
        WatchdogInstaller.install()
        val content = File(systemdDir, "focusflow-watchdog.service").readText()
        val execLine = content.lines().firstOrNull { it.startsWith("ExecStart=") }
        assertNotNull(execLine, "Service file must have an ExecStart line")
        assertTrue(
            execLine!!.length > "ExecStart=".length,
            "ExecStart must contain the command to relaunch FocusFlow, not be empty.\nLine: $execLine"
        )
    }

    @Test
    fun `isInstalled returns a boolean without throwing on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        // Should never throw regardless of whether systemd is running in CI
        assertDoesNotThrow { WatchdogInstaller.isInstalled() }
    }

    @Test
    fun `uninstall does not throw even when timer is not installed`() {
        assumeTrue(isLinux, "Linux-only test")
        assertDoesNotThrow { WatchdogInstaller.uninstall() }
    }
}
