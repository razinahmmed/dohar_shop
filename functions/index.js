const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const axios = require("axios"); // 👈 ফেসবুক এপিআই-তে রিকোয়েস্ট পাঠানোর জন্য
const crypto = require("crypto"); // 👈 কাস্টমার ডাটা সিকিউর (Hash) করার জন্য

admin.initializeApp();

// ==========================================
// ১. পুশ নোটিফিকেশন পাঠানোর ফাংশন (আপনার আগের কোড)
// ==========================================
exports.sendNotification = onDocumentCreated("notifications/{id}", async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const title = data.title || "D Shop";
    const message = data.message || "New Update";
    const screen = data.data && data.data.screen ? data.data.screen : "notifications";
    
    const type = data.type || (data.data && data.data.type) || "default";

    let topicName = data.topic || null;
    if (!topicName && data.target_role) {
        if (data.target_role === 'rider') topicName = 'riders';
        else if (data.target_role === 'seller') topicName = 'sellers';
        else if (data.target_role === 'admin') topicName = 'admins';
        else topicName = 'all_users';
    }

    let channelId = "d_shop_channel";
    let soundName = "default";

    if (topicName === "riders" || type === "rider_job") {
        channelId = "rider_job_channel";
        soundName = "rider_alert";
    } else if (topicName === "admins" && type === "new_order") {
        channelId = "admin_order_channel";
        soundName = "admin_order";
    } else {
        channelId = "d_shop_channel";
        soundName = "default";
    }

    const messagePayload = {
        notification: { 
            title: title, 
            body: message,
            image: data.image_url ? data.image_url : null 
        },
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
            await admin.messaging().send({ topic: topicName, ...messagePayload });
            console.log(`Sent to Topic: ${topicName}`);
        } else if (data.target_user_id) {
            const userDoc = await admin.firestore().collection("users").doc(data.target_user_id).get();
            if (userDoc.exists && userDoc.data().fcm_token) {
                await admin.messaging().send({ token: userDoc.data().fcm_token, ...messagePayload });
                console.log(`Sent to User: ${data.target_user_id}`);
            }
        }
    } catch (error) { console.error("FCM Error:", error); }
    return null;
});

// ==========================================
// ২. ফেসবুক Conversions API (CAPI) ফাংশন [NEW]
// ==========================================
// ফেসবুক পিক্সেল আইডি এবং এপিআই টোকেন এখানে বসাবেন
/*
const PIXEL_ID = "YOUR_FACEBOOK_PIXEL_ID";
const ACCESS_TOKEN = "YOUR_FACEBOOK_CONVERSIONS_API_ACCESS_TOKEN";

exports.sendPurchaseToFacebookCAPI = onDocumentCreated("orders/{orderId}", async (event) => {
    const orderData = event.data.data();
    if (!orderData) return null;
    
    const orderId = event.params.orderId;

    // আইপি এবং ব্রাউজার আইডি (ফ্লাটার অ্যাপ থেকে অর্ডারের সময় ডাটাবেসে পাঠালে ভালো হয়, না পাঠালে এগুলো ডিফল্ট কাজ করবে)
    const clientIp = orderData.client_ip || "192.168.0.1"; 
    const userAgent = orderData.user_agent || "Mobile App UserAgent";
    const fbp = orderData.fbp || ""; 
    const fbc = orderData.fbc || ""; 

    // ফেসবুকের নিয়ম অনুযায়ী ফোন নাম্বার হ্যাশ (SHA256) করতে হয়
    const phoneToHash = (orderData.shipping_phone || "").trim().toLowerCase();
    const hashedPhone = crypto.createHash("sha256").update(phoneToHash).digest("hex");

    const eventPayload = {
      data:[
        {
          event_name: "Purchase",
          event_time: Math.floor(Date.now() / 1000),
          action_source: "app",
          event_id: orderId,
          user_data: {
            ph: [hashedPhone], 
            client_ip_address: clientIp,
            client_user_agent: userAgent,
            fbp: fbp,
            fbc: fbc,
          },
          custom_data: {
            currency: "BDT",
            value: orderData.total_amount,
            content_ids: orderData.items ? orderData.items.map(item => item.product_id) : [],
            content_type: "product",
          },
        },
      ],
    };

    try {
      const response = await axios.post(
        `https://graph.facebook.com/v19.0/${PIXEL_ID}/events?access_token=${ACCESS_TOKEN}`,
        eventPayload
      );
      console.log("Successfully sent to Facebook CAPI:", response.data);
    } catch (error) {
      console.error("Error sending to Facebook CAPI:", error.response ? error.response.data : error.message);
    }
    return null;
});

*/