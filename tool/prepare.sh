#!/usr/bin/env bash
# Shared prep for the CI lanes: stamp the resolved toolchain into the
# workspace so every lane log records which Dart built it.
set -euo pipefail
# .dart_tool/ only exists after `dart pub get`; the stamp step runs before
# it (gh-41/gh-47), so create it first.
mkdir -p .dart_tool
dart --version > .dart_tool/toolchain.txt
echo "prep: $(cat .dart_tool/toolchain.txt)"
