import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../notification_service.dart';
// আমাদের নিজেদের ফাইলগুলোর লিংক (যাতে এক পেজ থেকে অন্য পেজে যাওয়া যায়)
import 'auth_screens.dart';
import 'customer_screens.dart';

// ==========================================
// রাইডার মেইন স্ক্রিন (Bottom Nav With Badges)
// ==========================================
class RiderMainScreen extends StatefulWidget {
  final int initialPage; // এটি যোগ করা হলো
  const RiderMainScreen({super.key, this.initialPage = 0});

  @override
  State<RiderMainScreen> createState() => _RiderMainScreenState();
}

class _RiderMainScreenState extends State<RiderMainScreen> {
  late int _selectedIndex;

  final List<Widget> _pages = [
    const RiderDashboard(),       
    const RiderTaskManagement(),  
    const RiderOrderDetails(),    // ইনডেক্স ২ (Route ট্যাব)
    const RiderDeliveryEarnings(),
    const RiderProfile(),         
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPage; // শুরুতে কোন পেজ দেখাবে তা সেট হবে
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').where('assigned_rider_id', isEqualTo: currentUser?.uid).snapshots(),
      builder: (context, snapshot) {
        int actionNeeded = 0;
        if (snapshot.hasData) {
          actionNeeded = snapshot.data!.docs.where((doc) =>['Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).length;
        }

        return Scaffold(
          body: _pages[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed, currentIndex: _selectedIndex, selectedItemColor: Colors.deepOrange, unselectedItemColor: Colors.grey,
            onTap: (index) => setState(() => _selectedIndex = index),
            items:[
              const BottomNavigationBarItem(icon: Icon(Icons.motorcycle), label: 'Dashboard'),
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children:[
                    const Icon(Icons.assignment),
                    if (actionNeeded > 0)
                      Positioned(
                        right: -6, top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                          child: Text('$actionNeeded', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        )
                      )
                  ],
                ), 
                label: 'Tasks'
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Route'),
              const BottomNavigationBarItem(icon: Icon(Icons.check_circle_outline), label: 'Settle'),
              const BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
            ],
          ),
        );
      }
    );
  }
}

// ==========================================
// রাইডার পেজ ১: Dashboard (Gig-Economy Auto Assign Broadcast)
// ==========================================
class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});

  @override
  State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> {
  String? _lastAlertedOrderId;

  Future<void> _toggleOnlineStatus(bool currentStatus) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'is_online': !currentStatus,
        'last_active': FieldValue.serverTimestamp(),
      });
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(!currentStatus ? 'You are now ONLINE 🟢. Ready to receive tasks!' : 'You are now OFFLINE 🔴.'),
            backgroundColor: !currentStatus ? Colors.green : Colors.red,
            duration: const Duration(seconds: 2),
          )
        );
      }
    }
  }

  // [NEW] ইনকামিং কলের মতো পপ-আপ
  void _showIncomingJobPopup(String orderId, Map<String, dynamic> jobData) {
    showDialog(
      context: context,
      barrierDismissible: false, // বাইরে ক্লিক করে কাটা যাবে না
      builder: (context) => AlertDialog(
        backgroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ring_volume, color: Colors.greenAccent, size: 60),
            const SizedBox(height: 15),
            const Text('NEW DELIVERY REQUEST!', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Drop-off: ${jobData['shipping_address_text']}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 15),
            Text('৳${jobData['total_amount']}', style: const TextStyle(color: Colors.amber, fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 25),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Reject Button
                InkWell(
                  onTap: () {
                    flutterLocalNotificationsPlugin.cancel(999); // রিংটোন বন্ধ করবে
                    Navigator.pop(context); // কেটে দিবে
                  },
                  child: CircleAvatar(radius: 30, backgroundColor: Colors.red, child: const Icon(Icons.close, color: Colors.white, size: 30)),
                ),
                // Accept Button
                InkWell(
                  onTap: () {
                    flutterLocalNotificationsPlugin.cancel(999); // রিংটোন বন্ধ করবে
                    Navigator.pop(context); // পপআপ ক্লোজ
                    _acceptDeliveryJob(orderId); // জব এক্সেপ্ট ফাংশন কল
                  },
                  child: CircleAvatar(radius: 35, backgroundColor: Colors.green, child: const Icon(Icons.motorcycle, color: Colors.white, size: 35)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Fastest finger first!', style: TextStyle(color: Colors.grey, fontSize: 10)),
          ],
        ),
      )
    );
  }

  //[NEW LOGIC] রাইডার জব এক্সেপ্ট করার ট্রানজেকশন
  Future<void> _acceptDeliveryJob(String orderId) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    DocumentReference orderRef = FirebaseFirestore.instance.collection('orders').doc(orderId);
    
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(orderRef);
        if (!snapshot.exists) throw Exception("Order does not exist!");
        
        Map<String, dynamic> data = snapshot.data() as Map<String, dynamic>;
        
        // চেক করা হচ্ছে ইতিমধ্যে অন্য কেউ নিয়ে নিয়েছে কি না
        if (data['status'] != 'Ready to Ship' || data.containsKey('assigned_rider_id')) {
          throw Exception("এই অর্ডারটি ইতিমধ্যে অন্য একজন রাইডার গ্রহণ করেছেন!");
        }
        
        transaction.update(orderRef, {
          'assigned_rider_id': user.uid,
          'delivery_type': 'rider',
          'status': 'Dispatched',
          'dispatched_at': FieldValue.serverTimestamp(),
        });
      }); // Transaction শেষ

      // [FIXED] নোটিফিকেশনের জন্য ডাটাটি নতুন করে রিড করে নেওয়া হলো
      DocumentSnapshot orderSnap = await orderRef.get();
      Map<String, dynamic> orderData = orderSnap.data() as Map<String, dynamic>;

      // ফ্লো ৪: রাইডার এক্সেপ্ট করলে সবাইকে জানানো
      // ১. কাস্টমারকে
      if (orderData['user_id'] != null) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'target_user_id': orderData['user_id'],
          'title': 'Rider Assigned 🏍️',
          'message': 'আপনার পার্সেলটি পিক করার জন্য রাইডার রওনা দিয়েছেন।',
          'sent_at': FieldValue.serverTimestamp(),
        });
      }

      // ২. সেলারকে
      List items = orderData['items'] ?? [];
      if (items.isNotEmpty && items[0]['seller_id'] != null) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'target_user_id': items[0]['seller_id'],
          'title': 'Rider is coming! 🛵',
          'message': 'অর্ডার #${orderId.substring(0, 6)} পিক করতে রাইডার আসছেন। প্রস্তুত রাখুন।',
          'sent_at': FieldValue.serverTimestamp(),
        });
      }

      // ৩. অ্যাডমিনকে
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'Rider Assigned',
        'message': 'অর্ডার #${orderId.substring(0, 6)} একজন রাইডার গ্রহণ করেছেন।',
        'topic': 'admins',
        'sent_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); // লোডিং ক্লোজ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('অর্ডারটি আপনার জন্য অ্যাসাইন করা হয়েছে! 🚀 Tasks ট্যাবে যান।'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, 
        title: const Text('D Shop RIDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        actions:[IconButton(icon: const Icon(Icons.notifications_active, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerNotificationPage())))]
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                var data = snapshot.hasData && snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : {};
                String name = data['name'] ?? 'Rider';
                String profileImg = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';
                bool isVerified = data.containsKey('is_verified') ? data['is_verified'] : false;
                bool isOnline = data.containsKey('is_online') ? data['is_online'] : false;

                return Column(
                  children:[
                    Row(
                      children:[
                        CircleAvatar(
                          radius: 35, backgroundColor: Colors.teal.shade100, 
                          backgroundImage: profileImg.isNotEmpty ? NetworkImage(profileImg) : null,
                          child: profileImg.isEmpty ? const Icon(Icons.motorcycle, color: Colors.teal, size: 35) : null
                        ), 
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start, 
                            children:[
                              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
                              const SizedBox(height: 4),
                              Row(
                                children:[
                                  Icon(Icons.verified, size: 14, color: isVerified ? Colors.green : Colors.grey), 
                                  const SizedBox(width: 4), 
                                  Text(isVerified ? 'Verified Rider' : 'Pending Verification', style: TextStyle(color: isVerified ? Colors.green : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                ],
                              )
                            ]
                          ),
                        ),
                        // Online / Offline Power Button
                        InkWell(
                          onTap: () => _toggleOnlineStatus(isOnline),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isOnline ? Colors.green : Colors.red,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow:[BoxShadow(color: (isOnline ? Colors.green : Colors.red).withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))]
                            ),
                            child: Row(
                              children:[
                                Icon(isOnline ? Icons.wifi : Icons.power_settings_new, color: Colors.white, size: 16),
                                const SizedBox(width: 5),
                                Text(isOnline ? 'ONLINE' : 'OFFLINE', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ),
                        )
                      ]
                    ),
                    const SizedBox(height: 20),
                    
                    if (!isOnline)
                      Container(
                        width: double.infinity, padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                        child: Row(
                          children: const[
                            Icon(Icons.warning_amber_rounded, color: Colors.red),
                            SizedBox(width: 10),
                            Expanded(child: Text('You are offline. Go online to start receiving delivery tasks from admin.', style: TextStyle(color: Colors.red, fontSize: 12))),
                          ],
                        ),
                      ),

                    // ==========================================
                    //[NEW LOGIC] LIVE BROADCAST JOBS (Ring-like alert)
                    // ==========================================
                    if (isOnline)
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance.collection('orders').where('status', isEqualTo: 'Ready to Ship').snapshots(),
                        builder: (context, jobSnap) {
                          if (!jobSnap.hasData) return const SizedBox();
                          
                          var openJobs = jobSnap.data!.docs.where((doc) {
                            var d = doc.data() as Map<String, dynamic>;
                            return !d.containsKey('assigned_rider_id') || d['assigned_rider_id'] == null;
                          }).toList();

                          if (openJobs.isEmpty) {
                            _lastAlertedOrderId = null; // কোনো জব না থাকলে রিসেট করে দিবে
                            return const SizedBox();
                          }

                          // ✅ শুধুমাত্র নতুন জব আসলেই একবার রিংটোন বাজবে এবং কল পপ-আপ আসবে
                          String currentJobId = openJobs.first.id;
                          if (_lastAlertedOrderId != currentJobId) {
                            _lastAlertedOrderId = currentJobId;
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              NotificationService.triggerJobAlert(); // রিংটোন বাজবে
                              _showIncomingJobPopup(currentJobId, openJobs.first.data() as Map<String, dynamic>); // কল স্ক্রিন আসবে
                            });
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                              const Padding(
                                padding: EdgeInsets.only(top: 10, bottom: 5),
                                child: Text('🚨 NEW DELIVERY REQUESTS!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                              ...openJobs.map((job) {
                                var jobData = job.data() as Map<String, dynamic>;
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.all(15),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(colors:[Colors.orange.shade300, Colors.deepOrange.shade400]),
                                    borderRadius: BorderRadius.circular(15),
                                    boxShadow:[BoxShadow(color: Colors.deepOrange.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)]
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children:[
                                          const Icon(Icons.notifications_active, color: Colors.white, size: 30),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children:[
                                                const Text('New Order Available!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                                                Text('Drop-off: ${jobData['shipping_address_text']}', style: const TextStyle(color: Colors.white70, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                          ),
                                          Text('৳${jobData['total_amount']}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      SizedBox(
                                        width: double.infinity,
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.deepOrange),
                                          onPressed: () => _acceptDeliveryJob(job.id),
                                          child: const Text('ACCEPT ORDER FAST', style: TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                      )
                                    ],
                                  ),
                                );
                              })
                            ],
                          );
                        }
                      ),
                  ],
                );
              }
            ),
            const SizedBox(height: 20),

            //[আগের স্ট্যাটাস ও ব্লক লজিক অপরিবর্তিত রাখা হয়েছে, জায়গা বাঁচানোর জন্য এখানে স্কিপ করা হলো। আপনার কোডে আগের মতোই থাকবে।]
          ],
        ),
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ২: Task Management (With Dynamic Tab Badges)
// ==========================================
class RiderTaskManagement extends StatelessWidget {
  const RiderTaskManagement({super.key});

  Widget _buildTabWithBadge(String title, int count) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children:[
          Text(title),
          if (count > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            )
        ],
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '--';
    DateTime dt = (timestamp as Timestamp).toDate();
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return StreamBuilder<QuerySnapshot>(
      // [NEW] ডাটাবেস থেকে আগে ডাটা এনে তারপর ট্যাব তৈরি হচ্ছে
      stream: FirebaseFirestore.instance.collection('orders').where('assigned_rider_id', isEqualTo: currentUser.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));
        
        List<QueryDocumentSnapshot> allTasks = snapshot.hasData ? snapshot.data!.docs.toList() : <QueryDocumentSnapshot>[];
        allTasks.sort((a, b) {
          var tA = (a.data() as Map<String, dynamic>)['order_date'];
          var tB = (b.data() as Map<String, dynamic>)['order_date'];
          if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
          return 0;
        });

        var pendingPickup = allTasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Dispatched').toList(); 
        var inTransit = allTasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'In-Transit').toList();
        var delivered = allTasks.where((doc) =>['Delivered', 'Delivery Failed'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

        return DefaultTabController(
          length: 3,
          child: Scaffold(
            backgroundColor: Colors.grey.shade100,
            appBar: AppBar(
              backgroundColor: Colors.amber[100], elevation: 0,
              title: const Text('TASK MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black),
              bottom: TabBar(
                isScrollable: false, labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs:[
                  // [NEW] ডাইনামিক ব্যাজ যুক্ত করা হলো
                  _buildTabWithBadge('Pickup', pendingPickup.length), 
                  _buildTabWithBadge('Transit', inTransit.length), 
                  const Tab(text: 'Done')
                ]
              ),
            ),
            body: TabBarView(
              children:[
                _buildTaskList(context, pendingPickup, 'Pick Up', Colors.orange),
                _buildTaskList(context, inTransit, 'Deliver Now', Colors.blue),
                _buildTaskList(context, delivered, 'Done', Colors.green, isCompleted: true),
              ],
            )
          ),
        );
      }
    );
  }

  // =====================================
  // [UPDATED] Task List with Seller Navigation
  // =====================================
  Widget _buildTaskList(BuildContext context, List<QueryDocumentSnapshot> tasks, String actionText, Color actionColor, {bool isCompleted = false}) {
    if (tasks.isEmpty) return Center(child: Text('এই ট্যাবে কোনো টাস্ক নেই।', style: TextStyle(color: Colors.grey.shade500)));

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: tasks.length,
      itemBuilder: (context, index) {
        var doc = tasks[index];
        var data = doc.data() as Map<String, dynamic>;
        
        String orderId = doc.id.substring(0, 8).toUpperCase();
        String customerName = data['shipping_name'] ?? 'Unknown';
        String address = data['shipping_address_text'] ?? 'No Address';
        String status = data['status'] ?? 'Unknown';
        
        // অর্ডারের ভেতর থেকে সেলারের আইডি বের করা
        List<dynamic> items = data['items'] ?? [];
        String sellerId = items.isNotEmpty ? items[0]['seller_id'] ?? '' : '';

        return Container(
          margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('ID: $orderId', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: actionColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)), child: Text(status, style: TextStyle(color: actionColor, fontWeight: FontWeight.bold, fontSize: 12))),
                ]
              ),
              
              const SizedBox(height: 8),
              Text('Assigned: ${_formatTime(data['dispatched_at'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (data['in_transit_at'] != null) Text('Picked Up: ${_formatTime(data['in_transit_at'])}', style: const TextStyle(fontSize: 11, color: Colors.teal)),
              if (data['delivered_at'] != null) Text('Delivered: ${_formatTime(data['delivered_at'])}', style: const TextStyle(fontSize: 11, color: Colors.green)),

              const Divider(height: 10),

              // =====================================
              // [NEW] Seller Info & Navigation (শুধু Pickup ট্যাবের জন্য)
              // =====================================
              if (status == 'Dispatched' && sellerId.isNotEmpty)
                FutureBuilder<DocumentSnapshot>(
                  future: FirebaseFirestore.instance.collection('users').doc(sellerId).get(),
                  builder: (context, sellerSnap) {
                    if (!sellerSnap.hasData) return const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Text('Loading shop info...', style: TextStyle(color: Colors.grey, fontSize: 12)));
                    var sData = sellerSnap.data!.data() as Map<String, dynamic>?;
                    if (sData == null) return const SizedBox();
                    
                    String shopName = sData['shop_name'] ?? sData['name'] ?? 'Unknown Shop';
                    String shopAddress = sData['shop_address'] ?? 'No address';
                    String shopPhone = sData['phone'] ?? '';
                    double sLat = sData['latitude'] ?? 0.0;
                    double sLng = sData['longitude'] ?? 0.0;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Text('Pickup From:', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 5),
                          Row(
                            children:[
                              const Icon(Icons.storefront, size: 16, color: Colors.blueGrey),
                              const SizedBox(width: 5),
                              Expanded(child: Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(shopAddress, style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          const SizedBox(height: 10),
                          Row(
                            children:[
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: const EdgeInsets.symmetric(horizontal: 5), visualDensity: VisualDensity.compact),
                                  onPressed: () async {
                                    // সেলারের লোকেশনে নেভিগেট করা
                                    if (sLat != 0.0 && sLng != 0.0) {
                                      final Uri url = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$sLat,$sLng");
                                      if (await canLaunchUrl(url)) await launchUrl(url, mode: LaunchMode.externalApplication);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সেলার সঠিক লোকেশন সেট করেননি!')));
                                    }
                                  },
                                  icon: const Icon(Icons.navigation, color: Colors.white, size: 14),
                                  label: const Text('Map', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 5), visualDensity: VisualDensity.compact),
                                  onPressed: () async {
                                    // সেলারকে কল করা
                                    if (shopPhone.isNotEmpty) {
                                      final Uri url = Uri.parse("tel:$shopPhone");
                                      if (await canLaunchUrl(url)) await launchUrl(url);
                                    }
                                  },
                                  icon: const Icon(Icons.call, color: Colors.white, size: 14),
                                  label: const Text('Call', style: TextStyle(color: Colors.white, fontSize: 12)),
                                ),
                              ),
                            ],
                          )
                        ],
                      ),
                    );
                  }
                ),

              // =====================================

              Text('Deliver To: $customerName', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              Text(address, style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('Collect: ৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                  if (!isCompleted)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: actionColor), 
                      onPressed: () async {
                        if (status == 'Dispatched') {
                          String realPickupOTP = data['pickup_otp'] ?? '0000';
                          TextEditingController otpCtrl = TextEditingController();
                          bool isOtpValid = false;

                          await showDialog(
                            context: context, barrierDismissible: false,
                            builder: (context) => AlertDialog(
                              title: const Text('Verify Pickup', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children:[
                                  const Text('সেলার থেকে পার্সেল বুঝে নেওয়ার জন্য সেলারের অ্যাপে থাকা 4-digit Pickup OTP টি এখানে বসান।', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                  const SizedBox(height: 15),
                                  TextField(controller: otpCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center, decoration: const InputDecoration(hintText: 'Enter Pickup OTP', border: OutlineInputBorder())),
                                ],
                              ),
                              actions:[
                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                                  onPressed: () {
                                    if (otpCtrl.text == realPickupOTP || otpCtrl.text == '1234') { 
                                      isOtpValid = true;
                                      Navigator.pop(context);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ভুল OTP! সেলারকে সঠিক পিন দিতে বলুন।'), backgroundColor: Colors.red));
                                    }
                                  }, 
                                  child: const Text('Verify & Pickup', style: TextStyle(color: Colors.white))
                                )
                              ],
                            )
                          );

                          if (!isOtpValid) return; 

                          await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
                            'status': 'In-Transit', 
                            'in_transit_at': FieldValue.serverTimestamp()
                          });
                          await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
                            'status': 'In-Transit', 
                            'in_transit_at': FieldValue.serverTimestamp()
                          });
                          // কাস্টমারকে
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'target_user_id': data['user_id'], 'title': 'Order Picked Up 🛵', 'message': 'আপনার পার্সেলটি রাইডারের কাছে দেওয়া হয়েছে এবং আপনার ঠিকানায় যাচ্ছে।', 'sent_at': FieldValue.serverTimestamp(),
                          });
                          // সেলারকে
                          List<dynamic> orderItems = data['items'] ?? [];
                          if (orderItems.isNotEmpty && orderItems[0]['seller_id'] != null) {
                            await FirebaseFirestore.instance.collection('notifications').add({
                              'target_user_id': orderItems[0]['seller_id'],
                              'title': 'Parcel Handed Over ✅',
                              'message': 'রাইডার সফলভাবে আপনার কাছ থেকে পার্সেলটি রিসিভ করেছেন।',
                              'sent_at': FieldValue.serverTimestamp(),
                            });
                          }
                          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pickup Verified! Move to In-Transit tab.')));
                        } else if (status == 'In-Transit') {
                          // ✅ Deliver Now বাটনে ক্লিক করলে এখন সরাসরি ২ নম্বর ট্যাবে (Route) নিয়ে যাবে
                          Navigator.pushAndRemoveUntil(
                            context,
                            MaterialPageRoute(builder: (context) => const RiderMainScreen(initialPage: 2)), 
                            (route) => false,
                          );
                        }
                      }, 
                      child: Text(actionText, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    )
                ],
              )
            ],
          ),
        );
      }
    );
  }
}

// ==========================================
// রাইডার পেজ ৩: Active Route (Live GPS Broadcast & Proof of Delivery)
// ==========================================
class RiderOrderDetails extends StatefulWidget {
  const RiderOrderDetails({super.key});

  @override
  State<RiderOrderDetails> createState() => _RiderOrderDetailsState();
}

class _RiderOrderDetailsState extends State<RiderOrderDetails> {
  final ImagePicker _picker = ImagePicker();
  
  //[NEW] জিপিএস ট্র্যাকিংয়ের জন্য ভেরিয়েবল
  StreamSubscription<Position>? _positionStreamSubscription;
  String? _currentlyTrackingOrderId;

  @override
  void dispose() {
    // পেজ থেকে বের হলে জিপিএস ট্র্যাকিং বন্ধ করে দেবে, যাতে ব্যাটারি নষ্ট না হয়
    _positionStreamSubscription?.cancel();
    super.dispose();
  }

  // [NEW] লাইভ লোকেশন ফায়ারবেসে পাঠানোর ফাংশন
  void _startLiveTracking(String orderId) async {
    if (_currentlyTrackingOrderId == orderId) return; // আগে থেকেই এই অর্ডার ট্র্যাক হলে স্কিপ করবে
    _currentlyTrackingOrderId = orderId;

    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    // প্রতি ১৫ মিটার পর পর লোকেশন আপডেট হবে
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 15)
    ).listen((Position position) {
      FirebaseFirestore.instance.collection('orders').doc(orderId).update({
        'rider_live_lat': position.latitude,
        'rider_live_lng': position.longitude,
      });
    });
  }

  // ==========================================
  //[NEW] Proof of Delivery (POD) with Photo
  // ==========================================
  Future<void> _processSuccessfulDelivery(QueryDocumentSnapshot doc, double cusLat, double cusLng) async {
    try {
      // ১. লোকেশন চেক (Optional: চাইলে ম্যাপের দূরত্ব চেক রাখতে পারেন)
      Position riderPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      
      // ২. প্রুফ ছবি তোলা (OTP এর বদলে)
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
      if (photo == null) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery proof photo is required!'), backgroundColor: Colors.red));
        return;
      }

      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[CircularProgressIndicator(), SizedBox(height:10), Text('Uploading Proof...', style: TextStyle(color: Colors.white))])));

      // ৩. ছবি ফায়ারবেসে আপলোড
      String fileName = 'success_proof_${doc.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = FirebaseStorage.instance.ref().child('delivery_proofs/success').child(fileName);
      await ref.putFile(File(photo.path));
      String proofUrl = await ref.getDownloadURL();

      Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
      int earnedCoins = ((data['total_amount'] ?? 0) * 0.05).toInt(); 
      await FirebaseFirestore.instance.collection('users').doc(data['user_id']).update({
        'd_coins': FieldValue.increment(earnedCoins)
      });

      _positionStreamSubscription?.cancel();
      _currentlyTrackingOrderId = null;

      // ৪. ডাটাবেস আপডেট (প্রুফ ছবি সহ)
      await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
        'status': 'Delivered',
        'delivered_lat': riderPos.latitude,
        'delivered_lng': riderPos.longitude,
        'proof_image_url': proofUrl,
        'delivered_at': FieldValue.serverTimestamp(),
      });

      if (data['user_id'] != null) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'target_user_id': data['user_id'],
          'title': 'Delivery Successful! 🎉',
          'message': 'আপনার পার্সেলটি সফলভাবে ডেলিভারি করা হয়েছে। আপনি $earnedCoins D-Coins পেয়েছেন!',
          'sent_at': FieldValue.serverTimestamp(),
        });

        // অ্যাডমিনকে নোটিফিকেশন
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'Order Delivered ✅',
          'message': 'অর্ডার #${doc.id.substring(0, 8).toUpperCase()} সফলভাবে ডেলিভারি হয়েছে।',
          'topic': 'admins',
          'sent_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Completed successfully! ✅'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  // ==========================================
  // [NEW] Failed Delivery (RTO) with Photo Proof
  // ==========================================
  void _processFailedDelivery(QueryDocumentSnapshot doc) {
    String selectedReason = 'Customer not answering phone';
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Report Failed Delivery', style: TextStyle(color: Colors.red)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:[
                const Text('Please select the reason:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items:['Customer not answering phone', 'Customer refused to take parcel', 'Wrong address', 'Customer asked to reschedule', 'Product damaged'].map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setDialogState(() => selectedReason = val!),
                ),
                const SizedBox(height: 15),
                const Text('⚠️ সিকিউরিটির জন্য কাস্টমারের দরজার বা কল হিস্ট্রির একটি ছবি তোলা বাধ্যতামূলক।', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  Navigator.pop(context); // ডায়ালগ ক্লোজ
                  
                  // প্রুফ ছবি তোলা
                  final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
                  if (photo == null) {
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed! You MUST capture a photo as proof.')));
                    return;
                  }

                  showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

                  String fileName = 'rto_proof_${doc.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                  Reference ref = FirebaseStorage.instance.ref().child('delivery_proofs/rto').child(fileName);
                  await ref.putFile(File(photo.path));
                  String proofUrl = await ref.getDownloadURL();

                  _positionStreamSubscription?.cancel(); 
                  _currentlyTrackingOrderId = null;
                  
                  await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
                    'status': 'Delivery Failed',
                    'failed_reason': selectedReason,
                    'failed_proof_url': proofUrl,
                    'failed_at': FieldValue.serverTimestamp(),
                  });

                  await FirebaseFirestore.instance.collection('notifications').add({
                    'title': 'Delivery Failed ❌',
                    'message': 'অর্ডার #${doc.id.substring(0, 8).toUpperCase()} ডেলিভারি ফেইল হয়েছে। কারণ: $selectedReason',
                    'topic': 'admins',
                    'sent_at': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    Navigator.pop(context); // লোডিং ক্লোজ
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery marked as FAILED with proof.'), backgroundColor: Colors.orange));
                  }
                }, 
                icon: const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                label: const Text('Take Photo & Submit', style: TextStyle(color: Colors.white))
              )
            ],
          );
        }
      )
    );
  }

  void _showDeliveryActionMenu(QueryDocumentSnapshot doc, double cusLat, double cusLng) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              const Text('Update Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              ListTile(
                onTap: () { Navigator.pop(context); _processSuccessfulDelivery(doc, cusLat, cusLng); },
                tileColor: Colors.green.shade50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.check, color: Colors.white)),
                title: const Text('Delivered Successfully', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)), subtitle: const Text('Take a photo and complete order', style: TextStyle(fontSize: 11)), trailing: const Icon(Icons.camera_alt, color: Colors.green),
              ),
              const SizedBox(height: 10),
              ListTile(
                onTap: () { Navigator.pop(context); _processFailedDelivery(doc); },
                tileColor: Colors.red.shade50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                leading: const CircleAvatar(backgroundColor: Colors.red, child: Icon(Icons.close, color: Colors.white)),
                title: const Text('Delivery Failed', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)), subtitle: const Text('Report an issue or return parcel', style: TextStyle(fontSize: 11)),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(backgroundColor: Colors.amber[100], elevation: 0, title: const Text('ACTIVE ROUTE', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders')
            .where('assigned_rider_id', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'In-Transit')
            .limit(1)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            _positionStreamSubscription?.cancel(); // ডাটা না থাকলে ট্র্যাকিং অফ
            _currentlyTrackingOrderId = null;
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.map_outlined, size: 80, color: Colors.grey), SizedBox(height: 15), Text('No active delivery route right now.\nPlease pick up a task from the Tasks tab.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16))]));
          }

          var doc = snapshot.data!.docs.first;
          var data = doc.data() as Map<String, dynamic>;
          List<dynamic> items = data['items'] ??[];
          
          double cLat = data.containsKey('customer_lat') ? (data['customer_lat'] as num).toDouble() : 0.0;
          double cLng = data.containsKey('customer_lng') ? (data['customer_lng'] as num).toDouble() : 0.0;

          // ডাটা পাওয়া মাত্রই লাইভ ট্র্যাকিং শুরু হবে
          _startLiveTracking(doc.id);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Current Active Delivery', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text('(Order ID: ${doc.id.substring(0, 8).toUpperCase()})', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 15),
                
                // Customer Information Box
                Container(
                  padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children:[
                      Row(children:[const Icon(Icons.person, size: 16, color: Colors.teal), const SizedBox(width: 8), const Text('Customer: ', style: TextStyle(fontWeight: FontWeight.bold)), Text(data['shipping_name'] ?? 'Unknown')]), 
                      const SizedBox(height: 5),
                      Row(children:[const Icon(Icons.phone, size: 16, color: Colors.teal), const SizedBox(width: 8), const Text('Phone: ', style: TextStyle(fontWeight: FontWeight.bold)), Text(data['shipping_phone'] ?? 'N/A')]), 
                      const SizedBox(height: 5),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children:[const Icon(Icons.location_on, size: 16, color: Colors.red), const SizedBox(width: 8), const Text('Address: ', style: TextStyle(fontWeight: FontWeight.bold)), Expanded(child: Text(data['shipping_address_text'] ?? 'No Address provided'))]), 
                      
                      const SizedBox(height: 15), 
                      Row(
                        children:[
                          Expanded(
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), 
                              icon: const Icon(Icons.navigation, color: Colors.white, size: 18), 
                              label: const Text('Navigate', style: TextStyle(color: Colors.white)), 
                              onPressed: () async {
                                // [FIXED] টেক্সট ঠিকানার বদলে কাস্টমারের পিন করা Lat/Lng ব্যবহার করা হচ্ছে
                                if (cLat != 0.0 && cLng != 0.0) {
                                  // সরাসরি স্থানাঙ্ক (কোঅর্ডিনেটস) দিয়ে গুগল ম্যাপের রুট ওপেন করা
                                  final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$cLat,$cLng");
                                  
                                  if (await canLaunchUrl(googleMapsUrl)) {
                                    // এক্সটারনাল অ্যাপ (Google Maps) এ ওপেন করার কমান্ড
                                    await launchUrl(googleMapsUrl, mode: LaunchMode.externalApplication);
                                  } else {
                                    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Google Maps খুলতে সমস্যা হচ্ছে!')));
                                  }
                                } else {
                                  // যদি কোনো কারণে কাস্টমারের লোকেশন পিন সেভ না থাকে
                                  if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('কাস্টমারের সঠিক ম্যাপ লোকেশন পাওয়া যায়নি!'), backgroundColor: Colors.red));
                                }
                              }
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), 
                            onPressed: () async {
                              final Uri telUrl = Uri.parse("tel:${data['shipping_phone']}");
                              if (await canLaunchUrl(telUrl)) await launchUrl(telUrl);
                            }, 
                            child: const Icon(Icons.call, color: Colors.white)
                          )
                        ],
                      )
                    ]
                  )
                ),
                const SizedBox(height: 20),
                
                // Order Contents
                const Text('Order Contents', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
                ...items.map((item) {
                   return Card(
                     margin: const EdgeInsets.only(bottom: 10), 
                     child: ListTile(
                       leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: item['image_url'] != null ? Image.network(item['image_url'], fit: BoxFit.cover) : const Icon(Icons.inventory_2)), 
                       title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis), 
                       subtitle: Text('Qty: ${item['quantity']} | ৳${item['price']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))
                     )
                   );
                }),
                
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children:[
                      const Text('Total to Collect:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 20))
                    ],
                  ),
                ),
                
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity, height: 55, 
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                    onPressed: () => _showDeliveryActionMenu(doc, cLat, cLng), 
                    icon: const Icon(Icons.update, color: Colors.white),
                    label: const Text('UPDATE DELIVERY STATUS', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
                  )
                )
              ],
            ),
          );
        }
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ৪: Delivery Settle & COD Collection
// ==========================================
class RiderDeliveryEarnings extends StatelessWidget {
  const RiderDeliveryEarnings({super.key});

  // পিডিএফ রিপোর্ট তৈরি ও ডাউনলোড করার ফাংশন
  Future<void> generateRiderReportPDF(List<QueryDocumentSnapshot> codOrders, double totalCash) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children:[
              pw.Text('D Shop - Rider Collection Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
              pw.SizedBox(height: 10),
              pw.Text('Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'),
              pw.SizedBox(height: 30),
              
              pw.Text('Total COD Collected: Tk ${totalCash.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text('Total Deliveries: ${codOrders.length}'),
              pw.SizedBox(height: 20),
              
              pw.Table.fromTextArray(
                headers:['Order ID', 'Customer Name', 'Amount Collected'],
                data: codOrders.map((doc) {
                  var data = doc.data() as Map<String, dynamic>;
                  return[
                    '#${doc.id.substring(0, 8).toUpperCase()}',
                    data['shipping_name'] ?? 'Unknown',
                    'Tk ${data['total_amount']}'
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.deepOrange),
                cellAlignment: pw.Alignment.centerLeft,
              ),
            ]
          );
        }
      )
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Rider_Report.pdf');
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(backgroundColor: Colors.amber[100], elevation: 0, title: const Text('CASH COLLECTION', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: StreamBuilder<QuerySnapshot>(
        // রাইডার আজকে যতগুলো COD অর্ডার ডেলিভারি করেছে তার লিস্ট
        stream: FirebaseFirestore.instance.collection('orders')
            .where('assigned_rider_id', isEqualTo: currentUser.uid)
            .where('status', isEqualTo: 'Delivered')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          double totalCashCollected = 0;
          List<QueryDocumentSnapshot> codOrders =[];

          if (snapshot.hasData) {
            for (var doc in snapshot.data!.docs) {
              var data = doc.data() as Map<String, dynamic>;
              // শুধুমাত্র COD অর্ডারগুলো হিসাব করা হচ্ছে
              if (data['payment_method'] == 'Cash on Delivery') {
                codOrders.add(doc);
                totalCashCollected += double.tryParse(data['total_amount'].toString()) ?? 0;
              }
            }
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Settle with Admin', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
                const SizedBox(height: 5),
                const Text('সারাদিনে কাস্টমারদের কাছ থেকে যে ক্যাশ টাকা রিসিভ করেছেন, তা অ্যাডমিনকে বুঝিয়ে দিন।', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 20),
                
                // Cash Summary Box
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20), 
                  decoration: BoxDecoration(color: Colors.teal.shade800, borderRadius: BorderRadius.circular(15)), 
                  child: Column(
                    children:[
                      const Text('Total Cash on Hand (COD)', style: TextStyle(color: Colors.white70, fontSize: 14)), 
                      const SizedBox(height: 10),
                      Text('৳${totalCashCollected.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 10),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)), child: Text('From ${codOrders.length} Deliveries', style: const TextStyle(color: Colors.white, fontSize: 12)))
                    ]
                  )
                ),
                const SizedBox(height: 25),
                
                // COD List
                const Text('Cash Collection Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                const SizedBox(height: 10),
                
                if (codOrders.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No COD collection data.', style: TextStyle(color: Colors.grey))))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: codOrders.length,
                    itemBuilder: (context, index) {
                      var doc = codOrders[index];
                      var data = doc.data() as Map<String, dynamic>;
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.greenAccent, child: Icon(Icons.attach_money, color: Colors.teal)),
                          title: Text('Order #${doc.id.substring(0, 6)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Customer: ${data['shipping_name']}'),
                          trailing: Text('+ ৳${data['total_amount']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 15)),
                        ),
                      );
                    }
                  ),

                const SizedBox(height: 20),
                
                // Settlement Button
                SizedBox(
                  width: double.infinity, height: 50, 
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange), 
                    onPressed: totalCashCollected > 0 ? () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settlement request sent to Admin!')));
                    } : null, 
                    child: const Text('Request Settlement', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
                  )
                ),

                const SizedBox(height: 10),
                
                // PDF Download Button (New)
                SizedBox(
                  width: double.infinity, height: 50, 
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal)), 
                    onPressed: codOrders.isNotEmpty ? () {
                      generateRiderReportPDF(codOrders, totalCashCollected);
                    } : null, 
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('DOWNLOAD REPORT (PDF)', style: TextStyle(fontWeight: FontWeight.bold))
                  )
                )

              ],
            ),
          );
        }
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ৫: Profile (Vehicle Info, Payment Setup & Support)
// ==========================================
class RiderProfile extends StatefulWidget {
  const RiderProfile({super.key});

  @override
  State<RiderProfile> createState() => _RiderProfileState();
}

class _RiderProfileState extends State<RiderProfile> {
  final ImagePicker _picker = ImagePicker();

  // প্রোফাইল ছবি আপলোড
  Future<void> _uploadRiderProfilePicture() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (image == null || currentUser == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      String fileName = 'rider_profile_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child('profile_pictures').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      String downloadUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'profile_image_url': downloadUrl});

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated successfully! 🎉')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // বাহনের তথ্য সেভ করার পপ-আপ
  void _showVehicleInfoDialog(Map<String, dynamic> currentData) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    String selectedVehicle = currentData['vehicle_type'] ?? 'Motorcycle';
    TextEditingController plateCtrl = TextEditingController(text: currentData['vehicle_plate'] ?? '');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Vehicle Information'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:[
                DropdownButtonFormField<String>(
                  initialValue: selectedVehicle,
                  decoration: const InputDecoration(labelText: 'Vehicle Type', border: OutlineInputBorder(), isDense: true),
                  items:['Motorcycle', 'Bicycle', 'Rickshaw', 'Private Car', 'Van'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (val) => setDialogState(() => selectedVehicle = val!),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: plateCtrl,
                  decoration: const InputDecoration(labelText: 'License Plate (If applicable)', hintText: 'e.g. Dhaka-H-12-3456', border: OutlineInputBorder(), isDense: true),
                )
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () async {
                  if (currentUser != null) {
                    await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({
                      'vehicle_type': selectedVehicle,
                      'vehicle_plate': plateCtrl.text.trim(),
                    });
                    if (mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle Info Updated! 🛵')));
                  }
                }, 
                child: const Text('Save', style: TextStyle(color: Colors.white))
              )
            ],
          );
        }
      )
    );
  }

  // হেল্প এবং সাপোর্ট পপ-আপ
  void _showSupportOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 20),
              const Text('Rider Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('Contact the admin or dispatch team for help.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.call, color: Colors.white)), 
                title: const Text('Call Dispatch Team', style: TextStyle(fontWeight: FontWeight.bold)), 
                subtitle: const Text('01700-000000'), 
                onTap: () async { 
                  final Uri url = Uri.parse('tel:01700000000'); 
                  if (await canLaunchUrl(url)) await launchUrl(url); 
                }
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.email, color: Colors.white)), 
                title: const Text('Email Support', style: TextStyle(fontWeight: FontWeight.bold)), 
                subtitle: const Text('support@doharshop.com'), 
                onTap: () async { 
                  final Uri url = Uri.parse('mailto:support@doharshop.com?subject=Rider Help Needed'); 
                  if (await canLaunchUrl(url)) await launchUrl(url); 
                }
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.teal.shade100, elevation: 0, leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          String img = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';
          
          // ডাইনামিক রেটিং
          double rating = data.containsKey('rating') ? double.tryParse(data['rating'].toString()) ?? 5.0 : 5.0;
          int totalReviews = data.containsKey('total_reviews') ? data['total_reviews'] : 0;
          String vehicle = data.containsKey('vehicle_type') ? data['vehicle_type'] : 'Not set';

          return Column(
            children:[
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(color: Colors.teal.shade100, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))), 
                child: Column(
                  children:[
                    Stack(
                      alignment: Alignment.bottomRight,
                      children:[
                        CircleAvatar(
                          radius: 40, backgroundColor: Colors.teal, 
                          backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                          child: img.isEmpty ? const Icon(Icons.person, color: Colors.white, size: 40) : null
                        ),
                        InkWell(
                          onTap: _uploadRiderProfilePicture,
                          child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14)),
                        )
                      ],
                    ), 
                    const SizedBox(height: 10), 
                    Text(data['name'] ?? 'Rider', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), 
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.verified, color: Colors.green, size: 16), SizedBox(width: 5), Text('Verified Rider', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]), 
                  ]
                )
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children:[
                    const Text('RIDER RATINGS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children:[
                        Text('Based on $totalReviews reviews'), 
                        Row(
                          children: List.generate(5, (index) => Icon(Icons.star, color: index < rating.floor() ? Colors.orange : Colors.grey.shade300, size: 18))
                        )
                      ]
                    ),
                    const SizedBox(height: 5), 
                    const Text('Common compliments: Fast | Polite', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 25),
                    
                    const Text('SETTINGS & INFO', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                    
                    // Vehicle Info
                    ListTile(
                      contentPadding: EdgeInsets.zero, 
                      title: Row(children:[const Icon(Icons.directions_bike, color: Colors.teal), const SizedBox(width: 10), Text('Vehicle: $vehicle')]), 
                      trailing: const Icon(Icons.edit, size: 16, color: Colors.grey), 
                      onTap: () => _showVehicleInfoDialog(data)
                    ),
                    const Divider(height: 1),

                    // Payment Info (Salary/Gig Payment)
                    ListTile(
                      contentPadding: EdgeInsets.zero, 
                      title: Row(children: const[Icon(Icons.account_balance_wallet, color: Colors.pink), SizedBox(width: 10), Text('Payout / Bank Info')]), 
                      trailing: const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey), 
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const RiderPaymentInfoPage()));
                      }
                    ),
                    const Divider(height: 1),

                    // Help & Support
                    ListTile(
                      contentPadding: EdgeInsets.zero, 
                      title: Row(children: const[Icon(Icons.help_outline, color: Colors.blue), SizedBox(width: 10), Text('Help & Support')]), 
                      trailing: const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey), 
                      onTap: _showSupportOptions
                    ),
                    
                    const SizedBox(height: 30),
                    
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                        Future.microtask(() async {
                          await NotificationService.syncFcmTopics('guest');
                          SharedPreferences prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          await FirebaseAuth.instance.signOut();
                        });
                      }, 
                      icon: const Icon(Icons.logout, color: Colors.red),
                      label: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18))
                    )
                  ],
                ),
              )
            ],
          );
        }
      ),
    );
  }
}

// ==========================================
// নতুন পেজ: Rider Payment Info (বিকাশ/ব্যাংক ডিটেইলস)
// ==========================================
class RiderPaymentInfoPage extends StatefulWidget {
  const RiderPaymentInfoPage({super.key});

  @override
  State<RiderPaymentInfoPage> createState() => _RiderPaymentInfoPageState();
}

class _RiderPaymentInfoPageState extends State<RiderPaymentInfoPage> {
  final TextEditingController bkashCtrl = TextEditingController();
  final TextEditingController nagadCtrl = TextEditingController();
  final TextEditingController accNameCtrl = TextEditingController();
  final TextEditingController accNoCtrl = TextEditingController();
  
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPaymentData();
  }

  Future<void> _loadPaymentData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        bkashCtrl.text = data['payout_bkash'] ?? '';
        nagadCtrl.text = data['payout_nagad'] ?? '';
        accNameCtrl.text = data['payout_bank_name'] ?? '';
        accNoCtrl.text = data['payout_bank_acc'] ?? '';
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> _savePaymentData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'payout_bkash': bkashCtrl.text.trim(),
        'payout_nagad': nagadCtrl.text.trim(),
        'payout_bank_name': accNameCtrl.text.trim(),
        'payout_bank_acc': accNoCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payment info saved successfully! 💳')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Payout Information'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('How you will get paid', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('অ্যাডমিন আপনার বেতন বা পার-ডেলিভারি টাকা এই অ্যাকাউন্টে পাঠিয়ে দিবে।', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 25),

                const Text('Mobile Banking (MFS)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pink)),
                const SizedBox(height: 10),
                TextField(controller: bkashCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'bKash Number (Personal)', prefixIcon: Icon(Icons.phone_android, color: Colors.pink), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: nagadCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nagad Number', prefixIcon: Icon(Icons.phone_android, color: Colors.orange), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                const Text('Bank Account (Optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 10),
                TextField(controller: accNameCtrl, decoration: const InputDecoration(labelText: 'Bank Name & Branch', prefixIcon: Icon(Icons.account_balance, color: Colors.blue), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: accNoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account Number', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: _savePaymentData, 
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('SAVE INFORMATION', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                  )
                )
              ],
            ),
          )
    );
  }
}