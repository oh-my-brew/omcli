VERSION := $(shell tr -d '\n' < VERSION)

.PHONY: build

build:
	mkdir -p bin
	sed 's/@VERSION@/$(VERSION)/g' src/omcli.sh > bin/omcli
	chmod +x bin/omcli
	clang -O2 -Wall -Wextra -o bin/omcli-lockscreen src/lockscreen.c -framework ApplicationServices -framework CoreFoundation -framework IOKit
	swiftc -O -target arm64-apple-macosx13.0 -o bin/omcli-sidecar src/sidecar.swift
