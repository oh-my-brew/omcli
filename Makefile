VERSION := $(shell tr -d '\n' < VERSION)

.PHONY: build

build:
	mkdir -p bin
	sed 's/@VERSION@/$(VERSION)/g' src/omcli.sh > bin/omcli
	chmod +x bin/omcli
	clang -F /System/Library/PrivateFrameworks -framework login -o bin/omcli-lockscreen src/lockscreen.c
	swiftc -O -target arm64-apple-macosx13.0 -o bin/omcli-sidecar src/sidecar.swift
