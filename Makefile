.PHONY: generate build-ios build-macos test lint format clean help

SCHEME = Vibrdrome
PROJECT = Vibrdrome.xcodeproj
IOS_DEST = platform=iOS Simulator,name=iPhone 17 Pro
MACOS_DEST = platform=macOS

# Entitlements content that xcodegen clears on every run
define ENTITLEMENTS_CONTENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.developer.carplay-audio</key>
	<true/>
</dict>
</plist>
endef
export ENTITLEMENTS_CONTENT

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-15s\033[0m %s\n", $$1, $$2}'

generate: ## Run xcodegen and restore entitlements
	xcodegen generate
	@echo "$$ENTITLEMENTS_CONTENT" > Vibrdrome/Vibrdrome.entitlements
	@echo "✓ Entitlements restored"

build-ios: ## Build for iOS Simulator (iPhone 17 Pro)
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(IOS_DEST)' \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		| tail -20

build-macos: ## Build for macOS
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(MACOS_DEST)' \
		-configuration Debug \
		CODE_SIGNING_ALLOWED=NO \
		| tail -20

test: ## Run unit tests (iOS Simulator)
	xcodebuild test \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-destination '$(IOS_DEST)' \
		CODE_SIGNING_ALLOWED=NO \
		| tail -30

lint: ## Run SwiftLint
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --config .swiftlint.yml; \
	else \
		echo "⚠ SwiftLint not installed. Run: brew install swiftlint"; \
		exit 1; \
	fi

format: ## Run SwiftFormat
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat . --config .swiftformat; \
	else \
		echo "⚠ SwiftFormat not installed. Run: brew install swiftformat"; \
		exit 1; \
	fi

format-check: ## Check SwiftFormat (no changes, CI mode)
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat . --config .swiftformat --lint; \
	else \
		echo "⚠ SwiftFormat not installed. Run: brew install swiftlint"; \
		exit 1; \
	fi

clean: ## Clean build artifacts
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) 2>/dev/null || true
	rm -rf DerivedData build

all: generate build-ios build-macos lint ## Generate, build all platforms, lint
