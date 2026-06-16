# Distribution Guide

Didact is distributed directly (not via the Mac App Store) with Apple notarization
for Gatekeeper approval. It isn't sandboxed (DDC needs raw IOKit access), so the
App Store isn't an option anyway.

## Prerequisites

1. **Apple Developer account** ($99/year)
2. **Developer ID Application certificate** (Xcode → Settings → Accounts → Manage Certificates → `+` → Developer ID Application)
3. **App-specific password** from https://appleid.apple.com (Security → App-Specific Passwords)

## One-time setup

Store credentials in the keychain so the script can notarize non-interactively:

```bash
xcrun notarytool store-credentials "notarytool-password" \
  --apple-id "matt.sephton@gmail.com" \
  --team-id "Q3Z639YB49" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

## Build a notarized DMG

```bash
./scripts/notarize.sh
```

This archives (Release) → exports with Developer ID signing → notarizes & staples
the app → builds a drag-to-Applications DMG → notarizes & staples the DMG →
verifies with `spctl`. Output lands in `build/`:

- `build/export/Didact.app`
- `build/Didact.dmg`

## Manual steps (equivalent)

```bash
xcodebuild -project Didact.xcodeproj -scheme Didact -configuration Release \
  -archivePath build/Didact.xcarchive archive

xcodebuild -exportArchive -archivePath build/Didact.xcarchive \
  -exportPath build/export -exportOptionsPlist ExportOptions.plist

ditto -c -k --keepParent build/export/Didact.app build/Didact.zip
xcrun notarytool submit build/Didact.zip --keychain-profile notarytool-password --wait
xcrun stapler staple build/export/Didact.app

hdiutil create -volname Didact -srcfolder build/export/Didact.app -ov -format UDZO build/Didact.dmg
xcrun notarytool submit build/Didact.dmg --keychain-profile notarytool-password --wait
xcrun stapler staple build/Didact.dmg
```

## Verify

```bash
spctl -a -v build/export/Didact.app          # → accepted, source=Notarized Developer ID
xcrun stapler validate build/Didact.dmg
```

## Notes

- **Hardened Runtime is required** for notarization and is already enabled
  (`ENABLE_HARDENED_RUNTIME = YES`).
- Didact links `CoreDisplay` and resolves private `IOAVService*` symbols at runtime
  (`@_silgen_name`). This is dynamic linking, not a build-time framework, so it
  notarizes fine — the same approach MonitorControl/m1ddc ship with.
- If macOS reports the app as "damaged" during local testing, it's a quarantine
  flag, not a signing failure: `xattr -cr build/export/Didact.app`.

## Troubleshooting

Get the detailed notarization log for a submission:

```bash
xcrun notarytool log <submission-id> --keychain-profile notarytool-password
```
