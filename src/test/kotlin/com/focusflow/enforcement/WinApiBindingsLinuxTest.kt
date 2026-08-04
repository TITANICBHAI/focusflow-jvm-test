package com.focusflow.enforcement

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.Test

class WinApiBindingsLinuxTest {

    private val isLinux = System.getProperty("os.name", "").lowercase().contains("linux")

    @Test
    fun `hasXdotool resolves without throwing`() {
        assumeTrue(isLinux, "Linux-only test")
        // Accessing the lazy val must never throw — xdotool may or may not be
        // installed, but the absence must be handled gracefully.
        assertDoesNotThrow {
            @Suppress("UNUSED_VARIABLE")
            val result = hasXdotool
            // result is true if installed, false if not — both are valid
        }
    }

    @Test
    fun `isLinux is true when running on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        assertTrue(isLinux, "isLinux must be true on a Linux runner")
    }

    @Test
    fun `isWindows is false when running on Linux`() {
        assumeTrue(isLinux, "Linux-only test")
        assertFalse(isWindows, "isWindows must be false on Linux — guards throughout the codebase depend on this")
    }

    @Test
    fun `getLinuxForegroundProcess returns null or a pair without throwing`() {
        assumeTrue(isLinux, "Linux-only test")
        // In a headless CI environment this will return null — that is correct.
        // What it must NOT do is throw an uncaught exception.
        assertDoesNotThrow {
            WinEventHook.getLinuxForegroundProcess()
        }
    }
}
