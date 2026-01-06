# Vision Pro App Distribution Guide

## Distribution Methods for Testing on Physical Devices

---

## Method 1: TestFlight (Recommended)

### Prerequisites:
- Apple Developer Program membership ($99/year)
- App Store Connect access

### Steps:

1. **Open Project in Xcode**:
```bash
open VisionProPlayer/VisionProPlayer.xcodeproj
```

2. **Configure Signing in Xcode**:
   - Project Navigator → VisionProPlayer (target)
   - Signing & Capabilities tab
   - Team: Select your Developer team
   - Bundle Identifier: Must be unique (e.g., `com.yourcompany.visionproplayer`)

3. **Create Archive**:
   - Select Generic visionOS Device as destination
   - Menu: Product → Archive
   - Wait for Archive to complete

4. **Upload to App Store Connect**:
   - Window → Organizer
   - Archives tab → Select your app
   - Distribute App
   - App Store Connect → Upload
   - Include bitcode: Yes
   - Strip Swift symbols: Yes (optional)
   - Upload

5. **Configure TestFlight**:
   - Go to [App Store Connect](https://appstoreconnect.apple.com)
   - My Apps → Your app
   - TestFlight tab
   - Internal Testing or External Testing
   - Add Testers → Enter testers' emails

6. **Installation by Tester**:
   - Tester receives invitation email
   - Downloads TestFlight app from App Store
   - Opens invitation link
   - Installs the app

---

## Method 2: Ad-hoc Distribution

### Prerequisites:
- Apple Developer Program membership
- UDID of target Vision Pro device

### Steps:

#### Step 1: Obtain Device UDID

Tester must:
1. Connect Vision Pro to Mac
2. Open Finder and select the device
3. Click on device name to display UDID
4. Copy UDID and send it to you

Or use this tool:
- [get.udid.io](https://get.udid.io) (requires profile installation)

#### Step 2: Register Device in Developer Portal

1. Go to [developer.apple.com/account](https://developer.apple.com/account)
2. Certificates, Identifiers & Profiles
3. Devices → Register a Device
4. Device Name: Choose a name
5. Device ID (UDID): Paste received UDID
6. Continue → Register

#### Step 3: Create Ad-hoc Provisioning Profile

1. In Developer Portal: Profiles → Generate a Profile
2. Distribution → Ad Hoc
3. App ID: Select or create App ID for VisionProPlayer
4. Certificate: Select Distribution Certificate (create if needed)
5. Devices: Select registered device
6. Profile Name: e.g., "VisionProPlayer AdHoc"
7. Generate → Download → Double-click to install

#### Step 4: Export from Xcode

1. Open project in Xcode
2. Configure Signing:
   - Signing & Capabilities
   - Disable Automatically manage signing
   - Provisioning Profile: Select created Ad-hoc profile

3. Archive:
   - Select Generic visionOS Device
   - Product → Archive

4. Export:
   - Window → Organizer → Archives
   - Distribute App
   - Ad Hoc
   - Next → Select Provisioning Profile
   - Export → Choose save location

5. **The .ipa file is created!**

#### Step 5: Send .ipa File

Send the .ipa file via:
- Email (if size permits)
- Google Drive / Dropbox / iCloud
- WeTransfer

#### Step 6: Installation by Tester

**Option A: Using Apple Configurator (Mac)**
1. Download Apple Configurator 2
2. Connect Vision Pro to Mac
3. Apps → Add Apps
4. Select .ipa file

**Option B: Using Xcode**
1. Connect Vision Pro to Mac
2. Xcode → Window → Devices and Simulators
3. Select device
4. Installed Apps → "+" → Select .ipa file

**Option C: Using OTA (Over The Air) Services**
- [diawi.com](https://www.diawi.com)
- [installonair.com](https://www.installonair.com)

Upload .ipa file, get link, tester opens link in Safari and installs.

---

## Method 3: Development Build (Simplest for Single Device)

If you only have one device and want to test quickly:

1. Obtain device UDID (same as Method 2)
2. Register device in Developer Portal
3. In Xcode:
   - Set Team
   - Enable Automatically manage signing
   - Select Generic visionOS Device
   - Product → Archive
   - Distribute App → Development
   - Export

4. Send .ipa file to tester

---

## Important Notes

### Pre-Distribution Checklist:

- [ ] Bundle Identifier is unique
- [ ] Version and Build Number are set
- [ ] WebSocket Server URL is correctly configured in app
- [ ] All required Capabilities are enabled
- [ ] App runs without issues on simulator

### Common Errors:

**"Unable to install"**:
- Device UDID not in Provisioning Profile
- Certificate has expired
- Bundle Identifier mismatch

**"Untrusted Developer"**:
- Settings → General → VPN & Device Management
- Developer App → Trust

**"Could not launch"**:
- Check Capabilities (e.g., Network permissions)
- Review logs in Console.app

---

## Useful Resources

- [Apple Developer Documentation](https://developer.apple.com/documentation/)
- [App Distribution Guide](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [TestFlight Documentation](https://developer.apple.com/testflight/)

---

## Support

If you encounter issues:
1. Check Xcode logs
2. Review device logs in Console.app
3. Ensure all certificates are valid


