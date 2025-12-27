# Extremis Debugging Guide

This document contains debugging tips and procedures for common development scenarios.

---

## Keychain Access Testing

Extremis stores all API keys in a **single keychain entry** as JSON to minimize user prompts. macOS remembers app trust based on code signature.

### How Keychain Trust Works

1. **First access**: macOS prompts "Allow Extremis to access keychain?"
2. **User clicks "Always Allow"**: Trust stored for app's code signature + service name
3. **Subsequent access**: No prompts (trust remembered)

### View Stored API Keys

```bash
# View the keychain entry (will show JSON with all API keys)
security find-generic-password -s "com.extremis.app" -a "api_keys" -g 2>&1
```

### Delete Keychain Entry (Data Only)

```bash
# Delete the API keys entry
security delete-generic-password -s "com.extremis.app" -a "api_keys"
```

> **Note**: This deletes the data but macOS still remembers the app trust. No prompt on next run.

### Revoke Keychain Access (Force Fresh Prompt)

To fully test the "first-run" keychain prompt experience:

#### Method 1: Re-sign the App (Recommended)

```bash
# Delete existing entry
security delete-generic-password -s "com.extremis.app" -a "api_keys"

# Re-sign with ad-hoc signature (changes code signature)
codesign --force --sign - .build/debug/Extremis

# Run the app - should prompt for keychain access
.build/debug/Extremis
```

#### Method 2: Keychain Access App (GUI)

1. Open **Keychain Access** (Spotlight → "Keychain Access")
2. Select **login** keychain in sidebar
3. Search for "extremis" or "com.extremis.app"
4. If entry exists:
   - Right-click → **Get Info**
   - Go to **Access Control** tab
   - Remove "Extremis" from the allowed applications list
   - Click **Save Changes**
5. Delete the entry
6. Run the app - should prompt for keychain access

#### Method 3: Reset Default Keychain (Nuclear Option)

⚠️ **Warning**: This resets ALL keychain data including passwords for other apps!

1. Open **Keychain Access**
2. Go to **Keychain Access → Settings** (or Preferences)
3. Click **Reset My Default Keychain**

---

## Console Logging

### View App Logs

Run the app from terminal to see console output:

```bash
.build/debug/Extremis
```

### KeychainHelper Logs

KeychainHelper only logs **errors** (not normal operations):

| Log Message | Meaning |
|-------------|---------|
| `[KeychainHelper] Failed to decode keychain data` | JSON decode failed - data corrupted |
| `[KeychainHelper] Load failed with status: X` | Keychain read failed unexpectedly |
| `[KeychainHelper] Failed to encode API keys` | JSON encode failed |
| `[KeychainHelper] Save failed with status: X` | Keychain write failed |

**No output = everything working correctly**

### Filter Logs by Component

```bash
# Run and filter for specific component
.build/debug/Extremis 2>&1 | grep -E "\[KeychainHelper\]|\[LLMProvider\]"
```

---

## Common Issues

### Issue: Keychain prompts multiple times

**Cause**: Old storage format (separate entry per API key)

**Fix**: Delete old entries and let new single-entry format take over:
```bash
security delete-generic-password -s "com.extremis.app" -a "api_key_OpenAI"
security delete-generic-password -s "com.extremis.app" -a "api_key_Anthropic"
security delete-generic-password -s "com.extremis.app" -a "api_key_Gemini"
```

### Issue: API keys not loading

**Check**: Verify the keychain entry exists and contains valid JSON:
```bash
security find-generic-password -s "com.extremis.app" -a "api_keys" -g 2>&1
```

### Issue: "errSecAuthFailed" or "-25293"

**Cause**: Keychain is locked or app doesn't have access

**Fix**: Unlock keychain or re-grant access via Keychain Access app

---

## Build & Test

### Run Tests
```bash
cd Extremis && ./scripts/run-tests.sh
```

### Clean Build
```bash
rm -rf .build && swift build
```

### Build Release
```bash
swift build -c release
```

