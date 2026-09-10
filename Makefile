PROJECT = PodcastAnalyzer.xcodeproj
SCHEME = PodcastAnalyzer
SWIFTLINT = swiftlint
# SwiftLint parses the subcommand first, so --config has to follow it — putting
# it in the SWIFTLINT variable makes `analyze` parse as `lint`.
CONFIG = --config .swiftlint.yml
# Newest available iPhone simulator, so this keeps working across Xcode updates.
SIMULATOR_NAME = $(shell xcrun simctl list devices available \
	| grep "iPhone" \
	| tail -1 | sed 's/^[[:space:]]*//' | sed 's/ *(.*) *$$//')
DESTINATION = 'platform=iOS Simulator,name=$(SIMULATOR_NAME)'

ONLY_TESTING ?= PodcastAnalyzerTests

.PHONY: help lint lint_lenient format analyze build build_macos test clean

help: ## Show this list of commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

lint: ## Lint the codebase
	$(SWIFTLINT) lint $(CONFIG) --quiet

lint_lenient: ## Lint, reporting every violation as a warning
	$(SWIFTLINT) lint $(CONFIG) --quiet --lenient

format: ## Autocorrect the violations SwiftLint can fix itself
	$(SWIFTLINT) --fix $(CONFIG)

# The analyzer rules (unused_declaration, unused_import) need a full compile
# log, so this builds first and feeds the log back in. Much slower than `lint`.
analyze: ## Run the dead-code analyzer rules (builds first)
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) \
		clean build | tee /tmp/$(SCHEME)-build.log
	$(SWIFTLINT) analyze $(CONFIG) --quiet --compiler-log-path /tmp/$(SCHEME)-build.log

build: ## Build the Debug configuration for the iOS Simulator
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination $(DESTINATION) build

build_macos: ## Build the Debug configuration for macOS
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-destination 'platform=macOS' build

test: ## Build and run the unit tests
	xcodebuild test -project $(PROJECT) -scheme $(SCHEME) \
		-only-testing:$(ONLY_TESTING) \
		-destination $(DESTINATION)

clean: ## Clean the build artifacts
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
