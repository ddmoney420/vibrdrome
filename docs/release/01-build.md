# Build Reproducibility Guide

**Project:** Veydrune — iOS/macOS music player for Navidrome (Subsonic API)
**Last verified:** 2026-02-21

---

## Table of Contents

1. [Required Tools](#required-tools)
2. [XcodeGen Workflow](#xcodegen-workflow)
3. [Build Commands](#build-commands)
4. [Project Configuration](#project-configuration)
5. [SPM Dependencies](#spm-dependencies)
6. [Code Signing](#code-signing)
7. [Available Simulators](#available-simulators)
8. [Known Issues](#known-issues)

---

## Required Tools

| Tool       | Version                          | Notes                                                        |
|------------|----------------------------------|--------------------------------------------------------------|
| Xcode      | 26.2 (Build version 17C52)      | `project.yml` declares `xcodeVersion: "16.0"` but the actual build environment uses Xcode 26.2 |
| XcodeGen   | 2.44.1                          | Installed via Homebrew at `/opt/homebrew/bin/xcodegen`        |
| Swift      | 6.0                             | Bundled with Xcode                                           |
| SwiftLint  | Not installed                    | No linting configured yet                                    |
| SwiftFormat| Not installed                    | No formatting configured yet                                 |

---

## XcodeGen Workflow

The Xcode project file (`Veydrune.xcodeproj`) is generated from `project.yml` and is listed in `.gitignore`. You must run XcodeGen before building from a fresh clone.

**CRITICAL:** XcodeGen clears the entitlements file on every run. The entitlements must be restored after generation.

### Step-by-step

1. Generate the Xcode project:

   ```bash
   xcodegen generate
   ```

2. Restore the entitlements file at `Veydrune/Veydrune.entitlements` with the following content:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>com.apple.developer.carplay-audio</key>
       <true/>
   </dict>
   </plist>
   ```

   The project's `Makefile` target `make generate` handles both steps automatically (generation followed by entitlements restoration).

### Quick path (recommended)

```bash
make generate
```

---

## Build Commands

### iOS Simulator (iPhone 17 Pro)

```bash
xcodebuild build \
  -project Veydrune.xcodeproj \
  -scheme Veydrune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### macOS Native

```bash
xcodebuild build \
  -project Veydrune.xcodeproj \
  -scheme Veydrune \
  -destination 'platform=macOS' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

### Full rebuild from clean state

```bash
make generate
xcodebuild clean build \
  -project Veydrune.xcodeproj \
  -scheme Veydrune \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

---

## Project Configuration

| Setting                  | Value                  |
|--------------------------|------------------------|
| Bundle ID                | `com.veydrune.app`     |
| Marketing version        | 0.1.0                  |
| Build number             | 1                      |
| iOS deployment target    | 17.0                   |
| macOS deployment target  | 14.0                   |
| Swift strict concurrency | `complete`             |
| Supported destinations   | iOS, macOS             |

---

## SPM Dependencies

| Package        | Version   | Product        | Purpose                          |
|----------------|-----------|----------------|----------------------------------|
| Nuke           | 12.0.0+   | NukeUI         | Image loading and disk caching   |
| KeychainAccess | 4.2.2+    | KeychainAccess | Keychain credential storage      |

Dependencies are declared in `project.yml` and resolved automatically by Xcode on first build. No manual `swift package resolve` step is required, but you can run it to pre-fetch:

```bash
xcodebuild -resolvePackageDependencies \
  -project Veydrune.xcodeproj \
  -scheme Veydrune
```

---

## Code Signing

### CarPlay Audio Entitlement

The app requires the `com.apple.developer.carplay-audio` entitlement for CarPlay integration. This entitlement is defined in `Veydrune/Veydrune.entitlements`.

### CI / Local builds without signing

Pass `CODE_SIGNING_ALLOWED=NO` to `xcodebuild` (shown in the build commands above). This is sufficient for simulator builds and verification that the project compiles.

### Device testing

Requires an Apple Developer account with the CarPlay audio entitlement provisioned. Configure your signing team in Xcode or pass the appropriate `DEVELOPMENT_TEAM` build setting.

---

## Available Simulators

The following simulators are available in the Xcode 26.2 environment:

| Device                     | UUID                                   | Status  |
|----------------------------|----------------------------------------|---------|
| iPhone 17 Pro              | EC1FB225-7EF0-4193-A942-E9889AF1A0CB  | Booted  |
| iPhone 17 Pro Max          | —                                      | —       |
| iPhone Air                 | —                                      | —       |
| iPhone 17                  | —                                      | —       |
| iPhone 16e                 | —                                      | —       |
| iPad Pro 13-inch (M5)      | —                                      | Booted  |
| iPad Pro 11-inch (M5)      | —                                      | —       |
| iPad mini                  | —                                      | —       |
| iPad                       | —                                      | —       |
| iPad Air 13-inch           | —                                      | —       |

The primary development simulator is **iPhone 17 Pro**.

---

## Known Issues

1. **`.xcodeproj` is gitignored.** You must run `xcodegen generate` (or `make generate`) before building from a fresh clone. The project file is not committed to version control.

2. **XcodeGen clears entitlements.** Every invocation of `xcodegen generate` overwrites `Veydrune/Veydrune.entitlements`. Always restore the file afterward. The `make generate` target handles this automatically.

3. **No test target.** Unit and UI test targets have not been created yet. There is no `xcodebuild test` workflow available.

4. **Xcode version mismatch in project.yml.** The `xcodeVersion` field in `project.yml` reads `"16.0"`, but the actual build environment runs Xcode 26.2. This has no effect on the build but may cause confusion.
