# macOS Release (Direct DMG Distribution)

How to build and publish the macOS `.dmg` that users download outside the Mac
App Store. The goal: a **signed + notarized** DMG that opens with no Gatekeeper
warning ("unidentified developer" / "damaged and can't be opened").

This is separate from TestFlight/App Store (see `testflight` notes). Direct
distribution requires **Developer ID** signing and **Apple notarization**, which
are different from the Apple Development signing used for local/TestFlight builds.

## Cutting a release — what you do manually

The one-time setup below is **already done on the current Mac.** To cut a new
macOS DMG release, the only manual steps are:

1. Make sure the build number is bumped/committed for the new build (if it's new).
2. **Run the script in your own Terminal** (not a background/CI runner — it has
   interactive keychain prompts):
   ```bash
   scripts/make-dmg.sh --upload v1.0.0-beta.<N>
   ```
   (omit `--upload …` to build locally without publishing)
3. When a **keychain dialog** appears (codesign accessing the Developer ID key),
   click **Always Allow**.
4. **Wait** — notarization goes to Apple and usually takes a few minutes;
   occasionally longer if Apple's notary queue is backed up. **Don't run it twice**
   (a built-in lock blocks concurrent runs and prevents duplicate submissions).
5. It finishes with `DONE: build-dmg/Vibrdrome-macOS-v1.0.0-build<N>.dmg`, a
   passing `stapler validate`, and (with `--upload`) the DMG attached to the
   GitHub pre-release.

If it **fails in notarization**, get the exact reason with:
`xcrun notarytool log <submission-id> --keychain-profile vibrdrome-notary`

On a **new Mac**, redo the one-time setup first (below).

## One-time setup (prerequisites)

These are required before `scripts/make-dmg.sh` will work. They are **already set
up on the current Mac** — redo them only on a new machine.

### 1. Developer ID Application certificate
- developer.apple.com → Certificates, IDs & Profiles → Certificates → **+** →
  **Developer ID Application** → create, download, double-click to install in the
  login keychain.
- Verify: `security find-identity -v -p codesigning | grep "Developer ID Application"`

### 2. Enable Hardened Runtime on the macOS app
Notarization requires the Hardened Runtime. Add to the `VibrdromeMac` target in
`project.yml` (then `make generate` + restore entitlements):

```yaml
    settings:
      base:
        ENABLE_HARDENED_RUNTIME: "YES"
```

(Confirm playback, EQ/audio tap, and downloads still work after enabling it — the
audio tap and any JIT-like behavior can need explicit entitlements under the
hardened runtime.)

### 3. notarytool credentials
Use the existing App Store Connect API key (Key ID `952C23848F`). Create a reusable
keychain profile once:

```bash
xcrun notarytool store-credentials "vibrdrome-notary" \
  --key /path/to/AuthKey_952C23848F.p8 \
  --key-id 952C23848F \
  --issuer <YOUR_ISSUER_UUID>
```

(The issuer UUID is on the App Store Connect → Users and Access → Integrations →
Keys page. Alternatively use `--apple-id <id> --team-id 85JD2B827Q --password
<app-specific-password>`.)

## Building a DMG

```bash
# build + notarize locally (no publish)
scripts/make-dmg.sh

# build + notarize AND attach to a GitHub release/tag
scripts/make-dmg.sh --upload v1.0.0-beta.54
```

Output: `build-dmg/Vibrdrome-macOS-v<version>-build<N>.dmg`, signed, notarized, and
stapled. The script runs `xcrun stapler validate` and `spctl` at the end to confirm.

**Note:** `codesign` and `notarytool` may surface keychain prompts. If the script
hangs on a background runner, run it in your own terminal (or via `! scripts/make-dmg.sh`).

## Publishing convention (GitHub Releases)

- **Keep old releases.** GitHub release assets are stored separately from the repo
  and are free/generous on public repos — old DMGs do **not** take up repo space.
  They're useful history; don't delete them.
- **One pre-release per build**, tagged like `v1.0.0-beta.54`, with a single DMG
  asset named `Vibrdrome-macOS-v1.0.0-build<N>.dmg`. This matches the existing
  pattern (builds 38, 39, 50).
- GitHub automatically marks the newest non-draft release as **Latest**, so a
  consistent "latest macOS download" just works.
- Optional later: a stable `…/releases/latest/download/<asset>` URL (keep the asset
  filename stable across builds) and/or **Sparkle** for in-app auto-updates.

## Status

- The prerequisites (Developer ID cert, notary profile `vibrdrome-notary`, Hardened
  Runtime, macOS-specific entitlements) are **set up, and the pipeline is proven end
  to end.**
- **Build 54** shipped a signed + notarized DMG via this process (the
  `v1.0.0-beta.54` GitHub pre-release). Builds 38–50 used an earlier undocumented
  manual process; builds 51–53 have no macOS DMG.
