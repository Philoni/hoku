#
# Hoku – common tasks. Needs Xcode 27 and XcodeGen (`brew install xcodegen`).
#   make install       build with YOUR free Apple Development certificate, install to ~/Applications, launch
#   make build         same build, without installing
#   make test          HueKit unit tests
#   make release-zip   release build signed with "Hoku Release Signing" (maintainer only)
#   make release-dmg   the same as a disk image with an Applications shortcut (maintainer only)
#   make verify        signature guard for an existing dist/Hoku-<version>.zip
#   make cert          one-time: create the self-signed release certificate (maintainer only)

SHELL         := /bin/zsh
.SHELLFLAGS   := -eu -o pipefail -c
APP_NAME      := Hoku
BUNDLE_ID     := io.github.philoni.hoku
DIST          := dist
RELEASE_DD    := build/ReleaseDerivedData.noindex
RELEASE_APP   := $(RELEASE_DD)/Build/Products/Release/$(APP_NAME).app
LSREGISTER    := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Version from project.yml unless given: make release-zip VERSION=0.9.0
VERSION       ?= $(shell sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1 | tr -d '"')
BUILD_NUMBER  ?= $(shell echo "$(VERSION)" | awk -F. '{ print $$1*10000 + $$2*100 + $$3 }')

.DEFAULT_GOAL := help
.PHONY: help build install test release-zip release-dmg verify cert clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{ printf "  make %-12s %s\n", $$1, $$2 }'

build: ## Build with your Apple Development certificate (free Apple ID), no install
	scripts/build-app.sh --no-install

install: ## Build, install to ~/Applications (only registered copy) and launch
	scripts/build-app.sh

test: ## Run the HueKit unit tests
	swift test --package-path Packages/HueKit

release-zip: ## Release build signed with "Hoku Release Signing" → dist/ (needs HOKU_SIGN_SHA1)
	@[[ -n "$${HOKU_SIGN_SHA1:-}" ]] || { print -u2 "HOKU_SIGN_SHA1 fehlt (SHA-1 von 'Hoku Release Signing', siehe make cert)"; exit 1; }
	HOKU_TEAM= xcodegen generate --quiet
	xcodebuild -project $(APP_NAME).xcodeproj -scheme $(APP_NAME) -configuration Release \
		-derivedDataPath $(RELEASE_DD) -destination 'generic/platform=macOS' -quiet \
		MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
		CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" \
		build
	scripts/sign-and-package.sh "$(RELEASE_APP)" "$(VERSION)" "$(DIST)"
	@# Build products must not stay registered: duplicate copies confuse Siri/Shortcuts and LNP.
	-$(LSREGISTER) -u "$(RELEASE_APP)" 2>/dev/null
	@print "✓ $(DIST)/$(APP_NAME)-$(VERSION).zip – zum Testen entpacken und nach /Applications VERSCHIEBEN"

release-dmg: release-zip ## Disk image with an Applications shortcut → dist/Hoku-<VERSION>.dmg
	@tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	ditto -x -k "$(DIST)/$(APP_NAME)-$(VERSION).zip" "$$tmp"; \
	ln -s /Applications "$$tmp/Programme"; \
	rm -f "$(DIST)/$(APP_NAME)-$(VERSION).dmg"; \
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$$tmp" -fs APFS -format ULFO -quiet "$(DIST)/$(APP_NAME)-$(VERSION).dmg"; \
	$(LSREGISTER) -u "$$tmp/$(APP_NAME).app" >/dev/null 2>&1 || true; \
	cd $(DIST) && shasum -a 256 "$(APP_NAME)-$(VERSION).dmg" > "$(APP_NAME)-$(VERSION).dmg.sha256"
	@print "✓ $(DIST)/$(APP_NAME)-$(VERSION).dmg"

verify: ## Re-check signature, DR and SHA256 of dist/Hoku-<VERSION>.zip
	@tmp=$$(mktemp -d); trap 'rm -rf "$$tmp"' EXIT; \
	ditto -x -k "$(DIST)/$(APP_NAME)-$(VERSION).zip" "$$tmp"; \
	codesign --verify --deep --strict --verbose=2 "$$tmp/$(APP_NAME).app"; \
	expected=$$(sed -n 's/^designated => //p' .github/signing/designated-requirement.txt); \
	codesign --verify --strict -R "=$$expected" "$$tmp/$(APP_NAME).app"; \
	codesign -d -r- "$$tmp/$(APP_NAME).app" 2>&1 | grep designated; \
	$(LSREGISTER) -u "$$tmp/$(APP_NAME).app" >/dev/null 2>&1 || true; \
	cd $(DIST) && shasum -a 256 -c "$(APP_NAME)-$(VERSION).zip.sha256"

cert: ## One-time: create the self-signed release certificate (maintainer only)
	scripts/make-signing-cert.sh

clean: ## Remove build output (keeps nothing registered with LaunchServices)
	-find build -maxdepth 6 -name "$(APP_NAME).app" -exec $(LSREGISTER) -u {} \; 2>/dev/null
	rm -rf build $(DIST)
