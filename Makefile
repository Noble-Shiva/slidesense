APP := SlideSense
BUNDLE := $(APP).app
INSTALL_DIR ?= /Applications

.PHONY: all build app run test snapshots install uninstall clean dump-touches

all: app

build:
	swift build

# Builds $(APP).app in the repository root.
app:
	./scripts/build-app.sh

run: app
	open "$(BUNDLE)"

test:
	swift test

# Renders every UI state to ./Snapshots for visual review.
snapshots:
	SLIDESENSE_SNAPSHOT_DIR="$(CURDIR)/Snapshots" swift test --filter "HUDLayoutTests|SettingsWindowTests"
	@echo "Snapshots written to $(CURDIR)/Snapshots"

install: app
	rm -rf "$(INSTALL_DIR)/$(BUNDLE)"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@echo "Installed to $(INSTALL_DIR)/$(BUNDLE)"

uninstall:
	rm -rf "$(INSTALL_DIR)/$(BUNDLE)"

clean:
	rm -rf .build "$(BUNDLE)"

# Prints raw trackpad contacts — useful when tuning edge geometry.
dump-touches:
	swift run SlideSense --dump-touches
