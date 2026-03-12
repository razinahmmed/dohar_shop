// [FIXED] Explicitly using v1 API for backward compatibility with the logic
const functions = require("firebase-functions/v1"); 
const admin = require("firebase-admin");
admin.initializeApp();

// ডাটাবেসের "notifications" কালেকশনে নতুন কোনো ডাটা এলেই এই ফাংশনটি অটো ফায়ার হবে
exports.sendPushNotification = functions.firestore
  .document("notifications/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();

    // যদি target_user_id থাকে, তার মানে শুধু নির্দিষ্ট একজনকে পাঠাতে হবে (যেমন: অর্ডার আপডেট)
    if (data.target_user_id) {
      try {
        const userDoc = await admin.firestore().collection("users").doc(data.target_user_id).get();
        const token = userDoc.data().fcm_token;
        
        if (token) {
          const message = {
            notification: {
              title: data.title || "Notification",
              body: data.message || ""
            },
            token: token
          };
          return admin.messaging().send(message);
        } else {
          console.log("No FCM token found for user:", data.target_user_id);
          return null;
        }
      } catch (error) {
        console.error("Error sending personal message:", error);
        return null;
      }
    } 
    // আর যদি target_user_id না থাকে, তার মানে অ্যাডমিন ব্রডকাস্ট পাঠিয়েছে (সব কাস্টমারকে)
    else {
      try {
        const message = {
          notification: {
            title: data.title || "Notice",
            body: data.message || ""
          },
          topic: "all_users" // যারা অ্যাপ ইনস্টল করেছে সবাই এই টপিকে আছে
        };
        return admin.messaging().send(message);
      } catch (error) {
        console.error("Error sending broadcast:", error);
        return null;
      }
    }
  });