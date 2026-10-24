VERSION := $(shell tr -d '\n' < VERSION)

.PHONY: build build-cli build-lockscreen build-sidecar

build: build-cli build-lockscreen build-sidecar

build-cli:
	mkdir -p bin
	cat src/core.sh src/commands/lockscreen.sh src/commands/sidecar.sh \
		src/commands/ncdu.sh src/commands/iphone.sh \
		src/commands/codex.sh src/commands/update.sh src/main.sh | \
		sed 's/@VERSION@/$(VERSION)/g' > bin/omcli
	chmod +x bin/omcli

build-lockscreen:
	mkdir -p bin
	clang -O2 -Wall -Wextra -o bin/omcli-lockscreen src/lockscreen.c -framework ApplicationServices -framework CoreFoundation -framework IOKit

build-sidecar:
	mkdir -p bin
	swiftc -O -target arm64-apple-macosx13.0 -o bin/omcli-sidecar src/sidecar.swift
