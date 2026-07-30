# ── Entry point ──────────────────────────────────────────────────────────────
-keep class com.focusflow.** { *; }

# ── JNA (Win32 / native interop) ─────────────────────────────────────────────
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.Library { *; }
-keep class * implements com.sun.jna.Callback { *; }
-keep class * implements com.sun.jna.Structure { *; }
-keepclassmembers class * extends com.sun.jna.Structure {
    <fields>;
}
-dontwarn com.sun.jna.**

# ── SQLite JDBC ───────────────────────────────────────────────────────────────
-keep class org.sqlite.** { *; }
-keep class org.sqlite.core.** { *; }
-dontwarn org.sqlite.**

# ── Kotlin stdlib + coroutines ────────────────────────────────────────────────
-keep class kotlin.** { *; }
-keep class kotlinx.coroutines.** { *; }
-keepclassmembers class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**
-dontwarn kotlin.**

# ── Compose runtime / UI / foundation / animation ────────────────────────────
# Keep these packages but NOT androidx.compose.material.icons.** —
# that package contains 2000+ icons; we let ProGuard tree-shake unused ones.
# Only the icons actually referenced in source will be retained automatically.
-keep class androidx.compose.runtime.** { *; }
-keep class androidx.compose.ui.** { *; }
-keep class androidx.compose.foundation.** { *; }
-keep class androidx.compose.animation.** { *; }
-keep class androidx.compose.material3.** { *; }
-keep class androidx.compose.material.ripple.** { *; }
# Keep the Icons container itself but NOT the individual icon objects
-keep class androidx.compose.material.icons.Icons { *; }
-keep class androidx.compose.material.icons.Icons$* { *; }
-dontwarn androidx.compose.**

# ── Skiko renderer ────────────────────────────────────────────────────────────
-keep class org.jetbrains.compose.** { *; }
-keep class org.jetbrains.skiko.** { *; }
-keep class org.jetbrains.skia.** { *; }
-dontwarn org.jetbrains.**

# ── Reflection / serialisation safety ────────────────────────────────────────
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
-keepattributes InnerClasses

# ── Suppress noisy warnings ───────────────────────────────────────────────────
-dontwarn java.awt.**
-dontwarn javax.**
-dontwarn sun.**
