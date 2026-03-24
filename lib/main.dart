import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // 🔴 এই ইম্পোর্ট যোগ করুন
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'notification_service.dart';
import 'screens/auth_screens.dart';
import 'screens/customer_screens.dart';
import 'screens/seller_screens.dart';
import 'screens/admin_screens.dart';
import 'screens/rider_screens.dart';

// ফাইলটির একদম শুরুতে এই Global Key টি ডিক্লেয়ার করুন (এটি নেভিগেশনের জন্য লাগবে)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// 🔴 ১. ব্যাকগ্রাউন্ড মেসেজ হ্যান্ডলার (অ্যাপ বন্ধ থাকলেও এটি কাজ করবে)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // অ্যাপ বন্ধ থাকলে এই অংশটি ফায়ারবেস থেকে মেসেজ রিসিভ করে
  await Firebase.initializeApp();
  
  // ব্যাকগ্রাউন্ডে রিংটোন বাজানোর জন্য এটি জরুরি
  if (message.data['type'] == 'rider_job' || message.data['screen'] == 'rider_dashboard') {
    // এখানে সরাসরি নোটিফিকেশন দেখানোর কোড কল করতে হবে
    NotificationService.showBackgroundNotification(message);
  }
}

// 🔴 ২. নোটিফিকেশন ট্যাপ করার জন্য ব্যাকগ্রাউন্ড হ্যান্ডলার
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  print('Notification tapped in background: ${notificationResponse.payload}');
  // এখানে ক্লিক করলে কি হবে তা অ্যাপ ওপেন হওয়ার পর কাজ করবে
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  
  await NotificationService.init();

  // অ্যান্ড্রয়েড ১৩+ পারমিশন
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  await messaging.requestPermission(alert: true, badge: true, sound: true);

  // ১. অ্যাপ যখন চালু থাকে (Foreground) তখন নোটিফিকেশন রিসিভ করা
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    NotificationService.showFcmNotification(message);
  });

  // ২. নোটিফিকেশন ক্লিক করলে অ্যাপ ওপেন হওয়ার লজিক (Background/Terminated)
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    _handleNotificationClick(message);
  });

  // ৩. অ্যাপ একদম বন্ধ অবস্থায় ক্লিক করলে যা হবে
  RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
  if (initialMessage != null) {
    _handleNotificationClick(initialMessage);
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  NotificationService.setupBackgroundHandler(notificationTapBackground);

  runApp(const MyApp());
}

// নোটিফিকেশন ক্লিক হ্যান্ডলার ফাংশন
void _handleNotificationClick(RemoteMessage message) {
  String? screen = message.data['screen'];
  if (screen == 'rider_dashboard') {
    navigatorKey.currentState?.pushNamed('/rider_dashboard'); // রাইডার পেজ
  } else if (screen == 'notifications') {
    navigatorKey.currentState?.pushNamed('/notifications'); // নোটিফিকেশন পেজ
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey, // এটি অবশ্যই যোগ করবেন, নেভিগেশনের জন্য জরুরি
      title: 'D Shop',
      theme: ThemeData(
        primarySwatch: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const AuthWrapper(), // আপনার আগের সিস্টেম অনুযায়ী
    );
  }
}

// ==========================================
// ফিক্সড Auth Wrapper (রোল এবং নোটিফিকেশন ফিক্সড)
// ==========================================
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  @override
  void initState() {
    super.initState();
    // অ্যাপ ওপেন হওয়ার পর ১ সেকেন্ড ওয়েট করবে যাতে ফায়ারবেস ঠিকমতো কানেক্ট হতে পারে
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initSafeStartup();
    });
  }

  Future<void> _initSafeStartup() async {
    try {
      await NotificationService.init();
      User? user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
        return;
      }

      // ১. ডাটাবেস থেকে ইউজারের রোল আনা
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (doc.exists && mounted) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String role = data['role'] ?? 'customer';

        // ২. নোটিফিকেশন পারমিশন ও টোকেন আপডেট
        FirebaseMessaging messaging = FirebaseMessaging.instance;
        await messaging.requestPermission(alert: true, badge: true, sound: true);

        String? token = await messaging.getToken();
        if (token != null) {
          await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcm_token': token});
        }

        // পুরনো সব টপিক থেকে আন-সাবস্ক্রাইব করা (যাতে জট না পাকায়)
        await messaging.unsubscribeFromTopic('riders');
        await messaging.unsubscribeFromTopic('sellers');
        await messaging.unsubscribeFromTopic('admins');
        await messaging.unsubscribeFromTopic('all_users');

        // সব ইউজার (কাস্টমারসহ) এই টপিকটি সাবস্ক্রাইব করবে
        await messaging.subscribeToTopic('all_users');

        // ৩. রোল অনুযায়ী নির্দিষ্ট টপিক ও স্ক্রিনে পাঠানো
        if (role == 'admin' || role == 'super_admin') {
          await messaging.subscribeToTopic('admins'); // এডমিন টপিক
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminMainScreen()));
        } 
        else if (role == 'seller') {
          await messaging.subscribeToTopic('sellers'); // সেলার টপিক
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
        } 
        else if (role == 'rider') {
          await messaging.subscribeToTopic('riders'); // রাইডার টপিক
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
        } 
        else {
          // এটি শুধুমাত্র পিওর কাস্টমারদের জন্য
          if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
        }

      } else {
        // যদি ইউজার ডাটাবেসে না থাকে তবে কাস্টমার হিসেবে মেইন স্ক্রিনে যাবে
        if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) {
      debugPrint("Startup Error: $e");
      // এরর হলে কাস্টমার মোডে পাঠিয়ে দেওয়া নিরাপদ
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.deepOrange,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.shopping_cart_checkout, size: 80, color: Colors.white),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 20),
            Text('Verifying Identity...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Please Wait...', style: TextStyle(color: Colors.white70, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // নোটিফিকেশন ক্লিক করলে কোন পেজে যাবে তার মাস্টার লজিক
  void handleNotificationNavigation(String? screen) {
    if (screen == null) return;

    if (screen == 'rider_dashboard') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const RiderMainScreen()));
    } else if (screen == 'notifications') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const CustomerNotificationPage()));
    } else if (screen == 'admin_orders') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const AdminMainScreen())); // এখানে ইনডেক্স সেট করা যায়
    } else if (screen == 'seller_orders') {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (context) => const SellerMainScreen()));
    }
  }
  
}