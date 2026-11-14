#!/usr/bin/env bash
set -e

# Setup script for native assets in Digital Books
# Generates .dart_tool/native_assets.yaml required by pdfium_dart on macOS/host OS JIT tests.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "Initializing native assets (pdfium_dart, sqlite3, objective_c)..."
dart run tool/setup_native_assets.dart

if [ -f ".dart_tool/native_assets.yaml" ]; then
  echo "✓ Native assets successfully verified at .dart_tool/native_assets.yaml"
else
  echo "✗ Error: .dart_tool/native_assets.yaml was not generated."
  exit 1
fi
