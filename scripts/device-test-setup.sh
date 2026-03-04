#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_MODEL="$ROOT/ios/KuriApp/AppModel.swift"
ENV_FILE="$ROOT/backend/.env"
ENV_EXAMPLE="$ROOT/backend/.env.example"

# --- Detect local IP ---
LOCAL_IP=""
for iface in en0 en1; do
    LOCAL_IP=$(ipconfig getifaddr "$iface" 2>/dev/null || true)
    [ -n "$LOCAL_IP" ] && break
done

if [ -z "$LOCAL_IP" ]; then
    echo "ERROR: Could not detect local IP. Are you connected to Wi-Fi?"
    exit 1
fi
echo "Detected local IP: $LOCAL_IP"

# --- Create backend/.env if missing ---
if [ ! -f "$ENV_FILE" ]; then
    echo ""
    echo "No backend/.env found. Let's create one."
    echo ""
    read -rp "NOTION_CLIENT_ID: " CLIENT_ID
    read -rp "NOTION_CLIENT_SECRET: " CLIENT_SECRET

    cat > "$ENV_FILE" <<EOF
NOTION_MODE=live
NOTION_CLIENT_ID=$CLIENT_ID
NOTION_CLIENT_SECRET=$CLIENT_SECRET
NOTION_REDIRECT_URI=http://$LOCAL_IP:8787/v1/oauth/notion/callback
PORT=8787
EOF
    echo "Created backend/.env"
else
    # Update redirect URI with current IP
    sed -i '' "s|NOTION_REDIRECT_URI=.*|NOTION_REDIRECT_URI=http://$LOCAL_IP:8787/v1/oauth/notion/callback|" "$ENV_FILE"
    echo "Updated NOTION_REDIRECT_URI in backend/.env"
fi

# --- Patch AppModel.swift with local IP ---
if grep -q 'http://localhost:8787' "$APP_MODEL"; then
    sed -i '' "s|http://localhost:8787|http://$LOCAL_IP:8787|" "$APP_MODEL"
    echo "Patched AppModel.swift: localhost → $LOCAL_IP"
elif grep -q "http://$LOCAL_IP:8787" "$APP_MODEL"; then
    echo "AppModel.swift already uses $LOCAL_IP"
else
    # Different IP was set before — update it
    sed -i '' -E "s|http://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:8787|http://$LOCAL_IP:8787|" "$APP_MODEL"
    echo "Updated AppModel.swift IP → $LOCAL_IP"
fi

# --- Generate Xcode project ---
if command -v xcodegen &>/dev/null; then
    echo "Running xcodegen..."
    cd "$ROOT/ios" && xcodegen generate
else
    echo "WARNING: xcodegen not found. Run 'brew install xcodegen' then 'cd ios && xcodegen generate'"
fi

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Start backend:  cd backend && npm start"
echo "  2. Open Xcode:     open ios/Kuri.xcodeproj"
echo "  3. Select your Team under Signing & Capabilities (both targets)"
echo "  4. Select your iPhone as destination"
echo "  5. Build & Run (Cmd+R)"
echo ""
echo "  IMPORTANT: Update the Notion integration redirect URI to:"
echo "    http://$LOCAL_IP:8787/v1/oauth/notion/callback"
echo ""
echo "  To revert: ./scripts/device-test-teardown.sh"
