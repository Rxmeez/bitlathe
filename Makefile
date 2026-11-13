.PHONY: generate build run test cli lint format clean build-appstore archive archive-direct archive-appstore export notarize dmg install-cli release
generate:
	xcodegen generate --quiet
build: generate
	xcodebuild -project Bitlathe.xcodeproj -scheme Bitlathe -configuration Debug -derivedDataPath .build/DerivedData -destination 'platform=macOS' build | grep -E "error:|warning:|BUILD"
run:
	scripts/run.sh
test:
	swift test
cli:
	swift build -c release --product bl && echo "CLI at .build/release/bl"
lint:
	swiftlint lint --quiet
format:
	swift-format format -i -r Sources App Tests
clean:
	rm -rf .build/DerivedData Bitlathe.xcodeproj
# release: distribution targets (see Docs/Release.md). VERSION=1.2.0 for `make release`; STEPS="--skip-github" etc.
build-appstore:
	scripts/build.sh appstore Debug
archive: archive-direct archive-appstore
archive-direct:
	scripts/archive.sh direct
archive-appstore:
	scripts/archive.sh appstore
export:
	scripts/export.sh all
notarize:
	scripts/notarize.sh build/export/Bitlathe/Bitlathe.app
dmg:
	scripts/dmg.sh
install-cli:
	scripts/install-cli.sh
release:
	scripts/release.sh $(VERSION) $(STEPS)
