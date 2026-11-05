#!/bin/zsh
# Checks formatting with the swift-format that ships with the toolchain.
set -euo pipefail
cd "${0:a:h}/.."

xcrun swift-format lint --strict --recursive --parallel App Packages
