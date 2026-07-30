# ── Entry point ──────────────────────────────────────────────────────────────
-keep class com.focusflow.** { *; }

# ── JNA (Win32 / native interop) ─────────────────────────────────────────────
# JNA structures and callbacks are called from native code, must not be renamed.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.Library { *; }
-keep class * implements com.sun.jna.Callback { *; }
-keep class * extends com.sun.jna.Structure { *; }
-keepclassmembers class * extends com.sun.jna.Structure { <fields>; }

# ── SQLite JDBC ───────────────────────────────────────────────────────────────
-keep class org.sqlite.** { *; }

# ── Reflection / serialisation safety ────────────────────────────────────────
-keepattributes *Annotation*, Signature, EnclosingMethod, InnerClasses

# ── Suppress all unresolved-reference warnings ────────────────────────────────
# Compose Desktop and Skiko reference many optional platform classes.
# Compose's own generated config already handles library resolution; suppress the rest.
-dontwarn **
