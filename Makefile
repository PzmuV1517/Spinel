.PHONY: build test app run install release icon diagnose clean

build:
	swift build

test:
	swift test

app:
	./scripts/bundle.sh

run: app
	-pkill -x Spinel
	open build/Spinel.app

install: app
	-pkill -x Spinel
	rm -rf /Applications/Spinel.app
	mv build/Spinel.app /Applications/  # move, so Spotlight sees one copy
	open /Applications/Spinel.app

# Zipped, signed app for a GitHub release: build/Spinel-<version>.zip
release: app
	ditto -c -k --keepParent build/Spinel.app build/Spinel-$$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist).zip

icon:
	swift scripts/make-icon.swift

diagnose: build
	.build/debug/Spinel --diagnose

clean:
	rm -rf .build build
