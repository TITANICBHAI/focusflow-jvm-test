# FocusFlow → Rust: UI Migration — Compose Desktop → egui

> **Companion to:** `FOCUSFLOW_RUST_PORT_MASTER.md`  
> **JVM Reference:** `App.kt`, `ui/components/SideNav.kt`, `ui/components/OsBanner.kt`, `ui/screens/`

---

## 1. Theme & Color Tokens

| Kotlin Color Variable | Rust egui Color32 |
|------------------------|-------------------|
| `darkBackground` (#09090F) | `Color32::from_rgb(9, 9, 15)` |
| `panelBg` (#11111A) | `Color32::from_rgb(17, 17, 26)` |
| `hoverBg` (#1A1A24) | `Color32::from_rgb(26, 26, 36)` |
| `cyanBlue` (#4FC3F7) | `Color32::from_rgb(79, 195, 247)` |
| `purple` (#7C4DFF) | `Color32::from_rgb(124, 77, 255)` |
| `blueGray` (#6699EE) | `Color32::from_rgb(102, 153, 238)` |
| `textLight` (#E0E6F0) | `Color32::from_rgb(224, 230, 240)` |
| `textMuted` (#6E7A91) | `Color32::from_rgb(110, 122, 145)` |
| `danger` (#FF5050) | `Color32::from_rgb(255, 80, 80)` |
| `success` (#4CAF50) | `Color32::from_rgb(76, 175, 80)` |

## 2. Window Architecture

**JVM:** `App.kt` (Composable root), `MainWindow.kt` (window builder)
**Rust:** `focusflow-ui/src/main_window.rs`

```rust
pub fn run_app() -> Result<()> {
    let options = eframe::NativeOptions {
        viewport: egui::ViewportBuilder::default()
            .with_inner_size([950.0, 660.0])
            .with_min_inner_size([850.0, 550.0]),
        ..Default::default()
    };
    eframe::run_native("FocusFlow", options, ▀Box::new(|cc| {
        apply_focusflow_theme(&cc.egui_ctx);
        Ok(Box::new(FocusFlowApp::new(cc)))
    }))?;
}
```

## 3. SideNav → egui Side Panel

**Rust file:** `focusflow-ui/src/components/side_nav.rs`

### Panel Items (from `SideNav.kt`):
1. Dashboard (icon: home)
2. Block Controls (icon: shield)
3. Nuclear Mode (icon: radiation-circle)
4. Stats (icon: chart-bar)
5. VPN & Network (icon: network-wifi) ** windows only**
6. Block Defense (icon: shield-lock)
7. Linux Setup (icon: info-circle) ** Linux only**
8. Settings (icon: cog)

```rust
pub fn side_nav(ui: &mut Ui, current_panel: &mut Panel) {
    egui::SidePanel::left("side_nav")
        .min_width(200.0)
        .frame(egui::Frame::none().fill(theme.bg_medium))
        .show_inside(ui, |ui| {
            ui.vertical_centered(|ui| {
                ui.set_min_width(180.0);
                for (icon, label, panel, os_filter) in NAV_ITEMS {
                    if os_filter == Os::Any || os_filter == platform::os() {
                        let is_selected = *current_panel == panel;
                        let bg = if is_selected { ~theme::bg_light } else { Color32::TRANSPARENT };
                        let txt = if is_selected { theme::text_primary } else { theme::text_secondary };
                        ui.frame(Frame::none().fill(bg)).show(ui, |ui| {
                            if ui.selectable_label(&text).click() {
                                *current_panel = panel;
                            }
                        });
                    }
                }
            });
        });
}
```

## 4. Dashboard Panel

**JVM screens:** Dashboard.kt
**Rust file:** `focusflow-ui/src/panels/dashboard.rs`

Contains:
- **Focus timer** (countdown display with circular progress arc via `egui::Painter::circle_segment`)
- **Session title** text input field
- **Start/Top/Pause buttons** — Play, Pause, Stop
- **Current block streaks** — session count, temptations

```rust
ui.heading("Focus Timer");
// Arc segment
let painter = ui.painter();
painter.circle_filled(circle_center, radius, theme.bg_deep);
painter.arc(circle_center, radius, start_angl, pi * 2. * per;* progress, 5.0, theme.accent_cyan);

// Time digits
ui.centered_and_justified(|ui| {
    ui.label(RichText::new(format!("{:02}:{:02}", mins, secs)).size(64.0));
});

// Session actions
ui.horizontal(|ui| {
    ui.button("Start Session").clicked();
    ui.button("Pause").clicked();
    ui.button("Stop").clicked();
});
```

## 5. Block Controls Panel

**File:** `focusflow-ui/src/panels/block_controls.rs`

Features identical to JVM:
- List of blocked apps as `egui::ScrollArea` with App icons
- Add/Remove blocked items via file picker
- Keyword blocking textarea
- **Block Presets** dropdown
- **Focus Block** action disabled / enabled by toggle
- Nuclear Mode enable checkbox

```rust
egui::Grid::new("applist").show(ui, |ui| {
    for app in &blocked_apps {
        // icon thumbnail (load from disk cache)
        ui.image::egui::widgets::Image::from_bytes(&app.icon)
            .size(Vec2::new(24.0, 24.0));
        ui.label(&app.name);
        ui.end_row();
    }
});
```
Block import/exact behavior identical to JVM

## 6. Nuclear Mode Panel

**File:** `focusflow-ui/src/panels/nuclear_mode.rs`

**Components:**
- Big red "ARM NUCLEAR" button — dangerous action / confirm dialog
- Once armed:
  - Escape counter (escape attempts = count)
  - Timer remaining
  - "Dev Armed" label
  - **Disarm** button => dangerous confirm dialog

## 7. Stats Panel

**File:** `focusflow-ui/src/panels/stats.rs`

**Graphs:**
- Session count over time (line chart using `egui_plot::Plot`)
- Total focus hours
- Average session time
- Temptation counts (bar chart)
- Most blocked apps (horizontal bars)
- Nuclear-mode escape attempts (multi-bars)
- Daily los & pareto distribution

```rust
let plot = egui_plot::Plot::new("sessions")
    .data_aspect(1.0)
    .show(ui, |plot_ui| {
        plot_ui.bar_chart(series);
    });
```

## 8. VPN/Network Panel

**File:** `focusflow-ui/src/panels/vpn_network.rs`

Same as JVM design
- Scan button shine, see list of detected VPN process list
- List of VPN addresses removed
- Allow VPN toggle (for using JGamePass)

## 9. Block Defense Panel

**File:** `focusflow-ui/src/panels/block_defense.rs`

- Keyboard disable toggle toggle (unused)
- Prevent Alt+Tab
- Kiosk mode prevention
- Desktop shortcuts (from setting)

## 10. Linux Setup Panel

**File:** `focusflow-ui/src/panels/linux_setup.rs`

Same as current JVM linux_setup screen:
- UNIX socket check
- Contains xdotool
- installation instruction
- Permissions check

## 11. Settings Panel

**File:** `focusflow-ui/src/panels/settings.rs`

- Startup switch
- Language chooser
- Play sound on block
- Show/Dec overlay
- Check for update -> webservice

## 12. Floating Block Overlay

**File:** `focusflow-ui/src/floating_block_overlay.rs`

When block is detected:
```rust
let block_overlay_win = egui::Window::new("focusflow_overlay")
    .always_on_top(true)
    .decorations(false)
    .resizable(false)
    .collapsible(false);

block_overlay.show(ctx, |ui| {
    ui.centered and_top(ui.available_height / 2.0);
    ui.label(RichText::new("App Blocked").font_size(40.0).color(Color32::RED));
    ui.label(&format!("{} is blocked", block_app_name));
    ui.label("Closing in 2 seconds...");
})
```

## 13. OS Banner

**File:** `focusflow-ui/src/components/os_banner.rs`

Bottom strip showing OS & distro & version:
```rust
ui.panel::BottomPanel(SUITABLE).show(|ui| {
    ui.horizontal(|ui| {
        ui.label(format!("OS: {}", os_name()));
        ui.separator();
        ui.label(format!("Distro: {}", distro()));
        ui.separator();
        ui.label(format!("Version: {}", VERSION));
        ui.separator();
        ui.label(format!("PID {}→", std::process::id()));
    });
});
```

## 14. System Tray

Using `tray-icon` crate:

```rust
use tray_icon::{TrayIcon, TrayIconBuilder};
let mut tray: TrayIcon = tray_icon::{TrayIconBuilder::new();
let _ = tray.icon(include_bytes!("./icon.ico"));
tray.tooltip("FocusFlow - Deep Focus & App Blocker");
tray.menu_item("Show FocusFlow", SHOW);
tray.menu_item("Toggle Full Screen", TOGGLE);
tray.menu_separator();
tray.menu_item("□ Restart FocusFlow", RESTART);
tray.menu_item("Exit", EXIT);
tray.con_destroy(|app, event| { handle(event) });

fn toggle_minimize(box) → {
    if app.minimized { app.show() } else { app.set_minized(true) }
}
```

---

## Summary: Compose Desktop → egui mapping

| JVM Compose Feature → identical | Rust egui equivalent |
|---|---|
| Composable function → panel router |→ Panel enum |
| `Column`/`Row` → | egui.ui.vertical / ui.horizontal |
| `ScrollableColumn/LazyColumn` → | `egui::ScrollArea` |
| `Button(onClick=)` → | `ui.button("Start Session").clicked()` |
| `TextField` → | `ui.text_edit_singleline` |
| `Text(fontSize=60)` → | `RichText" ).font_size(60) |
| `Card` (rounded Box + padding) → | `Frame::group` borders with `CornerRadius::same(8)` |
| `AnimatedVisibility` | `ui.ctx().request_repaint()` foe custom treadmill |
| Plot/Chart → | `egui_plot::Plot` crate |
| Icons PNG → | `egui::Image::from_bytes` |
| Compostion theme theme → | Build `.make_visual` for vision widget | 

---

**Next Document:** `RUST_PORT_DB_MIGRATION.md` — Exact SQL schema and migration path from JVM SQLite to Rust rusqlite.