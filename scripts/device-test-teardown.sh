#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_MODEL="$ROOT/ios/KuriApp/AppModel.swift"

# Revert any IP address back to localhost
if grep -qE 'http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8787' "$APP_MODEL"; then
    sed -i '' -E 's|http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8787|http://localhost:8787|' "$APP_MODEL"
    echo "Reverted AppModel.swift → localhost:8787"
else
    echo "AppModel.swift already uses localhost"
fi
