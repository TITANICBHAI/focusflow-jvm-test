# FocusFlow AUR Package

This directory contains the `PKGBUILD` for the [Arch User Repository](https://aur.archlinux.org/) package `focusflow-bin`.

Once submitted, Arch Linux users can install FocusFlow with:

```bash
yay -S focusflow-bin
# or
paru -S focusflow-bin
```

---

## Submitting to the AUR (one-time setup)

**You need to do this — it requires an AUR account and SSH key.**

1. Create an account at https://aur.archlinux.org/register/
2. Add your SSH public key at https://aur.archlinux.org/account/ → Edit Account → SSH Public Key
3. Clone the (empty) AUR package repo:
   ```bash
   git clone ssh://aur@aur.archlinux.org/focusflow-bin.git aur-focusflow
   ```
4. Copy `PKGBUILD` and `.SRCINFO` into `aur-focusflow/`
5. Commit and push:
   ```bash
   cd aur-focusflow
   cp /path/to/this/repo/aur/PKGBUILD .
   cp /path/to/this/repo/aur/.SRCINFO .
   git add PKGBUILD .SRCINFO
   git commit -m "Initial release v1.1.6"
   git push
   ```

---

## Updating for a new release

1. Bump `pkgver` in `PKGBUILD` and `.SRCINFO` to the new version
2. Update the `source=` URL in both files with the new version number
3. Compute the new sha256sum and replace `SKIP`:
   ```bash
   curl -sL https://github.com/TITANICBHAI/FocusFlow-jvm-Test/releases/download/vX.Y.Z/FocusFlow-X.Y.Z-x86_64.AppImage \
     | sha256sum | cut -d' ' -f1
   ```
4. Push to the AUR:
   ```bash
   cd aur-focusflow
   # copy updated PKGBUILD + .SRCINFO
   git add -A && git commit -m "Update to vX.Y.Z" && git push
   ```

---

## Testing the PKGBUILD locally (on Arch)

```bash
cd aur/
makepkg -si
```

This builds and installs the package locally without needing to push to the AUR first.
