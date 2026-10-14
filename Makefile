VERSION := $(shell tr -d '\n' < VERSION)

.PHONY: build

build:
	mkdir -p bin
	cat src/core.sh src/commands/lockscreen.sh src/commands/sidecar.sh \
		src/commands/ncdu.sh src/commands/iphone.sh src/commands/sublime.sh \
		src/commands/codex.sh src/main.sh | \
		sed 's/@VERSION@/$(VERSION)/g' > bin/omcli
	chmod +x bin/omcli
	clang -O2 -Wall -Wextra -o bin/omcli-lockscreen src/lockscreen.c -framework ApplicationServices -framework CoreFoundation -framework IOKit
	swiftc -O -target arm64-apple-macosx13.0 -o bin/omcli-sidecar src/sidecar.swift
	mkdir -p bin/omcli-sublime.app/Contents/MacOS
	cp src/SublimeSetup-Info.plist bin/omcli-sublime.app/Contents/Info.plist
	swiftc -O -target arm64-apple-macosx13.0 -o bin/omcli-sublime.app/Contents/MacOS/omcli-sublime src/sublime.swift
