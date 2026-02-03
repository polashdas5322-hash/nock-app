# Vibe 🎤

**Voice-First Interactive Widget Platform**

A Flutter application that enables sending voice messages that appear directly on your friends' home screens.

## ✨ Features

### Core Features
- **📸 Photo + Voice Messages**: Capture a photo and record a voice note to send as a "Vibe"
- **🏠 Home Screen Widget**: Messages appear directly on the recipient's home screen
- **🎬 Video Mode**: Record video with audio (Android parity)
- **⏰ Time Travel**: Send photos from your gallery with the original date tag
- **🗄️ Memory Vault**: Calendar view of all your vibes (last 24h free, older requires Vibe+)
- **👥 Squad Management**: Manage your close friends, see their status
- **🔔 Nudge**: Poke friends who haven't sent a vibe in a while
- **💬 Instant Reply**: Hold to record a quick reply after listening

### Widget Features
- **Android**: Glance-like widget with background audio playback (no app opening required)
- **iOS**: WidgetKit widget with AppIntents for interactive audio (iOS 17+)
- **Real-time Updates**: FCM push notifications update widget state

### Design System: "Cyberpunk Noir"
- Dark base colors (#0A0A0A, #0D0D15)
- Neon cyan accent (#00F0FF)
- Hot pink secondary (#FF0099)
- Glassmorphic UI components
- Aura visualization (animated mood-based blob)
- Monospaced typography (JetBrains Mono / Space Mono)

## 🚀 Getting Started

### Prerequisites
- Flutter SDK 3.9.2+
- Android Studio / Xcode
- Firebase project

### Installation

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/vibe.git
   cd vibe
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Firebase**
   
   Replace the placeholder files with your actual Firebase configuration:
   - Android: `android/app/google-services.json`
   - iOS: `ios/Runner/GoogleService-Info.plist`

4. **Run the app**
   ```bash
   flutter run
   ```

## 📱 Platform-Specific Setup

### Android Widget Setup
The Android widget is already configured in:
- `android/app/src/main/kotlin/com/vibe/vibe/VibeWidgetProvider.kt`
- `android/app/src/main/kotlin/com/vibe/vibe/VibeAudioService.kt`
- `android/app/src/main/res/layout/vibe_widget_layout.xml`

### iOS Widget Setup (Requires Xcode)

1. **Open in Xcode**
   ```bash
   open ios/Runner.xcworkspace
   ```

2. **Add Widget Extension Target**
   - File → New → Target → Widget Extension
   - Name: "VibeWidget"
   - Enable "Include Live Activity" if desired

3. **Configure App Groups**
   - Select Runner target → Signing & Capabilities → + App Groups
   - Add: `group.com.vibe.vibe`
   - Do the same for VibeWidget target

4. **Copy Widget Files**
   The Swift files are in `ios/VibeWidget/`:
   - `VibeWidget.swift`
   - `VibeWidgetBundle.swift`
   - `AudioPlaybackIntent.swift`

5. **Update Info.plist**
   Add NSAppTransportSecurity settings if needed for audio URLs

## 🏗️ Project Structure

```
lib/
├── core/
│   ├── constants/          # App-wide constants
│   ├── models/             # Data models (User, Vibe, Squad)
│   ├── router/             # GoRouter configuration
│   ├── services/           # Business logic services
│   └── theme/              # Cyberpunk Noir theme
├── features/
│   ├── auth/               # Phone authentication
│   ├── camera/             # Camera + voice recording
│   ├── home/               # Main app shell
│   ├── onboarding/         # Splash, permissions, widget setup
│   ├── player/             # Ghost player screen
│   ├── squad/              # Friend management
│   └── vault/              # Memory calendar
└── shared/
    └── widgets/            # Reusable UI components
```

## 🔧 Configuration

### Firebase Rules (Firestore)
```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /users/{userId} {
      allow read, write: if request.auth.uid == userId;
    }
    match /vibes/{vibeId} {
      allow read: if request.auth.uid in resource.data.recipientIds 
                   || request.auth.uid == resource.data.senderId;
      allow create: if request.auth != null;
    }
  }
}
```

### Firebase Storage Rules
```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /vibes/{vibeId}/{allPaths=**} {
      allow read, write: if request.auth != null;
    }
  }
}
```

## 📋 TODO / Known Issues

- [ ] Full Firebase integration (replace placeholder configs)
- [ ] Complete Vibe sending flow (upload to Storage + create in Firestore)
- [ ] User profile management (display name, avatar)
- [ ] In-app purchase integration for Vibe+ subscription
- [ ] FCM Cloud Functions for real-time widget updates
- [ ] End-to-end encryption for voice messages
- [ ] AI transcription (Speech-to-Text)
- [ ] Video export with Aura animation overlay

## 📄 License

MIT License

## 🤝 Contributing

Contributions are welcome! Please read the contributing guidelines first.
