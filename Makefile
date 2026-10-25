.PHONY: build test app run install release icon diagnose clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

run: app
	-pkill -x TileMyMac
	open build/TileMyMac.app

install: app
	-pkill -x TileMyMac
	rm -rf /Applications/TileMyMac.app
	cp -R build/TileMyMac.app /Applications/
	open /Applications/TileMyMac.app

# Zipped, signed app for a GitHub release: build/TileMyMac-<version>.zip
release: app
	ditto -c -k --keepParent build/TileMyMac.app build/TileMyMac-$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist).zip

icon:
	swift scripts/make-icon.swift

diagnose: build
	.build/debug/TileMyMac --diagnose

clean:
	rm -rf .build build
