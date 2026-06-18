#!/bin/zsh
# Builds the screenshot-renamer binary with swiftc directly.
# (SwiftPM's `swift build` is broken on this Command Line Tools beta, and the @Generable
#  macro plugin ships only with full Xcode — so we compile the sources by hand.)
set -e
cd "$(dirname "$0")"
SDK=$(xcrun --sdk macosx --show-sdk-path)
swiftc -O \
  -sdk "$SDK" \
  -target arm64-apple-macos27.0 \
  -o screenshot-renamer \
  Sources/screenshot-renamer/Renamer.swift \
  Sources/screenshot-renamer/main.swift
echo "built ./screenshot-renamer"
