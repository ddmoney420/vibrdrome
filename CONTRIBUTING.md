# Contributing to Vibrdrome (iOS/macOS)

Thanks for your interest in contributing! Whether it's a bug fix, new feature, or documentation improvement — all contributions are welcome.

## Getting Started

```bash
# Prerequisites: Xcode 16+, XcodeGen
brew install xcodegen

# Clone and build
git clone https://github.com/ddmoney420/vibrdrome.git
cd vibrdrome
xcodegen generate
open Vibrdrome.xcodeproj
```

Build for iOS Simulator or your device from Xcode.

## Development Workflow

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run `swiftlint` before committing
5. Test on a real device or simulator
6. Open a PR with a description of what you changed and why

## Code Style

- SwiftLint is enforced — run `swiftlint` before committing
- Follow existing patterns in the codebase
- Use SwiftUI for all new views
- Keep views small and composable

## Project Structure

```
Vibrdrome/
  App/           App entry, AppState, Theme
  CarPlay/       CarPlay scene delegate and template manager
  Core/
    Audio/       AudioEngine, EQ, crossfade, spectrum analysis
    Downloads/   Background download manager, cache
    Networking/  SubsonicClient, API models, endpoints
    Persistence/ SwiftData models
  Features/      SwiftUI views organized by feature
  Shared/        Reusable components and extensions
```

## Running Tests

```bash
make test      # Unit tests
make lint      # SwiftLint
make build-ios # iOS Simulator build
```

## Reporting Bugs

- Use the [Bug Report](https://github.com/ddmoney420/vibrdrome/issues/new?template=bug_report.md) template
- Include device model, iOS version, and steps to reproduce
- Crash logs from Settings > Privacy & Security > Analytics Data are very helpful

## Requesting Features

- Use the [Feature Request](https://github.com/ddmoney420/vibrdrome/issues/new?template=feature_request.md) template
- Check existing issues first to avoid duplicates

## Ideas for Contributions

- New EQ presets
- Additional visualizer shaders
- Playlist import/export
- Widget support
- Localization / translations
- Performance optimizations
- Bug fixes (check [Issues](https://github.com/ddmoney420/vibrdrome/issues))

## Community

- **Discord:** [Join the server](https://discord.gg/9q5uw3CfN)
- **Website:** [vibrdrome.io](https://vibrdrome.io)

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
