#!/usr/bin/env bash
# Shared prep for the CI lanes: stamp the resolved toolchain into the
# workspace so every lane log records which Dart built it.
set -euo pipefail
mkdir -p .dart_tool
dart --version > .dart_tool/toolchain.txt
echo "prep: $(cat .dart_tool/toolchain.txt)"
