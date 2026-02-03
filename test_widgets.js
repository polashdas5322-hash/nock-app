const admin = require('firebase-admin');

// 1. Setup
// You need to download your Service Account Key from Firebase Console:
// Project Settings -> Service Accounts -> "Generate New Private Key"
// Save it as "service-account.json" in this same folder.
const serviceAccount = require('./service-account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const db = admin.firestore();
const messaging = admin.messaging();

console.log("🚀 Laptop Backend Running...");
console.log("🔍 Listening for NEW Vibes (updates Nock & Squad Widgets)...");

// 2. Main Logic: Listen to Firestore 'vibes' collection
db.collection('vibes').onSnapshot((snapshot) => {
  snapshot.docChanges().forEach(async (change) => {
    // We only care about NEW vibes (added)
    if (change.type === 'added') {
      const vibe = change.doc.data();
      const vibeId = change.doc.id;
      
      // Ignore old vibes (older than 2 minutes) to avoid spamming on startup
      const now = Date.now();
      // Handle Firestore Timestamp vs Date
      let vibeTime = now;
      if (vibe.createdAt && vibe.createdAt._seconds) {
        vibeTime = vibe.createdAt._seconds * 1000;
      } else if (vibe.createdAt && vibe.createdAt.toMillis) {
        vibeTime = vibe.createdAt.toMillis();
      }
      
      if (now - vibeTime > 120000) return; // Ignore if > 2 mins old

      console.log(`📢 New Vibe detected from ${vibe.senderName}! Preparing Payload...`);

      // 3. Get the Receiver's FCM Token
      if (!vibe.receiverId) {
        console.log("❌ Error: Vibe has no receiverId");
        return;
      }

      const userDoc = await db.collection('users').doc(vibe.receiverId).get();
      if (!userDoc.exists) {
        console.log(`❌ Error: Receiver ${vibe.receiverId} not found in users collection`);
        return;
      }
      
      const fcmToken = userDoc.data().fcmToken;

      if (fcmToken) {
        // 4. Send the "Data Message" (Silent Push)
        // This payload MUST match what WidgetUpdateService parser expects
        const payload = {
          token: fcmToken,
          data: {
             type: 'WIDGET_UPDATE', // Critical: This triggers the background handler
             vibeId: vibeId,
             senderId: vibe.senderId || '',
             senderName: vibe.senderName || 'Friend',
             senderAvatar: vibe.senderAvatar || '',
             audioUrl: vibe.audioUrl || '',
             imageUrl: vibe.imageUrl || '',
             videoUrl: vibe.videoUrl || '',
             audioDuration: String(vibe.audioDuration || 0),
             transcription: vibe.transcription || '', // 3-Word Hook
             // Boolean flags as Strings (FCM data is always string)
             isVideo: String(vibe.isVideo || false),
             isAudioOnly: String(vibe.isAudioOnly || false),
             timestamp: String(vibeTime)
          }
        };

        try {
          await messaging.send(payload);
          console.log(`✅ WIDGET UPDATE SENT to ${vibe.receiverId} (Token: ${fcmToken.substring(0,6)}...)`);
          console.log(`   Content: ${vibe.isVideo ? 'VIDEO' : (vibe.isAudioOnly ? 'AUDIO-ONLY' : 'PHOTO')}`);
        } catch (error) {
          console.log("❌ Error sending FCM:", error);
        }
      } else {
        console.log(`⚠️ Receiver ${vibe.receiverId} has no FCM token saved.`);
      }
    }
  });
});

// Optional: Listen for Profile Updates (BFF Widget)
// Not critical for day 1, but good for completeness
