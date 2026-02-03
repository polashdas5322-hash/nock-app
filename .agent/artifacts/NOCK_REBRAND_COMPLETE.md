# 🎯 Nock Rebrand Complete

## Summary

Your app has been successfully renamed from **"Vibe"** to **"Nock"**!

---

## 📋 Changes Made

### 1. Flutter/Dart Files
| File | Change |
|------|--------|
| `pubspec.yaml` | `name: vibe` → `name: nock`, updated description |
| `lib/main.dart` | `VibeApp` → `NockApp`, title `'Vibe'` → `'Nock'` |

### 2. Android Configuration
| File | Changes |
|------|---------|
| `android/app/build.gradle.kts` | `com.vibe.vibe` → `com.nock.nock` (namespace + applicationId) |
| `android/app/src/main/AndroidManifest.xml` | App label, deep links (nock.app, getnock.app), intents, notification channel |

### 3. Android Kotlin Files (New com.nock.nock package)
| New File | Replaces |
|----------|----------|
| `MainActivity.kt` | (same functionality) |
| `TrampolineActivity.kt` | Updated references |
| `NockAudioService.kt` | `VibeAudioService.kt` |
| `NockWidgetProvider.kt` | `VibeWidgetProvider.kt` |

### 4. Android Resources
| New File | Replaces |
|----------|----------|
| `res/xml/nock_widget_info.xml` | `vibe_widget_info.xml` |
| `res/layout/nock_widget_layout.xml` | `vibe_widget_layout.xml` |

### 5. iOS Configuration
| File | Changes |
|------|---------|
| `ios/Runner/Info.plist` | Display name `Nock`, permission descriptions, URL scheme `nock://`, app group |
| `ios/Runner.xcodeproj/project.pbxproj` | Bundle ID `com.nock.nock` |
| `ios/Runner/Runner.entitlements` | App group `group.com.nock.nock` |
| `ios/VibeWidget/VibeWidget.swift` | App group references |
| `ios/VibeWidget/AudioPlaybackIntent.swift` | App group references |

---

## 🔧 Post-Rename Tasks

### Required Before Building

1. **Clean and rebuild:**
   ```bash
   flutter clean
   flutter pub get
   ```

2. **Android - Sync Gradle:**
   - Open in Android Studio and sync Gradle files

3. **iOS - Update Pods:**
   ```bash
   cd ios
   pod deintegrate
   pod install
   ```

### Firebase Configuration

⚠️ **IMPORTANT:** Your Firebase project still references `com.vibe.vibe`. You have two options:

**Option A: Update Firebase (Recommended)**
1. Go to [Firebase Console](https://console.firebase.google.com)
2. Add new Android app with `com.nock.nock`
3. Add new iOS app with `com.nock.nock`
4. Download new `google-services.json` and `GoogleService-Info.plist`
5. Replace the files in your project

**Option B: Keep existing Firebase**
- Create a new Firebase project named "Nock"
- Set up fresh configuration

### App Store Connect / Google Play

When submitting:
- New bundle IDs: `com.nock.nock` (iOS & Android)
- New app listings will be required (different bundle ID = different app)

---

## 📁 Old Files to Remove (Optional Cleanup)

These old files can be safely deleted:
```
android/app/src/main/res/xml/vibe_widget_info.xml
android/app/src/main/res/layout/vibe_widget_layout.xml
```

---

## ✅ Quick Verification

Run these commands to verify the rename:

```bash
# Check pubspec
grep "^name:" pubspec.yaml
# Expected: name: nock

# Check Android package
grep "applicationId" android/app/build.gradle.kts
# Expected: applicationId = "com.nock.nock"

# Check iOS bundle ID  
grep "PRODUCT_BUNDLE_IDENTIFIER" ios/Runner.xcodeproj/project.pbxproj | head -1
# Expected: com.nock.nock
```

---

## 🚀 Your New Brand Identity

- **App Name:** Nock
- **Package ID:** com.nock.nock
- **URL Scheme:** nock://
- **Deep Links:** nock.app, getnock.app
- **App Group:** group.com.nock.nock

Good luck with your launch! 🎉
