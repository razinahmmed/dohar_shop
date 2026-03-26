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
import 'package:shared_preferences/shared_preferences.dart';

// ফাইলটির একদম শুরুতে এই Global Key টি ডিক্লেয়ার করুন (এটি নেভিগেশনের জন্য লাগবে)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'rider_job') {
    NotificationService.triggerJobAlert(); // রাইডারের অ্যালার্ম
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

      // ইউজার লগইন না থাকলে সরাসরি মেইন স্ক্রিনে (লগইন পেজ) পাঠিয়ে দিবে
      if (user == null) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
        return;
      }

      // ১. ফোনের লোকাল মেমোরি (SharedPreferences) থেকে রোল চেক করা
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? savedRole = prefs.getString('user_role');

      // ২. মেমোরিতে সেভ থাকলে লোডিং ছাড়াই অ্যাপ ওপেন হবে
      if (savedRole != null && mounted) {
        _navigateToScreen(savedRole); 
        _syncRoleInBackground(user.uid, savedRole); // ব্যাকগ্রাউন্ডে চেক করবে রোল বদলেছে কি না
        return;
      }

      // ৩. মেমোরিতে না থাকলে (যেমন: প্রথমবার লগইন) ডাটাবেস থেকে আনা হবে
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (doc.exists && mounted) {
        String role = doc['role'] ?? 'customer';
        
        // মেমোরিতে রোল সেভ করে রাখা
        await prefs.setString('user_role', role); 
        
        // [NEW] রোল অনুযায়ী নোটিফিকেশন টপিক আপডেট করা
        await NotificationService.syncFcmTopics(role); 
        
        _navigateToScreen(role);
      } else {
        // যদি ডাটাবেসে ইউজার না থাকে
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const MainScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint("Startup Error: $e");
      // এরর হলে কাস্টমার মোডে বা মেইন স্ক্রিনে পাঠিয়ে দেওয়া নিরাপদ
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainScreen()),
        );
      }
    }
  }

  // এটি আপনার আগের নেভিগেশন লজিককে সহজ করার জন্য
  void _navigateToScreen(String role) {
    if (role == 'admin' || role == 'super_admin') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminMainScreen()));
    } else if (role == 'seller') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
    } else if (role == 'rider') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
    }
  }

  // ব্যাকগ্রাউন্ডে রোল চেক করার জন্য
  void _syncRoleInBackground(String uid, String oldRole) async {
    var doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (doc.exists) {
      String newRole = doc['role'] ?? 'customer';
      if (newRole != oldRole) {
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_role', newRole);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ব্যাকগ্রাউন্ড সাদা করা হলো লোগো ফোটার জন্য
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // আপনার অ্যাপের লোগো (আপনার লোগোর নাম বা ফোল্ডার আলাদা হলে path ঠিক করে দিবেন)
            // যদি কোনো কারণে লোগো লোড না হয়, তবে আইকন দেখাবে
            Image.asset(
              'assets/images/launcher_dshop.png', // আপনার লোগোর পাথ
              width: 120, 
              height: 120,
              errorBuilder: (context, error, stackTrace) => const Icon(Icons.shopping_bag, size: 80, color: Colors.deepOrange),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.deepOrange),
            const SizedBox(height: 20),
            const Text(
              'Loading D Shop...', 
              style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 18)
            ),
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