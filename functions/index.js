const functions = require("firebase-functions");
const admin = require("firebase-admin");
const path = require("path");
const os = require("os");
const fs = require("fs-extra");
const sharp = require("sharp");
const jwt = require("jsonwebtoken"); // For Apple client_secret generation
const crypto = require("crypto");

admin.initializeApp();

const storage = admin.storage();

/**
 * Vibe Widget Update Cloud Function
 * 
 * Listens for changes to user's widgetState and sends a silent FCM push
 * to wake up the receiver's app and refresh their home screen widget.
 * 
 * This is the "Push-to-Update" pipeline that makes widgets feel real-time.
 */
exports.sendWidgetUpdate = functions.firestore
    .document('users/{userId}')
    .onUpdate(async (change, context) => {
        const userId = context.params.userId;
        const newData = change.after.data();
        const previousData = change.before.data();

        // 1. Check if the 'widgetState' field specifically changed
        const newTimestamp = newData.widgetState?.timestamp;
        const oldTimestamp = previousData.widgetState?.timestamp;

        // If timestamps are the same, no new vibe - skip
        if (newTimestamp === oldTimestamp) {
            return null;
        }

        console.log(`Widget state changed for user: ${userId}`);

        // 2. Get the receiver's FCM Token (stored in their user doc)
        const fcmToken = newData.fcmToken;
        if (!fcmToken) {
            console.log(`No FCM token found for user: ${userId}`);
            return null;
        }

        // 3. Construct the SILENT Data Message
        // CRITICAL: Do NOT add a 'notification' field (title/body). 
        // If you do, the OS handles it as a visible notification and 
        // your app won't wake up to quietly update the widget.
        const widgetState = newData.widgetState || {};

        const payload = {
            data: {
                type: 'WIDGET_UPDATE',
                senderName: widgetState.senderName || 'Friend',
                senderId: widgetState.senderId || '',  // For nudge feature (102 requests)
                senderAvatar: widgetState.senderAvatar || '',
                audioUrl: widgetState.latestAudioUrl || '',
                imageUrl: widgetState.latestImageUrl || '',
                vibeId: widgetState.latestVibeId || '',
                audioDuration: String(widgetState.audioDuration || 0),
                distance: widgetState.distance || '',  // Distance badge (73 requests)
                // 📝 Transcription-First: First 50 chars for widget glanceability
                // Enables reading vibes in meetings/class without playing audio
                // 🪝 3-Word Hook: Now contains AI-generated engagement hook
                transcription: widgetState.transcriptionPreview || '',

                // 🎬 4-State Widget Protocol: Content type flags
                // Enables widgets to show different UI for video/audio-only/photo+audio
                isVideo: String(widgetState.isVideo || false),
                isAudioOnly: String(widgetState.isAudioOnly || false),
                videoUrl: widgetState.videoUrl || '',

                // FIX: Convert Firestore Timestamp to milliseconds, then stringify
                // Previously: String(newTimestamp) produced "[object Object]"
                // newTimestamp is a Firestore Timestamp object with toMillis() method
                timestamp: newTimestamp && typeof newTimestamp.toMillis === 'function'
                    ? String(newTimestamp.toMillis())
                    : String(Date.now())
            },
            token: fcmToken,
            // Android-specific: HIGH priority for immediate delivery
            android: {
                priority: 'high'
            },
            // iOS-specific: content-available for background processing
            apns: {
                headers: {
                    'apns-priority': '10'
                },
                payload: {
                    aps: {
                        'content-available': 1
                    }
                }
            }
        };

        // 4. Send the silent push
        try {
            await admin.messaging().send(payload);
            console.log(`Silent push sent successfully to user: ${userId}`);
            return { success: true };
        } catch (error) {
            console.error(`Error sending push to ${userId}:`, error);

            // If token is invalid, clean it up
            if (error.code === 'messaging/invalid-registration-token' ||
                error.code === 'messaging/registration-token-not-registered') {
                console.log(`Removing invalid token for user: ${userId}`);
                await admin.firestore()
                    .collection('users')
                    .doc(userId)
                    .update({ fcmToken: admin.firestore.FieldValue.delete() });
            }

            return { success: false, error: error.message };
        }
    });

/**
 * Send Vibe Notification (Optional - for visible notifications)
 * 
 * This is separate from the silent widget update.
 * Use this if you also want to show a notification banner.
 */
exports.sendVibeNotification = functions.firestore
    .document('vibes/{vibeId}')
    .onCreate(async (snapshot, context) => {
        const vibe = snapshot.data();
        const receiverId = vibe.receiverId;

        if (!receiverId) return null;

        // Get receiver's FCM token
        const receiverDoc = await admin.firestore()
            .collection('users')
            .doc(receiverId)
            .get();

        if (!receiverDoc.exists) return null;

        const fcmToken = receiverDoc.data().fcmToken;
        if (!fcmToken) return null;

        // Send notification
        const message = {
            notification: {
                title: `${vibe.senderName} sent you a Vibe`,
                body: '🎤 Tap to listen'
            },
            data: {
                type: 'NEW_VIBE',
                vibeId: context.params.vibeId,
                senderId: vibe.senderId
            },
            token: fcmToken
        };

        try {
            await admin.messaging().send(message);
            console.log(`Vibe notification sent for: ${context.params.vibeId}`);
        } catch (error) {
            console.error('Error sending vibe notification:', error);
        }
    });

/**
 * Nudge Notification - "Miss You" / "Poke" Feature
 * 
 * Competitor Analysis: 102 requests for quick interactions.
 * Sends a push when a friend sends you a heart, wave, hug, etc.
 */
exports.sendNudgeNotification = functions.firestore
    .document('nudges/{nudgeId}')
    .onCreate(async (snapshot, context) => {
        const nudge = snapshot.data();
        const receiverId = nudge.receiverId;
        const senderName = nudge.senderName || 'Someone';
        const emoji = nudge.emoji || '❤️';
        const message = nudge.message || 'is thinking of you';

        // Get receiver's FCM token
        const receiverDoc = await admin.firestore()
            .collection('users')
            .doc(receiverId)
            .get();

        if (!receiverDoc.exists) return null;

        const fcmToken = receiverDoc.data().fcmToken;
        if (!fcmToken) return null;

        // Create the notification message
        const notificationMessage = {
            notification: {
                title: `${senderName} ${emoji}`,
                body: `${senderName} ${message}`
            },
            data: {
                type: 'NUDGE',
                nudgeId: context.params.nudgeId,
                senderId: nudge.senderId,
                emoji: emoji,
                nudgeType: nudge.type || 'heart'
            },
            token: fcmToken,
            // Android: High priority for immediate delivery
            android: {
                priority: 'high',
                notification: {
                    channelId: 'nudges',
                    icon: 'ic_notification'
                }
            },
            // iOS: Show immediately
            apns: {
                headers: {
                    'apns-priority': '10'
                },
                payload: {
                    aps: {
                        sound: 'default',
                        badge: 1
                    }
                }
            }
        };

        try {
            await admin.messaging().send(notificationMessage);
            console.log(`Nudge notification sent: ${emoji} from ${senderName}`);
        } catch (error) {
            console.error('Error sending nudge:', error);

            // Clean up invalid tokens
            if (error.code === 'messaging/invalid-registration-token' ||
                error.code === 'messaging/registration-token-not-registered') {
                await admin.firestore()
                    .collection('users')
                    .doc(receiverId)
                    .update({ fcmToken: admin.firestore.FieldValue.delete() });
            }
        }
    });

/**
 * Server-Side Image Resizing for Widgets
 * 
 * CRITICAL: iOS widgets have a 30MB memory limit.
 * A 4K photo (5MB) expands to 40MB+ in RAM when decoded.
 * This function resizes images to 300x300px (perfect for widgets).
 * 
 * This prevents widget crashes and saves bandwidth.
 */
exports.generateThumbnail = functions.storage.object().onFinalize(async (object) => {
    const fileBucket = object.bucket;
    const filePath = object.name;
    const contentType = object.contentType;

    // 1. Exit if not an image
    if (!contentType || !contentType.startsWith('image/')) {
        console.log('Not an image, skipping.');
        return null;
    }

    // 2. Exit if already a thumbnail (prevent infinite loops)
    const fileName = path.basename(filePath);
    if (fileName.startsWith('thumb_')) {
        console.log('Already a thumbnail, skipping.');
        return null;
    }

    // 3. Exit if not in vibes storage path (only resize vibe images)
    if (!filePath.includes('/vibes/') && !filePath.includes('/images/')) {
        console.log('Not a vibe image, skipping.');
        return null;
    }

    console.log(`Generating thumbnail for: ${filePath}`);

    // 4. Define paths
    const bucket = storage.bucket(fileBucket);
    const workingDir = path.join(os.tmpdir(), 'thumbs');
    const tempFilePath = path.join(workingDir, fileName);
    const thumbFileName = `thumb_${fileName}`;
    const tempThumbPath = path.join(workingDir, thumbFileName);
    const storageThumbPath = path.join(path.dirname(filePath), thumbFileName);

    try {
        // 5. Create temp directory
        await fs.ensureDir(workingDir);

        // 6. Download original image
        await bucket.file(filePath).download({ destination: tempFilePath });

        // 7. Resize to 300x300 (perfect for widgets)
        await sharp(tempFilePath)
            .resize(300, 300, {
                fit: 'cover',
                position: 'center'
            })
            .jpeg({ quality: 80 }) // Compress for fast widget loading
            .toFile(tempThumbPath);

        // 8. Upload thumbnail with public read access
        await bucket.upload(tempThumbPath, {
            destination: storageThumbPath,
            metadata: {
                contentType: 'image/jpeg',
                cacheControl: 'public, max-age=31536000', // Cache for 1 year
            },
        });

        console.log(`Thumbnail created: ${storageThumbPath}`);

        // 9. Cleanup temp files
        await fs.remove(workingDir);

        return { success: true, thumbnail: storageThumbPath };
    } catch (error) {
        console.error('Error generating thumbnail:', error);
        // Cleanup on error
        await fs.remove(workingDir).catch(() => { });
        return { success: false, error: error.message };
    }
});

/**
 * Helper: Get thumbnail URL from original URL
 * 
 * Converts: path/to/image.jpg -> path/to/thumb_image.jpg
 */
function getThumbnailUrl(originalUrl) {
    if (!originalUrl) return '';
    try {
        const url = new URL(originalUrl);
        const pathParts = url.pathname.split('/');
        const filename = pathParts.pop();
        pathParts.push(`thumb_${filename}`);
        url.pathname = pathParts.join('/');
        return url.toString();
    } catch (e) {
        return originalUrl; // Fallback to original if parsing fails
    }
}

/**
 * 🍎 Apple Sign-In Token Revocation (App Store Guideline 5.1.1(v))
 * 
 * CRITICAL: Apple REQUIRES apps to revoke OAuth tokens when a user deletes their account.
 * Failure to implement this will result in App Store rejection.
 * 
 * This callable function:
 * 1. Generates a client_secret JWT using the Apple P8 private key
 * 2. Calls Apple's /auth/revoke endpoint
 * 
 * Security: The P8 key is stored in Firebase Functions config (firebase functions:config:set)
 * Command: firebase functions:config:set apple.team_id="XXXXX" apple.key_id="XXXXX" apple.private_key="-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"
 */
exports.revokeAppleToken = functions.https.onCall(async (data, context) => {
    // 1. Verify the user is authenticated
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }

    const { authorizationCode, refreshToken } = data;

    // We need either an authorizationCode to exchange OR a stored refreshToken
    if (!authorizationCode && !refreshToken) {
        throw new functions.https.HttpsError('invalid-argument', 'authorizationCode or refreshToken required');
    }

    try {
        // 2. Load Apple credentials from Firebase Config
        // Set these with: firebase functions:config:set apple.team_id="..." apple.key_id="..." apple.client_id="..." apple.private_key="..."
        const config = functions.config().apple || {};
        const teamId = config.team_id;
        const keyId = config.key_id;
        const clientId = config.client_id || 'com.nock.app'; // Your app's bundle ID
        const privateKey = (config.private_key || '').replace(/\\n/g, '\n');

        if (!teamId || !keyId || !privateKey) {
            console.error('Apple credentials not configured. Run: firebase functions:config:set apple.team_id=... apple.key_id=... apple.private_key=...');
            throw new functions.https.HttpsError('failed-precondition', 'Apple Sign-In not configured on server');
        }

        // 3. Generate client_secret JWT (required by Apple)
        const clientSecret = jwt.sign({}, privateKey, {
            algorithm: 'ES256',
            expiresIn: '5m',
            audience: 'https://appleid.apple.com',
            issuer: teamId,
            subject: clientId,
            keyid: keyId,
        });

        let tokenToRevoke = refreshToken;

        // 4. If we only have authorizationCode, exchange it for tokens first
        if (!tokenToRevoke && authorizationCode) {
            const tokenResponse = await fetch('https://appleid.apple.com/auth/token', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: new URLSearchParams({
                    client_id: clientId,
                    client_secret: clientSecret,
                    code: authorizationCode,
                    grant_type: 'authorization_code',
                }),
            });

            if (!tokenResponse.ok) {
                const errorText = await tokenResponse.text();
                console.error('Apple token exchange failed:', errorText);
                throw new functions.https.HttpsError('internal', 'Failed to exchange authorization code');
            }

            const tokens = await tokenResponse.json();
            tokenToRevoke = tokens.refresh_token || tokens.access_token;
        }

        if (!tokenToRevoke) {
            throw new functions.https.HttpsError('internal', 'No token available for revocation');
        }

        // 5. Revoke the token
        const revokeResponse = await fetch('https://appleid.apple.com/auth/revoke', {
            method: 'POST',
            headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
            body: new URLSearchParams({
                client_id: clientId,
                client_secret: clientSecret,
                token: tokenToRevoke,
                token_type_hint: 'refresh_token',
            }),
        });

        if (!revokeResponse.ok) {
            const errorText = await revokeResponse.text();
            console.error('Apple token revocation failed:', errorText);
            // Don't throw - allow account deletion to proceed even if revocation fails
            // Apple may have already revoked or token may be expired
            return { success: false, error: 'Revocation request failed, but proceeding with deletion' };
        }

        console.log(`Apple token revoked successfully for user: ${context.auth.uid}`);
        return { success: true };

    } catch (error) {
        console.error('Error in revokeAppleToken:', error);
        // Return success: false but don't throw, to allow account deletion to proceed
        return { success: false, error: error.message };
    }
});

/**
 * 🔐 Phone Number Hash Helper (for contact discovery privacy)
 * 
 * GDPR Compliance: Hash phone numbers with SHA256 + pepper before storing
 * This prevents raw phone numbers from being exposed in case of data breach.
 * 
 * IMPORTANT: This pepper must match the one in contacts_sync_service.dart
 */
const PHONE_NUMBER_PEPPER = 'nock_contact_discovery_2026_v1';

exports.hashPhoneNumber = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError('unauthenticated', 'User must be logged in');
    }

    const { phoneNumber } = data;
    if (!phoneNumber) {
        throw new functions.https.HttpsError('invalid-argument', 'phoneNumber required');
    }

    // Normalize and hash
    const normalized = normalizePhoneNumber(phoneNumber);
    const hash = crypto.createHash('sha256')
        .update(normalized + PHONE_NUMBER_PEPPER)
        .digest('hex');

    return { hash, normalized };
});

/**
 * Helper: Normalize phone number to E.164 format
 */
function normalizePhoneNumber(phone) {
    let normalized = phone.replace(/[^\d+]/g, '');

    if (!normalized.startsWith('+')) {
        normalized = normalized.replace(/\+/g, '');
    }

    if (normalized.length === 10) {
        normalized = '+1' + normalized;
    }

    if (normalized.length === 11 && normalized.startsWith('1')) {
        normalized = '+' + normalized;
    }

    if (normalized.length > 11 && !normalized.startsWith('+')) {
        normalized = '+' + normalized;
    }

    return normalized;
}
