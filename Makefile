.PHONY: generate build run test cli lint format clean
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
