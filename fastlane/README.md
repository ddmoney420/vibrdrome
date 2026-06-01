fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios generate

```sh
[bundle exec] fastlane ios generate
```

Regenerate the Xcode project from project.yml (restores nothing — entitlements handled separately)

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build a signed iOS archive and upload it to TestFlight

Usage: fastlane ios beta   (set SKIP_BUILD=1 to upload an existing .ipa at ./build/Vibrdrome.ipa)

### ios upload_only

```sh
[bundle exec] fastlane ios upload_only
```

Upload an already-built IPA to TestFlight (no build step)

### ios check_tf

```sh
[bundle exec] fastlane ios check_tf
```



----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
