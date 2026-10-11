#!/bin/bash
set -e
cd "$(dirname "$0")"

echo "Building AltDrag (universal: arm64 + x86_64)..."
swiftc -O -target arm64-apple-macos12.0 Sources/AltDrag/main.swift -o altdrag-arm64
swiftc -O -target x86_64-apple-macos12.0 Sources/AltDrag/main.swift -o altdrag-x86_64
lipo -create -output altdrag altdrag-arm64 altdrag-x86_64
rm altdrag-arm64 altdrag-x86_64

if [ -f altdrag ]; then
    echo ""
    echo "Build successful! Binary: $(pwd)/altdrag ($(du -h altdrag | cut -f1), universal arm64 + x86_64)"
    echo ""
    echo "Run:"
    echo "  ./altdrag"
    echo ""
    echo "Install to /usr/local/bin:"
    echo "  sudo cp altdrag /usr/local/bin/altdrag"
    echo ""
    echo "First run requires Accessibility permission:"
    echo "  System Settings > Privacy & Security > Accessibility"
else
    echo "Build failed!"
    exit 1
fi
