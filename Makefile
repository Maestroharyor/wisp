# Wisp build commands. Requires Xcode (xcode-select -p) and XcodeGen.

PROJECT  := Wisp.xcodeproj
DERIVED  := build
APP      := $(DERIVED)/Build/Products/Debug/Wisp.app
SOURCES  := Wisp WispCore WispTests WispAgent

# Sign with the stable self-signed "Wisp Dev" certificate when it exists, so the
# Accessibility grant survives rebuilds. Falls back to ad-hoc ("-").
SIGN_IDENTITY ?= $(shell security find-identity -p codesigning | grep -q '"Wisp Dev"' && echo "Wisp Dev" || echo "-")

XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -destination "platform=macOS,arch=arm64" -quiet

.PHONY: project build test lint format run release hooks clean

project:
	xcodegen generate --quiet

build: project
	@[ "$(SIGN_IDENTITY)" != "-" ] || echo "warning: 'Wisp Dev' certificate not found; signing ad-hoc (permissions reset on every build)"
	$(XCODEBUILD) -scheme Wisp -configuration Debug CODE_SIGN_IDENTITY="$(SIGN_IDENTITY)" build

test: project
	$(XCODEBUILD) -scheme WispCore test

lint:
	xcrun swift-format lint --strict --recursive $(SOURCES)

format:
	xcrun swift-format format --in-place --recursive $(SOURCES)

run: build
	-pkill -x Wisp
	@while pgrep -x Wisp >/dev/null; do sleep 0.2; done
	open "$(APP)"

# Local git hooks from lefthook.yml (brew install lefthook).
hooks:
	lefthook install

# Universal Release DMG in build/release. See scripts/release.sh for notarising.
release:
	scripts/release.sh

clean:
	rm -rf $(DERIVED) $(PROJECT)
