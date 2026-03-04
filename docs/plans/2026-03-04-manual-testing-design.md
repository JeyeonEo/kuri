# Manual Testing: Real Device + Real Notion

## Prerequisites

- iPhone (iOS 17+) on same Wi-Fi as Mac
- Xcode 15.1+ with paid Apple Developer account
- `xcodegen` installed (`brew install xcodegen`)
- Node.js installed

## 1. Create Notion Integration (One-time)

1. Go to https://www.notion.so/my-integrations
2. Click **Create new integration**
3. Name: "KURI Dev", Type: **Public integration**
4. Under **Capabilities**, enable: Read content, Update content, Insert content
5. Under **Distribution** → Redirect URIs, add:
   `http://<YOUR_MAC_IP>:8787/v1/oauth/notion/callback`
6. Copy **OAuth client ID** and **OAuth client secret**

## 2. Run Setup Script

```bash
./scripts/device-test-setup.sh
```

This will:
- Detect your Mac's local IP
- Create `backend/.env` with your Notion credentials (or update existing)
- Patch `AppModel.swift` to use your IP instead of `localhost`
- Run `xcodegen generate`

## 3. Xcode Signing (One-time)

1. Open `ios/Kuri.xcodeproj`
2. Select **KuriApp** target → Signing & Capabilities → select your Team
3. Select **KuriShareExtension** target → same

## 4. Run

```bash
# Terminal 1: backend
cd backend && npm start

# Xcode: select iPhone → Cmd+R
```

## 5. Test Scenarios

### A. Notion OAuth Connect
1. Tap "Notion 연결" in app
2. Authorize in browser → app reopens with connection confirmed
3. Workspace name visible in app

### B. Share Extension Capture
1. Share a URL from Safari/Threads/Instagram
2. Select "Kuri" → add tags/memo → Save
3. Open Kuri app → item appears in list

### C. Sync to Notion
1. Tap sync in app
2. Check Notion workspace → page created with correct title, URL, tags, memo

### D. Image + OCR
1. Share a screenshot
2. Wait for OCR (few seconds in main app)
3. Sync → Notion page has OCR text

### E. Offline → Online
1. Disable Wi-Fi → capture something → status shows "pending"
2. Re-enable Wi-Fi → sync → status shows "synced"

### F. Sync Failure & Retry
1. Stop backend → try sync → fails
2. Restart backend → sync → succeeds

### G. Disconnect
1. Settings → Disconnect Notion → confirm
2. Try sync → prompts to reconnect

## 6. Teardown

```bash
./scripts/device-test-teardown.sh
```

Reverts `AppModel.swift` back to `localhost:8787`.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Can't detect IP | Check Wi-Fi connection, try `ipconfig getifaddr en0` |
| Device can't reach backend | Same Wi-Fi? Check macOS firewall (System Settings → Firewall) |
| OAuth doesn't return to app | Verify redirect URI matches in both Notion integration settings and `backend/.env` |
| Share extension missing | Build both targets in Xcode, check App Group entitlements |
| OCR not running | Vision framework requires real device (not simulator) |
