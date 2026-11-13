# Installation & Distribution Guide • Digital Books for macOS (Beta Preparation)

This guide covers local macOS builds and the release path being prepared for the macOS beta. Android and iOS are out of scope for this beta.

---

## 1. System Requirements

- **Operating System**: macOS 12.0 (Monterey) or higher.
- **Hardware Architecture**: macOS architectures supported by the selected Flutter/Xcode build environment; each distributed architecture still needs its own build verification.
- **RAM**: Minimum 4 GB, Recommended 8 GB+.
- **Disk Storage**: ~100 MB for the application binary, plus storage for user PDFs and SQLite library files.

---

## 2. Running the Release Build Directly

After building via `flutter build macos --release`, the standalone macOS application bundle is located at:
```
build/macos/Build/Products/Release/Digital Books.app
```

To run the application directly from the terminal or open it in Finder:
```bash
# Launch the release application
open "build/macos/Build/Products/Release/Digital Books.app"
```

To install it into your user Applications directory:
```bash
cp -R "build/macos/Build/Products/Release/Digital Books.app" ~/Applications/
```

---

## 3. Local Build Signing Notes

Local developer builds may use an **ad-hoc code signature** (`flags=0x2(adhoc)`). They are suitable for local verification, not beta distribution to testers.

If you copy the application to another Mac that did not compile the code, macOS Gatekeeper may present an alert:
> *"Digital Books.app cannot be opened because the developer cannot be verified."*

Do not ask beta testers to bypass Gatekeeper or remove quarantine attributes. Prepare a Developer ID signed and notarized package for external beta distribution.

---

## 4. Beta Distribution Signing & Apple Notarization Workflow

For beta distribution outside the Mac App Store (Developer ID), sign the app with a Developer ID certificate and notarize it with Apple's notary service. These steps are a release checklist and must be completed and verified for the actual beta artifact.

### Step 1: Create Apple Developer ID Application Certificate
Ensure you have an active Apple Developer account with a **Developer ID Application** certificate installed in your macOS Keychain:
```bash
security find-identity -v -p codesigning
```

### Step 2: Configure Release Signing in Xcode
1. Open the Xcode workspace:
   ```bash
   open macos/Runner.xcworkspace
   ```
2. Navigate to **Runner target** -> **Signing & Capabilities**.
3. Select your **Apple Developer Team**.
4. Set **Signing Certificate** to `Developer ID Application`.
5. Ensure the bundle identifier matches `com.davindalana.digitalBooks`.

### Step 3: Archive & Sign
```bash
flutter build macos --release
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --entitlements macos/Runner/Release.entitlements \
  "build/macos/Build/Products/Release/Digital Books.app"
```

### Step 4: Package into a ZIP
```bash
ditto -c -k --keepParent "build/macos/Build/Products/Release/Digital Books.app" "DigitalBooks_beta.zip"
```

### Step 5: Submit for Apple Notarization
Submit using the official Apple `notarytool`:
```bash
xcrun notarytool submit "DigitalBooks_beta.zip" \
  --apple-id "your-apple-id@example.com" \
  --password "app-specific-password" \
  --team-id "TEAM_ID" \
  --wait
```

### Step 6: Staple the Notarization Ticket
Once notarization succeeds:
```bash
xcrun stapler staple "build/macos/Build/Products/Release/Digital Books.app"
```

Verify ticket stapling:
```bash
spctl --assess --verbose=4 --type execute "build/macos/Build/Products/Release/Digital Books.app"
# Expected output: source=Notarized Developer ID
```

---

## 5. Storage Locations on macOS

Digital Books stores user data in standard macOS Application Support directories:
- **SQLite Database**: `~/Library/Application Support/com.davindalana.digitalBooks/app_database.sqlite`
- **Extracted Text & Covers**: `~/Library/Application Support/com.davindalana.digitalBooks/`
- **User Backups**: Prompted via native macOS file picker (`.json` or `.bundle`).

