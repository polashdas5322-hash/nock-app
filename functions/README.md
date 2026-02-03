# Firebase Cloud Functions Setup

This folder contains the Cloud Functions that power real-time widget updates.

## Overview

The **Push-to-Update Pipeline** works like this:

1. **User A sends a Vibe** → Firestore `widgetState` is updated
2. **Cloud Function detects the change** → Sends silent FCM push to User B
3. **User B's app wakes up in background** → Updates the home screen widget
4. **Widget shows new Vibe** → Magic! ✨

## Files

| File | Description |
|------|-------------|
| `index.js` | Cloud Functions for FCM push notifications |
| `package.json` | Node.js dependencies |

## Deployment Steps

### Prerequisites

1. Install Firebase CLI:
```bash
npm install -g firebase-tools
```

2. Login to Firebase:
```bash
firebase login
```

3. Initialize Firebase in your project (if not already):
```bash
firebase init
```

### Deploy Functions

```bash
cd functions
npm install
firebase deploy --only functions
```

## Functions

### `sendWidgetUpdate`

**Trigger:** `users/{userId}` document update

**Purpose:** Sends a SILENT push notification when `widgetState` changes.

**Important:** This is a DATA message (no `notification` field). This allows:
- Android: App wakes up via `onBackgroundMessage`
- iOS: App wakes up via background handler

### `sendVibeNotification`

**Trigger:** `vibes/{vibeId}` document creation

**Purpose:** Sends a VISIBLE notification when a new Vibe is created.

### `sendNudgeNotification`

**Trigger:** `nudges/{nudgeId}` document creation

**Purpose:** Sends a nudge notification to remind friends.

## Testing

### Check Logs
```bash
firebase functions:log
```

### Test Locally (Optional)
```bash
cd functions
npm run serve
```

## Firestore Requirements

User documents need these fields:

```javascript
{
  "fcmToken": "abc123...",  // FCM token for push
  "widgetState": {
    "latestVibeId": "...",
    "latestAudioUrl": "...",
    "latestImageUrl": "...",
    "senderName": "...",
    "senderAvatar": "...",
    "audioDuration": 10,
    "timestamp": Timestamp,
    "isPlayed": false
  }
}
```

## Troubleshooting

### Functions Not Deploying
- Check you have billing enabled (required for external network calls)
- Verify Firebase project is properly linked

### Push Not Received
- Check FCM token is saved to user document
- Verify token is valid (not expired)
- Check function logs for errors

### Widget Not Updating
- Verify background handler is registered in `main.dart`
- Check App Groups are configured (iOS)
- Verify `home_widget` is properly set up

## Cost Considerations

Cloud Functions cost is based on:
- **Invocations:** ~$0.40 per million
- **Compute time:** ~$0.000025 per GB-second

For a small app (1000 users, 10 vibes/day each):
- ~10,000 function calls/day = ~$0.12/month

Very affordable for an MVP!
