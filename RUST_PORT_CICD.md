# FocusFlow → Rust: CI/CD, Packaging & Shipping Plan

> **Companion to:** `FOCUSFLOW_RUST_PORT_MASTER.md`  
> **Purpose:** Complete automated build pipeline for Windows, Linux, and macOS — including testing, signing, packaging, and store submission.

---

## 1. CI Matrix — All OS + All Arch

### 1.1 Build Matrix (`build.yml`)

```yaml
name: CI Build + Test
on: [push, pull_request]
# The merge cart strategy:
#   - branches-ignore main => don't build pushes to main (PRs are enough)
jobs:
  test:
    strategy:
      matrix:
        os: [ubuntu-latest, windows-latest, macos-latest]
        rust: [stable]
        target:
          - ubuntu: x86_64-unknown-linux-gnu
          - windows: x86_64-pc-windows-msvc
          - macos: x86_64-apple-darwin
          - macos: aarch64-apple-darwin
        exclude:
          - os: ubuntu-latest
            target: x86_64-pc-windows-msvc
          - os: ubuntu-latest
            target: x86_64-apple-darwin
          - os: ubuntu-latest
            target: aarch64-apple-darwin
          - os: windows-latest
            target: x86_64-unknown-linux-gnu
          - os: windows-latest
            target: x86_64-apple-darwin
          - os: windows-latest
            target: aarch64-apple-darwin
          - os: macos-latest
            target: x86_64-pc-windows-msvc
          - os: macos-latest
            target: x86_64-unknown-linux-gnu
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          target: ${{ matrix.target }}
      - name: Install system libraries
        if: matrix.os == 'ubuntu-latest'
        run: sudo apt-get update && sudo apt-get install -y libgtk-3-dev libxdo-dev libappindicator3-dev
        # required on windows: Visual Studio C++ toolchain (default on windows runner)
      - name: Clippy
        run: cargo clippy --target ${{ matrix.target }} --no-deps -- -D warnings
      - name: Check format
        run: cargo fmt --all --check
      - name: Run tests
        run: cargo test --target ${{ matrix.target }} --workspace
      - name: Build binary in release
        run: cargo build --target ${{ matrix.target }} --release --bin focusflow --bin focusflow-recovery
      - name: Check binary size
        run: ls -la target/${{ matrix.target }}/release/focusflow* | cut -c 1-80
        # goal: binary should be ≤ 35MB
```

### 1.1 Test Docker for Cross Compile on Ubuntu

The standard `gh Cargo` rust-workflow is the best for building on the target. The Linux cross from Windows can use the `cross` action.

---

## 2. Windows-Specific (`build-windows.yml`)

### 2.1 Workflow

```yaml
name: Build Windows Release Package

on:
  release:
    types: [published]

jobs:
  build:
    runs-on: windows-latest
    steps:
      - name: Install Rust
        uses: dtolnay/rust-toolchain@stable
        with:
          targets: x86_64-pc-windows-msvc

      - name: Build binary
        run: cargo build --target x86_64-pc-windows-msvc --release --bin focusflow --bin focusflow-recovery

      - name: Generate MSI with WiX
        uses: ./.github/actions/convert-msi
        with:
          binary: target/x86_64-pc-windows-msvc/release/focusflow.exe

      - name: Create ZIP Distribution
        run: >
          7z a focusflow-windows-x64.zip
          target/x86_64-pc-windows-msvc/release/focusflow.exe
          target/x86_64-pc-windows-msvc/release/focusflow-recovery.exe

      - name: Upload Artifacts
        uses: actions/upload-artifact@v4
        with:
          path: |
            focusflow-windows-x64.zip
            target/x86_64-pc-windows-msvc/release/focusflow.msi

      - name: Upload to Microsoft Store (manual trigger)
        if: needs.release
        uses: .
```

### 2.2 WiX configuration (`packaging/windows/wix_installer.wxs`)

```xml
<?xml version="1.0"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package Name="FocusFlow" Manufacturer="FocusFlow" Version="4.0.0" UpgradeCode="XXXX-XXXX-...">
     <!-- Copy binary to %PROGRAMFILES% -->
      <!-- Create Start Menu shortcut -->
      <!-- Optionally register startup via Registry HKCU component -->
  </Package>
</Wix>
```

---

## 3. Linux Packaging (`build-linux.yml`)

### 3.1 AppImage + .deb + tar.gz

```yaml
name: Build Linux Release

on:
  push:
    tags: ["*"]

jobs:
  build:
    runs-on: ubuntu-20.04
    steps:
      - name: 11
        uses: dtolnay/rust-toolchain@stable
        with:
          target: x86_64-unknown-linux-gnu

      - name: Install libs
        run: sudo apt update && sudo apt install -y libgtk-3-dev patchelf

      - name: Build Release
        run: cargo build --release --all

      - name: Download appimagetool
        uses: ./.github/actions/setup-appimage

      - name: Package AppImage
        run: appimagetool FocusFlow.AppDir FocusFlow-x86_64.AppImage

      - name:  Create .deb via cargo-deb package
        run: |
          cargo install cargo-deb
          cargo deb

      - name: Upload all packages
        uses: actions/upload-artifact@v4
        with:
          path: target/release/*.{AppImage,deb,tar.gz}
```

---

## 4. macOS-Specific (`build-macos.yml`)

```yaml
name: Build macOS

on:
  push:
    tags: ["*"]

jobs:
  build:
    uses: actions/checkout@v4

    - name: Install Rust
      uses: dtolnay/rust-toolchain@stable
      with:
        target: aarch64-apple-darwin, x86_64-apple-darwin

    - name: Compile Universal binary via lipo
      run: |
        # x86_64
        cargo build --target x86_64-apple-darwin --release
        # aarch64
        cargo build --target aarch64-apple-darwin --release
        # lipo both
        lipo -create -o target/release/focusflow \
            target/x86_64-apple-darwin/release/focusflow \
            target/aarch64-apple-darwin/release/focusflow

    - name: Package as .app bundle
      # mkdir app bundle → bundle contents → codesign
    - name: Package as .dmg (hdiutil)
      run: hdiutil create -volname "FocusFlow" -srcfolder "focusflow.app" -ov -format UDZO "FocusFlow-${GITHUB_REF_NAME}.dmg"

    - name: Upload Artifact
      uses: actions/upload-artifact@v4
      with: { path: [*.dmg] }
```

---

## 5. Release Workflow

### 5.1 Main Brave

```yaml
name: Release All Platforms to GitHub Releases

on:
  push:
    tags:
      - 'v*.*.*'

jobs:
  upload:
    strategy:
      matrix:
        target: [x86_64-pc-windows-msvc, x86_64-unknown-linux-gnu, x86_64-apple-darwin, aarch64-apple-darwin]
        include:
          - os: windows-latest
            target: x86_64-pc-windows-msvc
            label: Windows x86_64
          - os: ubuntu-latest
            target: x86_64-unknown-linux-gnu
            label: Linux x86_64
          - os: macos-latest
            target: x86_64-apple-darwin
            label: macOS Intel
          - os: macos-latest
            target: aarch64-apple-darwin
            label: macOS ARM
    steps:
      - uses: actions/checkout@v4
      - name: Set up .NET compile
        uses: dtolnay/rust-toolchain@stable
        with:
          target: ${{ matrix.target }}
      - name: Build
        run: cargo build --target ${{ matrix.target }} --release all bins
      - name: Sign executable (optional)
        if: runner.os == 'Windows' || runner.os == 'macOS'
        env:
          CERTIFICATE: ${{ secrets.CODE_SIGN_CERT }}
          CERT_PASS: ${{ secrets.CODE_SIGN_PASS }}
        run: .github/scripts/sign.sh ${{ matrix.target }}
      - name: Upload Asset
        uses: softprops/action-gh-release@v1
        with:
          files: path/to/binary/$}

      - name: Publish to Microsoft Store, via store update API
        if: runner.os == 'Windows'
        uses: ./.github/actions/store-publish
```

---

## 6. Update Check Service

### 6.1 Self-hosted update endpoint

- Publish binary hashes + version info to `updates.focusflow.app`
- Rust binary polls the API every 6 hours, download new binary in background, replace on restart

```rust
// focusflow-services/src/http_client.rs
pub fn check_for_update() -> Result<()> {
    // GET https://updates.focusflow.app/
    // Parse JSON { version, url, sha256 }
    // Compare semver
    // If new version: pop update notification to UI
}
```

---

## 7. Code Quality Gate in CI

| Check | Tool |
|-------|------|
| Lint   | `cargo clippy -- -D warnings` |
| Format  | `cargo fmt --all -- --check` |
| Unused data | `cargo udeps` |
| Static analysis | `cargo-audit` |
| File size check | BOF |

---

## 8. Summary — Complete Document Index

| Document | Description |
|------|------|
| `FOCUSFLOW_RUST_PORT_MASTER.md` | Master architecture, crate breakdown, full feature parity matrix, OS support strategy |
| `RUST_PORT_IMPLEMENTATION_PLAN.md` | Week-by-week phases (0–10), exact file creation order, completion gates |
| `RUST_PORT_ENFORCEMENT_DEEP.md` | Exact code patterns for ProcessMonitor, NuclearMode, WFP firewall, keyboard hook, VPN blocker |
| `RUST_PORT_UI_MIGRATION.md` | Compose Desktop→egui panel-by-panel mapping, theme/colors/layout, tray icon |
| `RUST_PORT_DB_MIGRATION.md` | SQLite DDL identical to JVM, Rust model structs, migration system |
| `RUST_PORT_CICD.md` | This document — CI pipelines, packaging, signing, release management |

---

**End of FocusFlow JVM→Rust Full Port Plan.**

---