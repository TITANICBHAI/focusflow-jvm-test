# Release Instructions

How to publish a new FocusFlow release. Steps marked **[YOU]** require action from you — the agent can't do them because they require a browser, admin rights, or credentials it doesn't hold.

---

## Before every release

### 1. Bump the version **[YOU]**

Edit two lines in `build.gradle.kts`:

```
version = "X.Y.Z"           # line ~8
packageVersion = "X.Y.Z"    # inside nativeDistributions block
```

Also update `CrashReporter.kt`:

```kotlin
const val APP_VERSION = "X.Y.Z"
```

And add a `ChangelogEntry` block in `ChangelogScreen.kt` for the new version — the release workflow reads this to auto-generate the GitHub Release body.

### 2. Push to `main`

```bash
git add -A && git commit -m "chore: bump version to X.Y.Z" && git push
```

---

## Building the installers

Both builds run automatically on every push to `main`. You just need to wait for them to go green on GitHub Actions before running the release workflow.

| Workflow | Produces | Runner |
|---|---|---|
| `build-windows.yml` | `.exe`, `.msi`, `.msix` | `windows-latest` |
| `build-linux.yml` | `.deb`, `.rpm`, `.AppImage` | `ubuntu-latest` |

**[YOU]** — Go to **Actions → build-windows** and **Actions → build-linux** and confirm both are green on the commit you want to release. If either is red, fix it before continuing.

---

## Publishing the release

### **[YOU]** — Trigger the release workflow

1. Go to **Actions → Publish Release → Run workflow**
2. Leave both Run ID fields blank (it picks the latest successful build automatically)
3. Tick **"Mark as pre-release?"** if this is a beta
4. Click **Run workflow**

The workflow will:
- Read the version from `build.gradle.kts`
- Parse the changelog entry for that version
- Download all Windows and Linux artifacts
- Create a `vX.Y.Z` git tag
- Publish a GitHub Release with all installers attached
- Include the install script (`install.sh`) in the release notes automatically

### After it finishes

**[YOU]** — Open the new release on GitHub (`Releases → vX.Y.Z`) and:
- Confirm all 6 assets are attached: `.exe`, `.msi`, `.msix`, `.deb`, `.rpm`, `.AppImage`
- Read through the auto-generated release notes and fix any formatting issues
- Copy the one-liner install command and test it in a shell (or WSL2):

```bash
curl -fsSL https://raw.githubusercontent.com/TITANICBHAI/FocusFlow-jvm-Test/main/install.sh | bash
```

---

## Getting your first downloads

Once the release is live:

### Listing the app

**[YOU]** — Submit to these places (each takes ~5 min):

| Platform | URL | Notes |
|---|---|---|
| AlternativeTo | https://alternativeto.net/software/add/ | List as alternative to Cold Turkey, Freedom, etc. |
| Product Hunt | https://www.producthunt.com/posts/new | Best for Windows side; schedule for Tuesday 12:01am PT |
| r/selfhosted | https://reddit.com/r/selfhosted | Post when Linux build is stable |
| r/productivity | https://reddit.com/r/productivity | Focus on the "real blocking" angle, not the tech |
| Arch AUR | https://aur.archlinux.org/submit/ | Requires writing a `PKGBUILD` — see note below |

### AUR package (Arch Linux) **[YOU]**

The AUR gets you in front of exactly the users who care about the Linux port. You need to:

1. Create an AUR account at https://aur.archlinux.org/register/
2. Write a `PKGBUILD` that downloads the `.AppImage` from GitHub Releases
3. Push it to the AUR

Minimal `PKGBUILD` template (put in a new `aur/` folder in this repo for reference):

```bash
pkgname=focusflow-bin
pkgver=1.1.6
pkgrel=1
pkgdesc="Focus & productivity app with real app blocking"
arch=('x86_64')
url="https://github.com/TITANICBHAI/FocusFlow-jvm-Test"
license=('custom')
depends=('xdotool' 'wmctrl')
source=("focusflow-${pkgver}.AppImage::https://github.com/TITANICBHAI/FocusFlow-jvm-Test/releases/download/v${pkgver}/focusflow-${pkgver}-x86_64.AppImage")
sha256sums=('SKIP')   # replace with actual sha256 of the AppImage

package() {
  install -Dm755 "focusflow-${pkgver}.AppImage" "$pkgdir/usr/bin/focusflow"
}
```

### Sentry (optional but recommended) **[YOU]**

To replace the Discord webhook with a proper crash-reporting backend:

1. Create a free account at https://sentry.io
2. Create a new project (Java/Kotlin)
3. Copy the DSN
4. Add it as a GitHub Actions secret named `SENTRY_DSN`
5. Replace `DISCORD_WEBHOOK_URL` in `CrashReporter.kt` with the Sentry SDK

This gives you deduplication, stack trace grouping, and a proper privacy policy URL to show users in the consent dialog.

---

## Version checklist

- [ ] `build.gradle.kts` version bumped (2 places)
- [ ] `CrashReporter.APP_VERSION` bumped
- [ ] `ChangelogScreen.kt` entry added
- [ ] Pushed to `main`
- [ ] `build-windows` green ✅
- [ ] `build-linux` green ✅
- [ ] Release workflow triggered
- [ ] All 6 assets confirmed on the release page
- [ ] Install script tested
