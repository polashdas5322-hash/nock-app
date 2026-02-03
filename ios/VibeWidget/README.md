# Vibe iOS Widget Setup Guide

## Overview

This folder contains all the Swift code needed for the Vibe home screen widget with interactive audio playback.

## Files

| File | Description |
|------|-------------|
| `VibeWidget.swift` | Main widget UI with SwiftUI, timeline provider, and data model |
| `VibeWidgetBundle.swift` | Widget bundle entry point |
| `AudioPlaybackIntent.swift` | iOS 17+ AppIntent for playing audio from widget |
| `AudioManager.swift` | Audio engine singleton with background playback and Now Playing support |
| `Assets.xcassets/` | Widget colors and assets |

## Xcode Setup Steps

### 1. Add Widget Extension Target

1. Open `ios/Runner.xcworkspace` in Xcode
2. Go to **File → New → Target**
3. Select **Widget Extension**
4. Name it: `VibeWidget`
5. **Uncheck** "Include Live Activity"
6. **Uncheck** "Include Configuration App Intent" (we have our own)
7. Click **Finish**

### 2. Configure App Groups

Both the main app and widget need to share data:

1. Select **Runner** target → **Signing & Capabilities**
2. Click **+ Capability** → **App Groups**
3. Add: `group.com.vibe.vibe`
4. Select **VibeWidget** target → **Signing & Capabilities**
5. Click **+ Capability** → **App Groups**
6. Add the same: `group.com.vibe.vibe`

### 3. Add Swift Files

1. Delete auto-generated files in the VibeWidget folder
2. Copy these files into the VibeWidget target:
   - `VibeWidget.swift`
   - `VibeWidgetBundle.swift`
   - `AudioPlaybackIntent.swift`
   - `AudioManager.swift`
3. Make sure all files are added to the VibeWidget target

### 4. Configure Background Audio

In `VibeWidget` target's **Signing & Capabilities**:

1. Add **Background Modes** capability
2. Check **Audio, AirPlay, and Picture in Picture**

### 5. Update Info.plist

**Note:** Firebase Storage uses HTTPS by default, so you do NOT need to configure App Transport Security. The following is only needed if you're loading images from non-HTTPS sources (not recommended):

```xml
<!-- SECURITY WARNING: Only add this if absolutely necessary for legacy servers -->
<!-- Firebase Storage uses HTTPS - this should NOT be needed -->
<!-- Apple will reject your app if you enable this without justification -->
<!--
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>your-legacy-domain.com</key>
        <dict>
            <key>NSTemporaryExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
-->
```

### 6. Build & Run

1. Select the main `Runner` scheme
2. Build and run on a device (iOS 17+ for interactive audio)
3. Long press home screen → Add Widget → Find "Vibe"

## Features

- ✅ Small and Medium widget sizes
- ✅ Displays sender photo and name
- ✅ "NEW" indicator for unplayed vibes
- ✅ Interactive play button (iOS 17+)
- ✅ Background audio playback
- ✅ Lock screen Now Playing controls
- ✅ Auto-refresh every 15 minutes

## iOS Version Compatibility

| Feature | iOS 14+ | iOS 17+ |
|---------|---------|---------|
| Static Widget | ✅ | ✅ |
| Photo Display | ✅ | ✅ |
| Tap to Open App | ✅ | ✅ |
| **Interactive Audio** | ❌ | ✅ |
| Background Playback | ❌ | ✅ |

## Troubleshooting

### Widget Not Appearing
- Restart the device
- Check that Widget Extension is properly signed

### Audio Not Playing
- Ensure App Groups are configured correctly
- Check that audio URL is valid and accessible
- Verify Background Modes capability is enabled

### "Cannot find AudioManager" Error
- Make sure `AudioManager.swift` is added to the VibeWidget target
- Check that the file is not accidentally added to Runner target only
