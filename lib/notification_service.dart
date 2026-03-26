import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:firebase_messaging/firebase_messaging.dart';

// আমাদের নিজেদের ফাইলগুলোর লিঙ্ক (যাতে ক্লিক করলে পেজে যেতে পারে)
import 'main.dart'; // navigatorKey এর জন্য
import 'screens/customer_screens.dart';
import 'screens/admin_screens.dart';
import 'screens/seller_screens.dart';
import 'screens/rider_screens.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // ১. সার্ভিস ইনিশিয়ালাইজ করা
  static Future<void> init() async {
    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    // ১. সাধারণ চ্যানেল
    const AndroidNotificationChannel normalChannel = AndroidNotificationChannel(
      'd_shop_channel', 'General Notifications', importance: Importance.max, playSound: true,
    );
    // ২. রাইডার চ্যানেল
    const AndroidNotificationChannel riderChannel = AndroidNotificationChannel(
      'rider_job_channel', 'Rider Alerts', importance: Importance.max, playSound: true,
      sound: RawResourceAndroidNotificationSound('rider_alert'),
    );
    // ৩. এডমিন চ্যানেল
    const AndroidNotificationChannel adminChannel = AndroidNotificationChannel(
      'admin_order_channel', 'Admin Alerts', importance: Importance.max, playSound: true,
      sound: RawResourceAndroidNotificationSound('admin_order'),
    );

    final plugin = _flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await plugin?.createNotificationChannel(normalChannel);
    await plugin?.createNotificationChannel(riderChannel);
    await plugin?.createNotificationChannel(adminChannel);

    await _flutterLocalNotificationsPlugin.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // ✅ নোটিফিকেশনে ক্লিক করলে নির্দিষ্ট পেজে যাওয়ার ফাংশন কল
        handleNotificationNavigation(response.payload);
      },
    );

     await _flutterLocalNotificationsPlugin.cancel(999);
  }

  // ২. নোটিফিকেশন ক্লিক করলে নির্দিষ্ট পেজে যাওয়ার মাস্টার লজিক
  static void handleNotificationNavigation(String? screen) {
    // ✅ রিংটোন বাজা বন্ধ করার জন্য নোটিফিকেশন আইডি ৯৯৯ বাতিল করা হলো
    _flutterLocalNotificationsPlugin.cancel(999); 
    
    if (screen == null) return;

    if (screen == 'rider_dashboard') {
      // রাইডারকে সরাসরি ড্যাশবোর্ড বা রুট ট্যাবে পাঠানোর জন্য
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RiderMainScreen(initialPage: 0)), 
        (route) => false
      );
    } else if (screen == 'notifications') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const CustomerNotificationPage()));
    } else if (screen == 'admin_orders') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const AdminMainScreen()));
    } else if (screen == 'seller_orders') {
      navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const SellerMainScreen(initialPage: 2)), 
        (route) => false
      );
    }
  }
  
  // ৩. ব্যাকগ্রাউন্ড হ্যান্ডলার সেটআপ
  static void setupBackgroundHandler(Function(NotificationResponse) handler) {
    _flutterLocalNotificationsPlugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: handler,
      onDidReceiveBackgroundNotificationResponse: handler,
    );
  }

  // ৪. অ্যাপ চলাকালীন (Foreground) নোটিফিকেশন দেখানো
  static void showFcmNotification(RemoteMessage message) {
    RemoteNotification? notification = message.notification;
    bool isRiderJob = message.data['type'] == 'rider_job' || message.data['screen'] == 'rider_dashboard';

    if (notification != null) {
      _flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            isRiderJob ? 'rider_job_channel' : 'd_shop_channel',
            isRiderJob ? 'Rider Job Alerts' : 'General Notifications',
            importance: Importance.max,
            priority: Priority.high,
            playSound: true,
            sound: isRiderJob ? const RawResourceAndroidNotificationSound('rider_alert') : null,
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentSound: true),
        ),
        payload: message.data['screen'], // ক্লিক করলে পেজ আইডি পাস হবে
      );
    }
  }

  // ৫. রাইডারদের জন্য রিংটোন ট্রিগার (Firestore Stream এর জন্য)
  static void triggerJobAlert() {
    _flutterLocalNotificationsPlugin.show(
      999,
      "🚨 নতুন ডেলিভারি রিকোয়েস্ট!",
      "একটি নতুন অর্ডার এসেছে, দ্রুত এক্সেপ্ট করুন।",
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'rider_job_channel',
          'Rider Job Alerts',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('rider_alert'),
        ),
      ),
      payload: 'rider_dashboard',
    );
  }

  // ৬. অ্যাপ বন্ধ থাকা অবস্থায় নোটিফিকেশন দেখানো
  static Future<void> showBackgroundNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'rider_job_channel',
      'Rider Job Alerts',
      importance: Importance.max,
      priority: Priority.high,
      sound: RawResourceAndroidNotificationSound('rider_alert'),
      playSound: true,
      fullScreenIntent: true,
    );

    await _flutterLocalNotificationsPlugin.show(
      message.hashCode,
      message.notification?.title ?? "🚨 নতুন আপডেট",
      message.notification?.body ?? "অ্যাপ চেক করুন।",
      const NotificationDetails(android: androidDetails),
      payload: message.data['screen'],
    );
  }

  // ৭. Role অনুযায়ী টপিক সিঙ্ক করা এবং Token সেভ করা (সবার জন্য)
  static Future<void> syncFcmTopics(String role) async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    User? user = FirebaseAuth.instance.currentUser;

    // [NEW] লগিন থাকা অবস্থায় সবার (সেলার, রাইডার, কাস্টমার) FCM Token ডাটাবেসে সেভ করা
    if (user != null && role != 'guest') {
      try {
        String? token = await messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
            'fcm_token': token
          });
        }
      } catch (e) {
        print("Token Update Error: $e");
      }
    }
    
    // প্রথমে সব টপিক থেকে আন-সাবস্ক্রাইব করবে (যাতে পুরোনো রোলের মেসেজ না আসে)
    await messaging.unsubscribeFromTopic('riders');
    await messaging.unsubscribeFromTopic('sellers');
    await messaging.unsubscribeFromTopic('admins');
    await messaging.unsubscribeFromTopic('all_users');

    // এরপর নতুন রোল অনুযায়ী সাবস্ক্রাইব করবে
    if (role == 'rider') {
      await messaging.subscribeToTopic('riders');
    } else if (role == 'seller') {
      await messaging.subscribeToTopic('sellers');
    } else if (role == 'admin' || role == 'super_admin') {
      await messaging.subscribeToTopic('admins');
    }
    
    // Guest (লগআউট) না হলে সবাইকে all_users এ রাখবে
    if (role != 'guest') {
      await messaging.subscribeToTopic('all_users');
    }
  }
}