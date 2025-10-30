#!/bin/bash

# Script to open the correct Xcode workspace for Axon

echo "🔧 Opening Axon workspace..."
echo ""

# Check if workspace exists
if [ ! -d "Axon.xcworkspace" ]; then
    echo "❌ Error: Axon.xcworkspace not found!"
    echo "Running pod install first..."
    pod install
fi

# Close any Xcode instances
echo "📱 Closing any open Xcode windows..."
osascript -e 'quit app "Xcode"' 2>/dev/null

sleep 1

# Open the workspace
echo "✅ Opening Axon.xcworkspace..."
open Axon.xcworkspace

echo ""
echo "✨ Workspace opened!"
echo ""
echo "Next steps:"
echo "1. Wait for Xcode to finish indexing"
echo "2. Press Shift+Cmd+K to clean build folder"
echo "3. Press Cmd+B to build"
echo ""
echo "⚠️  IMPORTANT: Make sure you see 'Axon.xcworkspace' in the window title!"
