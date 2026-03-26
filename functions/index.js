const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendNotification = onDocumentCreated("notifications/{id}", async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const title = data.title || "D Shop";
    const message = data.message || "New Update";
    const screen = data.data && data.data.screen ? data.data.screen : "notifications";
    
    // [FIXED] type রিসিভ করা হচ্ছে যাতে ফোনের ব্যাকগ্রাউন্ড বুঝতে পারে
    const type = data.type || (data.data && data.data.type) || "default";

    // ১. টপিক নির্ধারণ লজিক
    let topicName = data.topic || null;
    if (!topicName && data.target_role) {
        if (data.target_role === 'rider') topicName = 'riders';
        else if (data.target_role === 'seller') topicName = 'sellers';
        else if (data.target_role === 'admin') topicName = 'admins';
        else topicName = 'all_users';
    }

    // ২. সাউন্ড এবং চ্যানেল সেটিংস
    let channelId = "d_shop_channel";
    let soundName = "default";

    if (topicName === "riders" || type === "rider_job") {
        channelId = "rider_job_channel";
        soundName = "rider_alert";
    } else if (topicName === "admins") {
        channelId = "admin_order_channel";
        soundName = "admin_order";
    }

    const messagePayload = {
        notification: { title: title, body: message },
        // [FIXED] ফোনের কাছে type পাঠানো হচ্ছে
        data: { screen: screen, type: type, click_action: "FLUTTER_NOTIFICATION_CLICK" }, 
        android: {
            priority: "high",
            notification: { channelId: channelId, sound: soundName, priority: "high" }
        },
        apns: {
            payload: { aps: { sound: soundName === "default" ? "default" : soundName + ".mp3" } }
        }
    };

    try {
        if (topicName) {
            // টপিক বা ব্রডকাস্ট মেসেজ পাঠানো
            await admin.messaging().send({ topic: topicName, ...messagePayload });
            console.log(`Sent to Topic: ${topicName}`);
        } else if (data.target_user_id) {
            // পার্সোনাল মেসেজ
            const userDoc = await admin.firestore().collection("users").doc(data.target_user_id).get();
            if (userDoc.exists && userDoc.data().fcm_token) {
                await admin.messaging().send({ token: userDoc.data().fcm_token, ...messagePayload });
                console.log(`Sent to User: ${data.target_user_id}`);
            }
        }
    } catch (error) { console.error("FCM Error:", error); }
    return null;
});