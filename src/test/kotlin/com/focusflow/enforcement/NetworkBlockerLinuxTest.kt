package com.focusflow.enforcement

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

class NetworkBlockerLinuxTest {

    private val isLinux = System.getProperty("os.name", "").lowercase().contains("linux")

    @Test
    fun `syncFromFirewall does not throw on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        // Must silently return — no Windows Firewall available on Linux.
        // A throw here would crash the startup sequence.
        assertDoesNotThrow {
            NetworkBlocker.syncFromFirewall()
        }
    }

    @Test
    fun `addRule on Linux returns true without crashing`() {
        assumeTrue(isLinux, "Linux-only test")
        // Linux path registers the rule in-memory and returns true so callers
        // believe the block succeeded (HostsBlocker handles the actual blocking).
        val result = NetworkBlocker.addRule("test-process")
        assertTrue(result, "addRule must return true on Linux (in-memory registration)")
    }

    @Test
    fun `removeRule on Linux does not throw`() {
        assumeTrue(isLinux, "Linux-only test")
        assertDoesNotThrow {
            NetworkBlocker.removeRule("test-process")
        }
    }

    @Test
    fun `removeAllRules on Linux does not throw`() {
        assumeTrue(isLinux, "Linux-only test")
        assertDoesNotThrow {
            NetworkBlocker.removeAllRules()
        }
    }
}
