const admin = require('firebase-admin');

// 1. Setup
const serviceAccount = require('./service-account.json');

if (!admin.apps.length) {
    admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
    });
}

const db = admin.firestore();

async function connectAllUsers() {
    console.log("🛠️ Scanning for all users in Firestore...");

    try {
        const usersSnapshot = await db.collection('users').get();
        const userDocs = usersSnapshot.docs;

        if (userDocs.length < 2) {
            console.log(`⚠️ Only found ${userDocs.length} user(s). Need at least 2 users to create friendships.`);
            console.log("Docs found:");
            userDocs.forEach(d => console.log(` - ${d.id} (${d.data().displayName || d.data().email})`));
            return;
        }

        console.log(`✅ Found ${userDocs.length} users. Connecting everyone to everyone...`);

        const batch = db.batch();
        const allUserIds = userDocs.map(doc => doc.id);

        for (const doc of userDocs) {
            const currentUserId = doc.id;
            const otherUserIds = allUserIds.filter(id => id !== currentUserId);

            const updateData = {
                friendIds: admin.firestore.FieldValue.arrayUnion(...otherUserIds),
                lastActive: admin.firestore.FieldValue.serverTimestamp(),
                status: 'online'
            };

            // If displayName is missing, give them a placeholder
            if (!doc.data().displayName && !doc.data().email) {
                updateData.displayName = `User_${currentUserId.substring(0, 4)}`;
                updateData.searchName = updateData.displayName.toLowerCase();
            } else if (!doc.data().displayName && doc.data().email) {
                updateData.displayName = doc.data().email.split('@')[0];
                updateData.searchName = updateData.displayName.toLowerCase();
            }

            batch.set(db.collection('users').doc(currentUserId), updateData, { merge: true });
        }

        await batch.commit();

        console.log("✨ SUCCESS! All users are now friends.");
        console.log("👉 ACTION REQUIRED: Close the app completely and restart to refresh the list.");

    } catch (error) {
        console.error("❌ ERROR:", error);
    }
}

connectAllUsers();
