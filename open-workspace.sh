#!/bin/bash

# Opens Axon.xcodeproj in Xcode.
# This project uses SPM (not CocoaPods). No pod install needed.

set -e

if [ ! -d "Axon.xcodeproj" ]; then
    echo "Error: Axon.xcodeproj not found. Run this script from the repo root."
    exit 1
fi

echo "Closing any open Xcode windows..."
osascript -e 'quit app "Xcode"' 2>/dev/null || true
sleep 1

echo "Opening Axon.xcodeproj..."
open Axon.xcodeproj

echo ""
echo "Opened. Next steps:"
echo "  1. Wait for Xcode to resolve SPM packages (may take a minute on first open)"
echo "  2. Set your development team in Signing & Capabilities"
echo "  3. Press Cmd+B to build"
echo ""
echo "See README.md for full setup instructions."
