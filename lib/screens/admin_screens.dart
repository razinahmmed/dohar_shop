import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'auth_screens.dart';
import 'package:dohar_shop/notification_service.dart';
import 'package:geolocator/geolocator.dart'; 
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'customer_screens.dart';
import 'package:url_launcher/url_launcher.dart';





// ==========================================
// অ্যাডমিন প্যানেল: Main Screen (Web Responsive + Badges)
// ==========================================
class AdminMainScreen extends StatefulWidget {
  final int initialPage; // 🔴 শুধু এই লাইনটি অ্যাড করুন
  const AdminMainScreen({super.key, this.initialPage = 0}); // 🔴 এখানে this.initialPage = 0 অ্যাড করুন

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  // 🔴 এখানে _selectedIndex = 0 না দিয়ে late লিখুন
  late int _selectedIndex;

  final List<Widget> _pages =[
    const AdminDashboard(),       
    const AdminUserManagement(),  
    const AdminOrderControl(),    
    const AdminFinanceReports(),  
    const AdminSettings(),        
  ];

  // 🔴 এই ব্লকটি নতুন করে যোগ করুন
  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPage; 
  }

  @override
  Widget build(BuildContext context) {
    // [NEW LOGIC] স্ক্রিনের সাইজ মাপা হচ্ছে। ৮০০ পিক্সেলের বড় হলে বুঝবে এটা কম্পিউটার/ওয়েব
    bool isDesktop = MediaQuery.of(context).size.width > 800;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        int actionNeeded = 0;
        if (snapshot.hasData) {
          actionNeeded = snapshot.data!.docs.where((doc) =>['Pending', 'Ready to Ship'].contains((doc.data() as Map<String, dynamic>)['status'])).length;
        }

        return Scaffold(
          // [NEW] ডেস্কটপের জন্য বাম পাশে মেনু (NavigationRail)
          body: Row(
            children:[
              if (isDesktop)
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (int index) {
                    setState(() {
                      _selectedIndex = index;
                    });
                  },
                  labelType: NavigationRailLabelType.all,
                  selectedLabelTextStyle: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold),
                  unselectedLabelTextStyle: const TextStyle(color: Colors.grey),
                  selectedIconTheme: const IconThemeData(color: Colors.deepOrange),
                  unselectedIconTheme: const IconThemeData(color: Colors.grey),
                  leading: const Padding(
                    padding: EdgeInsets.only(bottom: 20, top: 10),
                    child: CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.admin_panel_settings, color: Colors.white)),
                  ),
                  destinations:[
                    const NavigationRailDestination(icon: Icon(Icons.dashboard), label: Text('Dashboard')),
                    const NavigationRailDestination(icon: Icon(Icons.people_alt), label: Text('Users')),
                    NavigationRailDestination(
                      icon: Stack(
                        clipBehavior: Clip.none,
                        children:[
                          const Icon(Icons.receipt_long),
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
                      label: const Text('Orders')
                    ),
                    const NavigationRailDestination(icon: Icon(Icons.account_balance_wallet), label: Text('Finance')),
                    const NavigationRailDestination(icon: Icon(Icons.settings), label: Text('Settings')),
                  ],
                ),
                
              if (isDesktop) const VerticalDivider(thickness: 1, width: 1),
              
              // মূল পেজগুলো দেখানোর জায়গা
              Expanded(child: _pages[_selectedIndex]),
            ],
          ),
          
          // [NEW] যদি মোবাইল হয়, তবেই কেবল নিচের মেনু (Bottom Nav) দেখাবে
          bottomNavigationBar: isDesktop ? null : BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.deepOrange,
            unselectedItemColor: Colors.grey,
            onTap: (index) => setState(() => _selectedIndex = index),
            items:[
              const BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
              const BottomNavigationBarItem(icon: Icon(Icons.people_alt), label: 'Users'),
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children:[
                    const Icon(Icons.receipt_long),
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
                label: 'Orders'
              ),
              const BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Finance'),
              const BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
            ],
          ),
        );
      }
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ ১: Dashboard (Clickable Real-Time Live Stats)
// ==========================================
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, 
        title: const Text('D Shop ADMIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children:[
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(color: Colors.deepOrange),
              accountName: FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).get(),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data!.exists) {
                    return Text(snapshot.data!['name'] ?? 'Admin', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                  }
                  return const Text('Chief Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                },
              ),
              accountEmail: const Text('Super Admin Panel', style: TextStyle(color: Colors.white70)),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white, 
                child: Icon(Icons.admin_panel_settings, size: 40, color: Colors.deepOrange)
              ),
            ),
              ListTile(leading: const Icon(Icons.notifications_active, color: Colors.blue), title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Send offers to all', style: TextStyle(fontSize: 10, color: Colors.grey)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminNotificationPage())); }),
              ListTile(leading: const Icon(Icons.category, color: Colors.teal), title: const Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminManageCategoriesPage())); }),
              ListTile(leading: const Icon(Icons.view_carousel, color: Colors.orange), title: const Text('Manage Banners', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminBannerManagementPage())); }),
              ListTile(leading: const Icon(Icons.motorcycle, color: Colors.purple), title: const Text('Manage Riders', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminManageRidersPage())); }),
              ListTile(leading: const Icon(Icons.map, color: Colors.green), title: const Text('Delivery Zones & Charges', style: TextStyle(fontWeight: FontWeight.bold)), onTap: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminDeliveryZonePage())); }),
              const Divider(height: 30, thickness: 1),

              // 🔴 নতুন ম্যানুয়াল অর্ডার বাটন
              ListTile(
                leading: const Icon(Icons.support_agent, color: Colors.deepOrange), 
                title: const Text('Tele-Sales (Manual Order)', style: TextStyle(fontWeight: FontWeight.bold)), 
                subtitle: const Text('কল রিসিভ করে কাস্টমারের অর্ডার দিন', style: TextStyle(fontSize: 10)),
                onTap: () { 
                  Navigator.pop(context); 
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminManualOrderPage())); 
                }
              ),

              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text('Secure Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                onTap: () {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                  Future.microtask(() async {
                    await NotificationService.syncFcmTopics('guest');
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    await FirebaseAuth.instance.signOut();
                  });
                },
              ),

              ListTile(
                leading: const Icon(Icons.bug_report, color: Colors.red),
                title: const Text('Notification Tester', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Check sounds & pop-ups for all roles'),
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminNotificationTester()));
                },
              ),
          ],
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            const Text('Live System Stats', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),

            // রিয়েল-টাইম গ্রিড কার্ড (এখন ক্লিকেবল)
            GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 15,
              mainAxisSpacing: 15,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children:[
                _buildLiveStatCard(context, 'Total Orders', Icons.shopping_cart, Colors.blue, FirebaseFirestore.instance.collection('orders').snapshots(), const AdminAllOrdersPage()),
                _buildLiveStatCard(context, 'Customers', Icons.people, Colors.green, FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'customer').snapshots(), const AdminUserStatusPage(role: 'customer', title: 'Customer Management')),
                _buildLiveStatCard(context, 'Active Sellers', Icons.storefront, Colors.orange, FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'seller').where('status', isEqualTo: 'approved').snapshots(), const AdminUserStatusPage(role: 'seller', title: 'Active Sellers')),
                _buildLiveStatCard(context, 'Live Products', Icons.inventory_2, Colors.purple, FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').snapshots(), const AdminLiveProductsPage()),
              ],
            ),
            
            const SizedBox(height: 30),
            const Text('Action Center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminProductApprovalPage())),
              child: _buildActionCard('Pending Products', Icons.pending_actions, Colors.deepOrange, FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'pending').snapshots(), 'products need your approval'),
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserManagement())),
              child: _buildActionCard('Pending Sellers', Icons.how_to_reg, Colors.teal, FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'seller').where('status', isEqualTo: 'pending').snapshots(), 'sellers waiting for approval'),
            ),
          ],
        ),
      ),
    );
  }

  // হেল্পার: ক্লিকেবল লাইভ স্ট্যাট কার্ড
  Widget _buildLiveStatCard(BuildContext context, String title, IconData icon, MaterialColor color, Stream<QuerySnapshot> stream, Widget destinationPage) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => destinationPage)),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: color.shade200)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            StreamBuilder<QuerySnapshot>(
              stream: stream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2));
                int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                return Text(count.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color.shade700));
              }
            ),
            const SizedBox(height: 5),
            Text(title, style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, IconData icon, Color color, Stream<QuerySnapshot> stream, String subtitleSuffix) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow:[BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, 5))]),
      child: Row(
        children:[
          CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                StreamBuilder<QuerySnapshot>(
                  stream: stream,
                  builder: (context, snapshot) {
                    int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                    return Text('$count $subtitleSuffix', style: const TextStyle(color: Colors.grey, fontSize: 13));
                  },
                ),
              ],
            ),
          ),
          const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        ],
      ),
    );
  }
}

// ==========================================
// নতুন পেজ ১: Admin All Orders (Status & Rating)
// ==========================================
class AdminAllOrdersPage extends StatelessWidget {
  const AdminAllOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('All Orders & Status', style: TextStyle(color: Colors.white, fontSize: 18)), backgroundColor: Colors.blue),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').orderBy('order_date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো অর্ডার পাওয়া যায়নি।'));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              
              String status = data['status'] ?? 'Pending';
              Color statusColor = status == 'Pending' ? Colors.orange : (status == 'Shipped' ? Colors.blue : (status == 'Delivered' ? Colors.green : Colors.red));
              
              // গ্রাহকের রেটিং (যদি থাকে)
              double rating = data.containsKey('rating') ? double.parse(data['rating'].toString()) : 0.0;

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Text('ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                          )
                        ],
                      ),
                      const Divider(),
                      Text('Customer: ${data['shipping_name'] ?? 'Unknown'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text('Phone: ${data['shipping_phone'] ?? 'N/A'}', style: const TextStyle(color: Colors.grey, fontSize: 13)),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Text('Total: ৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                          // রেটিং সেকশন
                          Row(
                            children:[
                              Icon(Icons.star, color: rating > 0 ? Colors.amber : Colors.grey.shade300, size: 18),
                              const SizedBox(width: 4),
                              Text(rating > 0 ? '$rating / 5' : 'No rating yet', style: TextStyle(color: rating > 0 ? Colors.black87 : Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }
}

// ==========================================
// নতুন পেজ ২: Customer / Active Seller Management (Online/Offline)
// ==========================================
class AdminUserStatusPage extends StatefulWidget {
  final String role; // 'customer' or 'seller'
  final String title;
  const AdminUserStatusPage({super.key, required this.role, required this.title});

  @override
  State<AdminUserStatusPage> createState() => _AdminUserStatusPageState();
}

class _AdminUserStatusPageState extends State<AdminUserStatusPage> {
  bool showOnline = true; // ডিফল্টভাবে অনলাইন ইউজার দেখাবে

  // নোটিফিকেশন পাঠানোর ফাংশন
  void _sendNotification(BuildContext context, {String? userId, bool isBulk = false}) {
    TextEditingController msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isBulk ? 'Send Notification to All ${showOnline ? 'Online' : 'Offline'} ${widget.role}s' : 'Send Direct Message'),
        content: TextField(controller: msgCtrl, decoration: const InputDecoration(hintText: 'Type your message here...')),
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (msgCtrl.text.isEmpty) return;
              await FirebaseFirestore.instance.collection('notifications').add({
                'title': isBulk ? 'Admin Notice' : 'Personal Message',
                'message': msgCtrl.text.trim(),
                'target_user_id': isBulk ? null : userId,
                'topic': isBulk ? (widget.role == 'rider' ? 'riders' : 'all_users') : null,  // 🔴 এখানে পরিবর্তন
                'target_role': isBulk ? widget.role : null,
                'sent_at': FieldValue.serverTimestamp(),
                'data': {  // 🔴 এই অংশ যোগ করুন
                  'screen': 'notifications',
                }
              });
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification sent successfully!')));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          )
        ],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    Color themeColor = widget.role == 'customer' ? Colors.green : Colors.orange;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 18)), backgroundColor: themeColor),
      body: StreamBuilder<QuerySnapshot>(
        // Role অনুযায়ী ডাটা আনা হচ্ছে
        stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: widget.role).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData) return const SizedBox();

          var allUsers = snapshot.data!.docs.where((doc) {
            if (widget.role == 'seller') {
              return (doc.data() as Map<String, dynamic>)['status'] == 'approved'; // শুধু এপ্রুভড সেলার
            }
            return true;
          }).toList();

          // অনলাইন/অফলাইন ফিল্টার (is_online ফিল্ড চেক করা হচ্ছে, না থাকলে অফলাইন ধরা হবে)
          List<QueryDocumentSnapshot> onlineUsers = [];
          List<QueryDocumentSnapshot> offlineUsers =[];
          
          for (var doc in allUsers) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            bool isOnline = data['is_online'] ?? false; // ফায়ারবেসে is_online না থাকলে false
            if (isOnline) {
              onlineUsers.add(doc);
            } else {
              offlineUsers.add(doc);
            }
          }

          List<QueryDocumentSnapshot> displayUsers = showOnline ? onlineUsers : offlineUsers;

          return Column(
            children:[
              // ==========================================
              // Top Online / Offline Buttons
              // ==========================================
              Padding(
                padding: const EdgeInsets.all(15.0),
                child: Row(
                  children:[
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => showOnline = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: showOnline ? Colors.green : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.green),
                            boxShadow: showOnline ? [const BoxShadow(color: Colors.black12, blurRadius: 5)] :[]
                          ),
                          child: Column(
                            children:[
                              Text('${onlineUsers.length}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: showOnline ? Colors.white : Colors.green)),
                              Text('Online', style: TextStyle(color: showOnline ? Colors.white : Colors.green)),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: InkWell(
                        onTap: () => setState(() => showOnline = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: !showOnline ? Colors.redAccent : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                            boxShadow: !showOnline ? [const BoxShadow(color: Colors.black12, blurRadius: 5)] :[]
                          ),
                          child: Column(
                            children:[
                              Text('${offlineUsers.length}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: !showOnline ? Colors.white : Colors.redAccent)),
                              Text('Offline', style: TextStyle(color: !showOnline ? Colors.white : Colors.redAccent)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Bulk Notification Button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15.0),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                    onPressed: displayUsers.isEmpty ? null : () => _sendNotification(context, isBulk: true), 
                    icon: const Icon(Icons.campaign, color: Colors.white), 
                    label: Text('Send Notice to ${showOnline ? 'Online' : 'Offline'} List', style: const TextStyle(color: Colors.white))
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // ==========================================
              // Users List
              // ==========================================
              Expanded(
                child: displayUsers.isEmpty 
                ? Center(child: Text('No ${showOnline ? 'online' : 'offline'} ${widget.role} found.'))
                : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: displayUsers.length,
                  itemBuilder: (context, index) {
                    var doc = displayUsers[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    String name = data.containsKey('shop_name') && data['shop_name'].toString().isNotEmpty ? data['shop_name'] : data['name'] ?? 'Unknown';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: showOnline ? Colors.green.shade100 : Colors.red.shade50,
                          child: Icon(Icons.person, color: showOnline ? Colors.green : Colors.redAccent),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(data['email'] ?? 'No email', style: const TextStyle(fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.send, color: Colors.blue),
                          tooltip: 'Send Notification',
                          onPressed: () => _sendNotification(context, userId: doc.id),
                        ),
                      ),
                    );
                  }
                )
              )
            ],
          );
        }
      ),
    );
  }
}

// ==========================================
// নতুন পেজ ৩: Live Products Analytics (Sales, Views, Date)
// ==========================================
class AdminLiveProductsPage extends StatefulWidget {
  const AdminLiveProductsPage({super.key});

  @override
  State<AdminLiveProductsPage> createState() => _AdminLiveProductsPageState();
}

class _AdminLiveProductsPageState extends State<AdminLiveProductsPage> {
  String sortBy = 'newest'; // 'newest' or 'sales'

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Live Products Analytics', style: TextStyle(color: Colors.white, fontSize: 18)), 
        backgroundColor: Colors.purple,
        actions:[
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white),
            onSelected: (val) => setState(() => sortBy = val),
            itemBuilder: (context) =>[
              const PopupMenuItem(value: 'newest', child: Text('Sort by Newest')),
              const PopupMenuItem(value: 'sales', child: Text('Sort by Highest Sales')),
            ]
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো লাইভ প্রোডাক্ট নেই।'));

          var products = snapshot.data!.docs.toList();
          
          // সর্টিং লজিক (Custom Sorting)
          products.sort((a, b) {
            var dataA = a.data() as Map<String, dynamic>;
            var dataB = b.data() as Map<String, dynamic>;
            
            if (sortBy == 'sales') {
              int salesA = dataA['sales_count'] ?? 0;
              int salesB = dataB['sales_count'] ?? 0;
              return salesB.compareTo(salesA); // Highest sales first
            } else {
              Timestamp? tA = dataA['timestamp'] as Timestamp?;
              Timestamp? tB = dataB['timestamp'] as Timestamp?;
              if (tA == null || tB == null) return 0;
              return tB.compareTo(tA); // Newest first
            }
          });

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: products.length,
            itemBuilder: (context, index) {
              var doc = products[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              String firstImage = data.containsKey('image_urls') && (data['image_urls'] as List).isNotEmpty ? data['image_urls'][0] : '';
              int salesCount = data['sales_count'] ?? 0;
              
              // কতোদিন আগে অ্যাড করা হয়েছে তার হিসাব
              String daysAgoText = 'Recently added';
              if (data['timestamp'] != null) {
                DateTime dateAdded = (data['timestamp'] as Timestamp).toDate();
                int days = DateTime.now().difference(dateAdded).inDays;
                if (days == 0) {
                  daysAgoText = 'Added today';
                } else if (days == 1) daysAgoText = 'Added yesterday';
                else daysAgoText = 'Added $days days ago';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                child: Padding(
                  padding: const EdgeInsets.all(10.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Container(
                        height: 80, width: 80,
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(8)),
                        child: firstImage.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['product_name'] ?? 'Product', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 5),
                            
                            // সেলারের নাম ফায়ারবেস থেকে আনার লজিক
                            FutureBuilder<DocumentSnapshot>(
                              future: FirebaseFirestore.instance.collection('users').doc(data['seller_id']).get(),
                              builder: (context, sellerSnap) {
                                String shopName = 'Loading shop...';
                                if (sellerSnap.hasData && sellerSnap.data!.exists) {
                                  var sData = sellerSnap.data!.data() as Map<String, dynamic>;
                                  shopName = sData['shop_name'] ?? sData['name'] ?? 'Unknown Shop';
                                }
                                return Row(
                                  children:[
                                    const Icon(Icons.storefront, size: 14, color: Colors.teal),
                                    const SizedBox(width: 4),
                                    Expanded(child: Text(shopName, style: const TextStyle(color: Colors.teal, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                  ],
                                );
                              }
                            ),
                            
                            const Divider(height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children:[
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children:[
                                    const Text('Total Sold', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    Text('$salesCount times', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                  ],
                                ),
                                Text(daysAgoText, style: const TextStyle(color: Colors.grey, fontSize: 11, fontStyle: FontStyle.italic)),
                              ],
                            )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }
}


// ==========================================
// অ্যাডমিন প্রোডাক্ট এপ্রুভাল পেজ (বিস্তারিত তথ্য ও ভেরিয়েন্ট সহ)
// ==========================================
class AdminProductApprovalPage extends StatefulWidget {
  const AdminProductApprovalPage({super.key});
  @override
  State<AdminProductApprovalPage> createState() => _AdminProductApprovalPageState();
}

class _AdminProductApprovalPageState extends State<AdminProductApprovalPage> {
  final TextEditingController rejectController = TextEditingController();
  Map<String, bool> flashSaleStates = {}; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('PENDING APPROVALS'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'pending').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) return const Center(child: Text('No pending products!'));
          
          return ListView.builder(
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] : [];
              List<dynamic> tags = data.containsKey('search_tags') ? data['search_tags'] :[];
              
              // নতুন ভেরিয়েন্ট ডাটা রিসিভ করা
              List<dynamic> variants = data.containsKey('variants') ? data['variants'] : [];
              String unit = data['variant_unit'] ?? '';
              
              String firstImage = images.isNotEmpty ? images[0] : '';
              bool isFlash = flashSaleStates[doc.id] ?? false;

              // আপলোডের সময় বের করা
              String uploadTime = 'Unknown Time';
              if (data['timestamp'] != null) {
                DateTime dt = (data['timestamp'] as Timestamp).toDate();
                uploadTime = '${dt.day}/${dt.month}/${dt.year}  at  ${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
              }

              return Card(
                margin: const EdgeInsets.all(10), elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ExpansionTile(
                  leading: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: firstImage.isNotEmpty 
                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover))
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                  title: Text(data['product_name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('Base Price: ৳${data['price']} | Total Stock: ${data['stock']}', style: const TextStyle(color: Colors.deepOrange)),
                  children:[
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          // সেলারের নাম ও আপলোডের সময়
                          FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection('users').doc(data['seller_id']).get(),
                            builder: (context, sellerSnap) {
                              String sellerName = 'Loading...';
                              if (sellerSnap.hasData && sellerSnap.data!.exists) {
                                var sData = sellerSnap.data!.data() as Map<String, dynamic>;
                                sellerName = sData.containsKey('shop_name') && sData['shop_name'].toString().isNotEmpty ? sData['shop_name'] : sData['name'] ?? 'Unknown';
                              }
                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  children:[
                                    const Icon(Icons.storefront, color: Colors.blue, size: 18),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text('Seller: $sellerName', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))),
                                    const Icon(Icons.access_time, color: Colors.grey, size: 14),
                                    const SizedBox(width: 4),
                                    Text(uploadTime, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  ],
                                ),
                              );
                            }
                          ),
                          const SizedBox(height: 15),

                          // সব ছবি দেখানো
                          if(images.isNotEmpty) 
                            SizedBox(
                              height: 60, 
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal, 
                                itemCount: images.length, 
                                itemBuilder: (context, i) => Container(margin: const EdgeInsets.only(right: 10), width: 60, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), image: DecorationImage(image: NetworkImage(images[i]), fit: BoxFit.cover)))
                              )
                            ),
                          const Divider(height: 20),
                          
                          Text('Category: ${data['category']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          
                          // ===================================
                          // নতুন ভেরিয়েন্ট টেবিল (অ্যাডমিনের দেখার জন্য)
                          // ===================================
                          const Text('Product Variants & Stock Breakdown:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                          const SizedBox(height: 5),
                          if (variants.isEmpty)
                            const Text('No variants added.', style: TextStyle(color: Colors.red))
                          else
                            Container(
                              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                              child: Column(
                                children: variants.map((v) {
                                  return Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                                    child: Row(
                                      children:[
                                        if (v['color_image_url'] != null)
                                          Container(width: 30, height: 30, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), image: DecorationImage(image: NetworkImage(v['color_image_url']), fit: BoxFit.cover))),
                                        Expanded(child: Text('${v['color']} - ${v['size']} $unit', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                                        Text('Stock: ${v['stock']}   |   ', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                        Text('+৳${v['price']}', style: const TextStyle(fontSize: 13, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          
                          const SizedBox(height: 15),
                          if(tags.isNotEmpty) Text('Tags: ${tags.join(", ")}', style: const TextStyle(color: Colors.blue, fontSize: 12)),
                          const SizedBox(height: 10),
                          const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(data['description'] ?? 'No description', style: const TextStyle(fontSize: 13)),
                          const Divider(height: 30),

                          // একশনের অংশ (এপ্রুভ/রিজেক্ট)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: [
                                const Text('Set Flash Sale?', style: TextStyle(fontWeight: FontWeight.bold)),
                                Switch(
                                    value: isFlash,
                                    activeThumbColor: Colors.deepOrange,
                                    onChanged: (v) => setState(() => flashSaleStates[doc.id] = v))
                              ]),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.teal,
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
                                onPressed: () async {
                                  // [UPDATE] ডাটা আপডেট এবং নোটিফিকেশন পাঠানো
                                  await doc.reference.update({
                                    'status': 'approved',
                                    'is_flash_sale': isFlash,
                                    'reject_reason': ""
                                  });

                                  // [NEW] এপ্রুভ নোটিফিকেশন সেলারকে পাঠানো
                                  await FirebaseFirestore.instance.collection('notifications').add({
                                    'target_user_id': data['seller_id'],
                                    'title': 'Product Approved ✅',
                                    'message': 'অভিনন্দন! আপনার প্রোডাক্ট "${data['product_name']}" লাইভ হয়েছে।',
                                    'sent_at': FieldValue.serverTimestamp(),
                                    'data': { 'screen': 'products' }  // 🔴 যোগ করুন
                                  });

                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Product Approved Successfully! ✅')));
                                },
                                icon: const Icon(Icons.check, color: Colors.white),
                                label: const Text('APPROVE',
                                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 15),
                          Row(
                            children: [
                              Expanded(
                                  child: TextField(
                                      controller: rejectController,
                                      decoration: const InputDecoration(
                                          hintText: 'রিজেক্টের কারণ লিখুন...',
                                          border: OutlineInputBorder(),
                                          contentPadding:
                                              EdgeInsets.symmetric(horizontal: 10, vertical: 0)))),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () async {
                                  if (rejectController.text.isEmpty) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(const SnackBar(content: Text('দয়া করে কারণ লিখুন!')));
                                    return;
                                  }

                                  // [UPDATE] ডাটা আপডেট
                                  await doc.reference.update({
                                    'status': 'rejected',
                                    'reject_reason': rejectController.text.trim()
                                  });

                                  // [NEW] রিজেক্ট নোটিফিকেশন সেলারকে পাঠানো
                                  await FirebaseFirestore.instance.collection('notifications').add({
                                    'target_user_id': data['seller_id'],
                                    'title': 'Product Rejected ❌',
                                    'message': 'আপনার প্রোডাক্ট "${data['product_name']}" রিজেক্ট করা হয়েছে। কারণ: ${rejectController.text.trim()}',
                                    'sent_at': FieldValue.serverTimestamp(),
                                    'data': { 'screen': 'products' }  // 🔴 যোগ করুন
                                  });

                                  rejectController.clear();
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(content: Text('Product Rejected! ❌')));
                                },
                                child: const Text('REJECT', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          )
                        ],
                      ),
                    )
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ ২: User & Seller Management (Pro UI, Search, Filter, Stats, WA & Ban)
// ==========================================
class AdminUserManagement extends StatefulWidget {
  const AdminUserManagement({super.key});

  @override
  State<AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<AdminUserManagement> {
  int _selectedTab = 0; // 0 = Customers, 1 = Sellers
  String searchQuery = '';
  String selectedFilter = 'All'; // All, Active, Banned, Pending (for sellers)

  @override
  Widget build(BuildContext context) {
    bool isSellerTab = _selectedTab == 1;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.orange[200], 
        title: const Text('Management Hub', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), 
        iconTheme: const IconThemeData(color: Colors.black)
      ),
      body: Column(
        children:[
          // 🔴 টগল বাটন
          Padding(
            padding: const EdgeInsets.all(15), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, 
              children:[
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() { _selectedTab = 0; selectedFilter = 'All'; }), 
                    style: ElevatedButton.styleFrom(backgroundColor: !isSellerTab ? Colors.deepOrange : Colors.white, foregroundColor: !isSellerTab ? Colors.white : Colors.black), 
                    child: const Text('Customers')
                  )
                ), 
                const SizedBox(width: 10), 
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() { _selectedTab = 1; selectedFilter = 'All'; }), 
                    style: ElevatedButton.styleFrom(backgroundColor: isSellerTab ? Colors.teal : Colors.white, foregroundColor: isSellerTab ? Colors.white : Colors.black), 
                    child: const Text('Sellers')
                  )
                )
              ]
            )
          ),

          // 🔴 সার্চ এবং ফিল্টার বার
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) => setState(() => searchQuery = val.toLowerCase().trim()),
                    decoration: InputDecoration(
                      hintText: 'Search name, email or phone...',
                      prefixIcon: const Icon(Icons.search, color: Colors.grey),
                      filled: true, fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                  child: PopupMenuButton<String>(
                    icon: const Icon(Icons.filter_list, color: Colors.deepOrange),
                    tooltip: 'Filter Users',
                    onSelected: (val) => setState(() => selectedFilter = val),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'All', child: Text('All Users')),
                      const PopupMenuItem(value: 'Active', child: Text('Active Only', style: TextStyle(color: Colors.green))),
                      const PopupMenuItem(value: 'Banned', child: Text('Banned/Frozen', style: TextStyle(color: Colors.red))),
                      if (isSellerTab) const PopupMenuItem(value: 'Pending', child: Text('Pending Approval', style: TextStyle(color: Colors.orange))),
                    ]
                  ),
                )
              ],
            ),
          ),
          
          if (selectedFilter != 'All')
             Padding(
               padding: const EdgeInsets.only(top: 10, left: 15),
               child: Align(alignment: Alignment.centerLeft, child: Text('Showing: $selectedFilter', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange))),
             ),

          const SizedBox(height: 10),

          // 🔴 ডাটাবেস থেকে ইউজার লিস্ট
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('users')
                  .where('role', isEqualTo: !isSellerTab ? 'customer' : 'seller')
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Text(!isSellerTab ? 'No customers found!' : 'No sellers found!', style: const TextStyle(color: Colors.grey)));

                var users = snapshot.data!.docs.where((doc) {
                  Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                  String name = (data['name']?.toString() ?? '').toLowerCase();
                  String sName = (data['shop_name']?.toString() ?? '').toLowerCase();
                  String phone = (data['phone']?.toString() ?? '').toLowerCase();
                  String status = data['status']?.toString() ?? 'active';
                  
                  // সার্চ লজিক
                  bool matchesSearch = name.contains(searchQuery) || sName.contains(searchQuery) || phone.contains(searchQuery);
                  
                  // ফিল্টার লজিক
                  bool matchesFilter = true;
                  if (selectedFilter == 'Active') matchesFilter = (status == 'active' || status == 'approved');
                  if (selectedFilter == 'Banned') matchesFilter = (status == 'banned' || status == 'frozen');
                  if (selectedFilter == 'Pending') matchesFilter = (status == 'pending');

                  return matchesSearch && matchesFilter;
                }).toList();

                if (users.isEmpty) return const Center(child: Text('No matching results found.'));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    return UserAdminCard(
                      userDoc: users[index], 
                      isSeller: isSellerTab
                    );
                  }
                );
              }
            ),
          )
        ],
      ),
    );
  }
}

// 🔴 কার্ডের জন্য আলাদা উইজেট (Null Safe)
class UserAdminCard extends StatefulWidget {
  final QueryDocumentSnapshot userDoc;
  final bool isSeller;
  const UserAdminCard({super.key, required this.userDoc, required this.isSeller});

  @override
  State<UserAdminCard> createState() => _UserAdminCardState();
}

class _UserAdminCardState extends State<UserAdminCard> {
  int totalOrders = 0;
  int successOrders = 0;
  int failedOrders = 0;
  String userAddress = 'Loading address...';

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _fetchAddress();
  }

  Future<void> _fetchStats() async {
    try {
      QuerySnapshot ordersSnap;
      if (widget.isSeller) {
        ordersSnap = await FirebaseFirestore.instance.collection('orders').get(); 
      } else {
        ordersSnap = await FirebaseFirestore.instance.collection('orders').where('user_id', isEqualTo: widget.userDoc.id).get();
        int t = 0, s = 0, f = 0;
        for (var doc in ordersSnap.docs) {
          t++;
          Map<String, dynamic>? oData = doc.data() as Map<String, dynamic>?;
          if (oData != null) {
            String status = oData['status']?.toString() ?? '';
            if (status == 'Delivered') s++;
            if (status == 'Delivery Failed' || status == 'Cancelled') f++;
          }
        }
        if (mounted) setState(() { totalOrders = t; successOrders = s; failedOrders = f; });
      }
    } catch (e) {
      debugPrint("Stat fetch error: $e");
    }
  }

  Future<void> _fetchAddress() async {
    Map<String, dynamic> data = widget.userDoc.data() as Map<String, dynamic>? ?? {};
    if (widget.isSeller) {
       setState(() => userAddress = data['shop_address']?.toString() ?? 'No address set');
    } else {
      var snap = await FirebaseFirestore.instance.collection('users').doc(widget.userDoc.id).collection('addresses').where('is_default', isEqualTo: true).limit(1).get();
      if (snap.docs.isNotEmpty && mounted) {
        Map<String, dynamic> addrData = snap.docs.first.data() as Map<String, dynamic>? ?? {};
        setState(() => userAddress = addrData['shipping_address_text']?.toString() ?? 'No saved address');
      } else {
        if (mounted) setState(() => userAddress = 'No saved address');
      }
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    if (phone.isEmpty || phone == 'No Phone') return;
    String cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (cleanPhone.startsWith('0')) cleanPhone = '88$cleanPhone';
    final Uri waUrl = Uri.parse("https://wa.me/$cleanPhone");
    if (await canLaunchUrl(waUrl)) await launchUrl(waUrl, mode: LaunchMode.externalApplication);
  }

  Future<void> _makePhoneCall(String phone) async {
    if (phone.isEmpty || phone == 'No Phone') return;
    final Uri callUrl = Uri.parse("tel:$phone");
    if (await canLaunchUrl(callUrl)) await launchUrl(callUrl);
  }

  Future<void> _changeUserStatus(String newStatus) async {
    await widget.userDoc.reference.update({'status': newStatus});
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('User marked as ${newStatus.toUpperCase()}')));
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = widget.userDoc.data() as Map<String, dynamic>? ?? {};
    String status = data['status']?.toString() ?? (widget.isSeller ? 'pending' : 'active');
    bool isBanned = status == 'banned' || status == 'frozen';
    
    String imgUrl = data['profile_image_url']?.toString() ?? '';
    
    // 🔴 Null safe name logic
    String userName = 'Unknown User';
    if (widget.isSeller && data['shop_name'] != null && data['shop_name'].toString().trim().isNotEmpty) {
      userName = data['shop_name'].toString();
    } else if (data['name'] != null && data['name'].toString().trim().isNotEmpty) {
      userName = data['name'].toString();
    }

    String phone = data['phone']?.toString() ?? 'No Phone';

    return Container(
      margin: const EdgeInsets.only(bottom: 15), 
      decoration: BoxDecoration(
        color: isBanned ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: isBanned ? Colors.red.shade300 : Colors.grey.shade300, width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 4))]
      ),
      child: Padding(
        padding: const EdgeInsets.all(15.0),
        child: Column(
          children:[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                CircleAvatar(
                  radius: 25, backgroundColor: Colors.grey.shade200,
                  backgroundImage: imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                  child: imgUrl.isEmpty ? Icon(widget.isSeller ? Icons.store : Icons.person, color: Colors.grey) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children:[
                      Text(userName, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, decoration: isBanned ? TextDecoration.lineThrough : null)), 
                      Text(phone, style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 13)),
                      if (widget.isSeller)
                        Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: status == 'approved' ? Colors.green.shade50 : (status == 'pending' ? Colors.orange.shade50 : Colors.red.shade50), borderRadius: BorderRadius.circular(5)), child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: status == 'approved' ? Colors.green : (status == 'pending' ? Colors.orange : Colors.red))))
                      else if (isBanned)
                        Container(margin: const EdgeInsets.only(top: 4), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(5)), child: const Text('BANNED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)))
                    ]
                  )
                ),
                
                // 🔴 Contact & Actions
                Row(
                  children: [
                    InkWell(onTap: () => _launchWhatsApp(phone), child: Image.asset('assets/icons/whatsapp.png', width: 28, height: 28, errorBuilder: (c,e,s) => const Icon(Icons.chat, color: Colors.green))),
                    const SizedBox(width: 10),
                    InkWell(onTap: () => _makePhoneCall(phone), child: const CircleAvatar(radius: 14, backgroundColor: Colors.blue, child: Icon(Icons.call, size: 14, color: Colors.white))),
                    
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert, color: Colors.grey),
                      onSelected: (val) {
                        if (val == 'ban') _changeUserStatus('banned');
                        else if (val == 'unban') _changeUserStatus(widget.isSeller ? 'approved' : 'active');
                        else if (val == 'delete') {
                          widget.userDoc.reference.delete();
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User deleted permanently!')));
                        }
                      },
                      itemBuilder: (context) => [
                        if (!isBanned) const PopupMenuItem(value: 'ban', child: Text('Block / Ban User', style: TextStyle(color: Colors.red))),
                        if (isBanned) const PopupMenuItem(value: 'unban', child: Text('Unban / Activate', style: TextStyle(color: Colors.green))),
                        const PopupMenuItem(value: 'delete', child: Text('Delete Permanently', style: TextStyle(color: Colors.red))),
                      ]
                    )
                  ],
                )
              ],
            ),
            
            const Divider(height: 20),
            
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Icon(Icons.location_on, color: Colors.red, size: 16),
                const SizedBox(width: 5),
                Expanded(child: Text(userAddress, style: const TextStyle(fontSize: 12, color: Colors.black54))),
              ]
            ),
            const SizedBox(height: 12),

            if (!widget.isSeller)
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(children: [const Text('Total Orders', style: TextStyle(fontSize: 10, color: Colors.grey)), Text('$totalOrders', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue))]),
                    Column(children: [const Text('Success', style: TextStyle(fontSize: 10, color: Colors.grey)), Text('$successOrders', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))]),
                    Column(children: [const Text('Failed/Cancel', style: TextStyle(fontSize: 10, color: Colors.grey)), Text('$failedOrders', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red))]),
                  ],
                ),
              ),

            const SizedBox(height: 10),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children:[
                  if (widget.isSeller) ...[
                    TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminSellerProductsPage(sellerId: widget.userDoc.id, sellerName: userName))), icon: const Icon(Icons.inventory_2, size: 16, color: Colors.deepPurple), label: const Text('Products', style: TextStyle(color: Colors.deepPurple))),
                    TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminSellerSalesPage(sellerId: widget.userDoc.id, sellerName: userName))), icon: const Icon(Icons.bar_chart, size: 16, color: Colors.teal), label: const Text('Sales', style: TextStyle(color: Colors.teal))),
                    TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ShopPage(sellerId: widget.userDoc.id))), icon: const Icon(Icons.storefront, size: 16, color: Colors.deepOrange), label: const Text('View Shop', style: TextStyle(color: Colors.deepOrange))),
                    if (status == 'pending')
                      ElevatedButton(onPressed: () => _changeUserStatus('approved'), style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, visualDensity: VisualDensity.compact), child: const Text('Approve', style: TextStyle(color: Colors.white)))
                  ] else ...[
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(backgroundColor: Colors.blue.shade50),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminCustomerOrdersPage(customerId: widget.userDoc.id, customerName: userName))), 
                        icon: const Icon(Icons.receipt_long, size: 16, color: Colors.blue), 
                        label: const Text('View Full Order History', style: TextStyle(color: Colors.blue))
                      ),
                    )
                  ]
                ]
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// নতুন সাব-পেজ ১: সেলারের প্রোডাক্ট লিস্ট (With Moderation: Freeze/Delete)
// ==========================================
class AdminSellerProductsPage extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  const AdminSellerProductsPage({super.key, required this.sellerId, required this.sellerName});

  // 🔴 প্রোডাক্ট মডারেশন ফাংশন (Freeze বা Delete করার জন্য)
  void _moderateProduct(BuildContext context, DocumentSnapshot doc, String action, String productName) {
    TextEditingController reasonCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(action == 'freeze' ? 'Freeze Product ❄️' : 'Delete Product ❌', style: TextStyle(color: action == 'freeze' ? Colors.blue : Colors.red)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(action == 'freeze' ? 'এই প্রোডাক্টটি সাময়িকভাবে বন্ধ হয়ে যাবে।' : 'এই প্রোডাক্টটি সেলার এবং কাস্টমার সবার থেকে হাইড হয়ে যাবে (সফট ডিলিট)।', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(labelText: 'Reason (সেলারকে জানানো হবে)', border: OutlineInputBorder(), isDense: true),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: action == 'freeze' ? Colors.blue : Colors.red),
            onPressed: () async {
              if (reasonCtrl.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে কারণ উল্লেখ করুন!')));
                return;
              }
              
              String newStatus = action == 'freeze' ? 'frozen' : 'deleted';
              
              // 1. Update Database
              await doc.reference.update({
                'status': newStatus, 
                'is_active': false,
                'admin_action_reason': reasonCtrl.text.trim(),
              });

              // 2. Send Notification to Seller
              await FirebaseFirestore.instance.collection('notifications').add({
                'target_user_id': sellerId,
                'title': action == 'freeze' ? 'Product Frozen by Admin ❄️' : 'Product Removed by Admin ❌',
                'message': 'আপনার প্রোডাক্ট "$productName" অ্যাডমিন কর্তৃক ${action == 'freeze' ? 'ফ্রিজ' : 'রিমুভ'} করা হয়েছে। কারণ: ${reasonCtrl.text.trim()}',
                'sent_at': FieldValue.serverTimestamp(),
              });

              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Product $newStatus successfully!')));
              }
            },
            child: const Text('Confirm', style: TextStyle(color: Colors.white))
          )
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: Text('$sellerName\'s Products', style: const TextStyle(fontSize: 16)), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        // 🔴 আমরা সব স্ট্যাটাসের প্রোডাক্টই আনবো যাতে অ্যাডমিন ডিলিট করা প্রোডাক্টও দেখতে পারে
        stream: FirebaseFirestore.instance.collection('products').where('seller_id', isEqualTo: sellerId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('এই সেলার এখনো কোনো প্রোডাক্ট আপলোড করেননি।'));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              String img = data.containsKey('image_urls') && (data['image_urls'] as List).isNotEmpty ? data['image_urls'][0] : '';
              
              String status = data['status'] ?? 'pending';
              Color statusColor = status == 'approved' ? Colors.green : (status == 'pending' ? Colors.orange : Colors.red);

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300, width: 1.5), // 🔴 স্পষ্ট বর্ডার
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))] // 🔴 শ্যাডো
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(10),
                  leading: Container(width: 60, height: 60, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)), child: img.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(img, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)),
                  title: Text(data['product_name'] ?? 'Product', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 5.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Price: ৳${data['price']} | Stock: ${data['stock']}', style: const TextStyle(color: Colors.black87, fontSize: 12)),
                        const SizedBox(height: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), 
                          decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)), 
                          child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold))
                        ),
                      ],
                    ),
                  ),
                  
                  // 🔴 মডারেশন একশন মেনু (Freeze / Delete)
                  trailing: PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onSelected: (value) => _moderateProduct(context, doc, value, data['product_name'] ?? 'Product'),
                    itemBuilder: (context) => [
                      if (status != 'frozen' && status != 'deleted')
                        const PopupMenuItem(
                          value: 'freeze',
                          child: Row(children: [Icon(Icons.ac_unit, color: Colors.blue, size: 18), SizedBox(width: 8), Text('Freeze Product')]),
                        ),
                      if (status != 'deleted')
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(children: [Icon(Icons.delete, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete/Hide', style: TextStyle(color: Colors.red))]),
                        ),
                    ],
                  ),
                ),
              );
            }
          );
        },
      ),
    );
  }
}

// ==========================================
// নতুন সাব-পেজ ২: সেলারের বিক্রয় (Sales) রিপোর্ট
// ==========================================
class AdminSellerSalesPage extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  const AdminSellerSalesPage({super.key, required this.sellerId, required this.sellerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$sellerName\'s Sales', style: const TextStyle(fontSize: 16)), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('products').where('seller_id', isEqualTo: sellerId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো সেলস ডাটা পাওয়া যায়নি।'));

          // সেলস কাউন্ট অনুযায়ী সর্টিং
          var products = snapshot.data!.docs.where((doc) => ((doc.data() as Map<String, dynamic>)['sales_count'] ?? 0) > 0).toList();
          products.sort((a, b) => ((b.data() as Map<String, dynamic>)['sales_count'] ?? 0).compareTo((a.data() as Map<String, dynamic>)['sales_count'] ?? 0));

          if (products.isEmpty) return const Center(child: Text('এই সেলারের এখনো কোনো প্রোডাক্ট বিক্রি হয়নি।'));

          double totalRevenue = 0;
          for (var p in products) {
            var d = p.data() as Map<String, dynamic>;
            totalRevenue += ((d['sales_count'] ?? 0) * (int.tryParse(d['price'].toString()) ?? 0));
          }

          return Column(
            children:[
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20), color: Colors.teal.shade50,
                child: Column(
                  children:[
                    const Text('Total Estimated Sales Revenue', style: TextStyle(color: Colors.teal)),
                    Text('৳${totalRevenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.teal)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    var data = products[index].data() as Map<String, dynamic>;
                    return Card(
                      child: ListTile(
                        title: Text(data['product_name'] ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text('Price: ৳${data['price']}'),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:[
                            const Text('Sold', style: TextStyle(fontSize: 10, color: Colors.grey)),
                            Text('${data['sales_count']}x', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                          ],
                        ),
                      ),
                    );
                  }
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ==========================================
// নতুন সাব-পেজ ৩: কাস্টমারের অর্ডার হিস্ট্রি (Fixed and Beautiful)
// ==========================================
class AdminCustomerOrdersPage extends StatelessWidget {
  final String customerId;
  final String customerName;
  const AdminCustomerOrdersPage({super.key, required this.customerId, required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: Text('$customerName\'s Orders', style: const TextStyle(fontSize: 16)), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders')
            .where('user_id', isEqualTo: customerId)
            .orderBy('order_date', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.remove_shopping_cart, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  const Text('এই কাস্টমার এখনো কোনো অর্ডার করেননি।', style: TextStyle(color: Colors.grey)),
                ],
              )
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              
              String dateString = 'Unknown Date';
              if (data['order_date'] != null) {
                DateTime date = (data['order_date'] as Timestamp).toDate();
                dateString = '${date.day}/${date.month}/${date.year} at ${date.hour > 12 ? date.hour - 12 : date.hour}:${date.minute.toString().padLeft(2, '0')} ${date.hour >= 12 ? 'PM' : 'AM'}';
              }

              String status = data['status'] ?? 'Pending';
              Color statusColor = Colors.orange;
              if (status == 'Delivered') statusColor = Colors.green;
              if (status == 'Dispatched' || status == 'In-Transit') statusColor = Colors.purple;
              if (status == 'Delivery Failed' || status == 'Cancelled') statusColor = Colors.red;
              
              List items = data['items'] ?? [];

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Text('ID: #${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                            child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11)),
                          )
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text('Placed: $dateString', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      const Divider(height: 20),
                      
                      // 🔴 Ordered Items List
                      ...items.map((item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Row(
                          children: [
                            Container(width: 40, height: 40, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), image: DecorationImage(image: NetworkImage(item['image_url'] ?? ''), fit: BoxFit.cover))),
                            const SizedBox(width: 10),
                            Expanded(child: Text('${item['quantity']}x ${item['product_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                            Text('৳${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                      )).toList(),
                      
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Row(
                            children: [
                              Icon(Icons.payment, size: 16, color: Colors.grey.shade600),
                              const SizedBox(width: 5),
                              Text(data['payment_method'] ?? 'COD', style: const TextStyle(color: Colors.blueGrey, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Text('Total: ৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                        ],
                      )
                    ],
                  ),
                ),
              );
            }
          );
        },
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ ৩: Order & Delivery Control (With Details Modal & Image Zoom)
// ==========================================
class AdminOrderControl extends StatefulWidget {
  const AdminOrderControl({super.key});
  @override
  State<AdminOrderControl> createState() => _AdminOrderControlState();
}

class _AdminOrderControlState extends State<AdminOrderControl> {
  
  // [NEW] ফুল-স্ক্রিন ছবি দেখানোর ফাংশন (Zoom সাপোর্ট সহ)
  void _showFullScreenImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children:[
            InteractiveViewer(
              panEnabled: true, minScale: 0.5, maxScale: 4,
              child: Image.network(imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity),
            ),
            Positioned(
              top: 40, right: 20,
              child: IconButton(
                icon: const Icon(Icons.cancel, color: Colors.white, size: 35),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

  Widget _buildTimelineRow(String title, dynamic timestamp, bool isCompleted, {bool isLast = false, bool isError = false}) {
    String timeStr = '--';
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dt = timestamp.toDate();
      timeStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }
    Color activeColor = isError ? Colors.red : Colors.teal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          Column(
            children:[
              Icon(isCompleted ? (isError ? Icons.cancel : Icons.check_circle) : Icons.radio_button_unchecked, size: 16, color: isCompleted ? activeColor : Colors.grey),
              if (!isLast) Container(height: 15, width: 2, color: isCompleted ? activeColor : Colors.grey.shade300),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text(title, style: TextStyle(fontSize: 12, fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal, color: isCompleted ? (isError ? Colors.red : Colors.black87) : Colors.grey)),
                if (isCompleted && timestamp != null) Text(timeStr, style: TextStyle(fontSize: 10, color: activeColor)),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showOrderFullDetailsModal(Map<String, dynamic> data, String orderId) {
    String status = data['status'] ?? 'Pending';
    List<dynamic> items = data['items'] ??[];
    bool isReviewed = data['is_reviewed'] ?? false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Center(child: Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                Text('Order #${orderId.substring(0,8).toUpperCase()}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(5)), child: Text(status, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12))),
              ],
            ),
            const Divider(),

            Expanded(
              child: ListView(
                children:[
                  const Text('Order Tracking Timeline', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 10),
                  _buildTimelineRow('Order Placed', data['order_date'], true),
                  _buildTimelineRow('Confirmed & Processing', data['processing_at'], status != 'Pending'),
                  _buildTimelineRow('Packed & Ready to Ship', data['ready_to_ship_at'],['Ready to Ship', 'Dispatched', 'In-Transit', 'Delivered'].contains(status)),
                  _buildTimelineRow('Handed Over to Rider/Courier', data['dispatched_at'],['Dispatched', 'In-Transit', 'Delivered'].contains(status)),
                  if (status != 'Delivery Failed')
                    _buildTimelineRow('Delivered Successfully', data['delivered_at'], status == 'Delivered', isLast: true),
                  if (status == 'Delivery Failed')
                    _buildTimelineRow('Delivery Failed (${data['failed_reason']})', data['failed_at'], true, isLast: true, isError: true),
                  
                  const Divider(height: 30),

                  // [UPDATED] ২. প্রুফ ছবি (ক্লিক করলে বড় হবে)
                  if (data['proof_image_url'] != null || data['failed_proof_url'] != null) ...[
                    Text(data['proof_image_url'] != null ? 'Proof of Delivery (Success)' : 'Proof of Failed Delivery', style: TextStyle(fontWeight: FontWeight.bold, color: data['proof_image_url'] != null ? Colors.green : Colors.red)),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _showFullScreenImage(context, data['proof_image_url'] ?? data['failed_proof_url']),
                      child: Stack(
                        alignment: Alignment.center,
                        children:[
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(data['proof_image_url'] ?? data['failed_proof_url'], height: 200, width: double.infinity, fit: BoxFit.cover),
                          ),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.zoom_out_map, color: Colors.white),
                          )
                        ],
                      ),
                    ),
                    const Divider(height: 30),
                  ],

                  const Text('Ordered Items & Sellers', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 10),
                  ...items.map((item) {
                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance.collection('users').doc(item['seller_id']).get(),
                      builder: (context, snap) {
                        String sName = 'Loading shop...';
                        if (snap.hasData && snap.data!.exists) {
                          sName = (snap.data!.data() as Map<String, dynamic>)['shop_name'] ?? 'Seller';
                        }
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Container(width: 50, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(item['image_url'] ?? ''), fit: BoxFit.cover))),
                          title: Text(item['product_name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                              Text('Seller: $sName', style: const TextStyle(fontSize: 11, color: Colors.blue)),
                              Text('Qty: ${item['quantity']} | Price: ৳${item['price']}', style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
                            ],
                          ),
                        );
                      }
                    );
                  }),
                  const Divider(height: 30),

                  if (isReviewed) ...[
                    const Text('Customer Feedback & Rating', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 10),
                    Row(children: List.generate(5, (index) => Icon(Icons.star, size: 18, color: index < (data['rating'] ?? 0) ? Colors.orange : Colors.grey.shade300))),
                    const SizedBox(height: 5),
                    Text('"${data['review_text'] ?? ''}"', style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.black87)),
                    if (data['review_image_url'] != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: InkWell(
                          onTap: () => _showFullScreenImage(context, data['review_image_url']),
                          child: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(data['review_image_url'], height: 100, width: 100, fit: BoxFit.cover)),
                        ),
                      ),
                    const SizedBox(height: 20),
                  ]
                ],
              ),
            ),
            
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(context), child: const Text('Close Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
          ]
        )
      )
    );
  }

  void _showAssignDeliveryModal(String orderId) {
    String deliveryMethod = 'rider'; 
    String? selectedRiderId;
    TextEditingController courierNameCtrl = TextEditingController();
    TextEditingController trackingIdCtrl = TextEditingController();

    showModalBottomSheet(
      context: context, isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  const Text('Assign Delivery', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Row(
                    children:[
                      Expanded(child: RadioListTile<String>(contentPadding: EdgeInsets.zero, title: const Text('Own Rider', style: TextStyle(fontSize: 14)), value: 'rider', groupValue: deliveryMethod, activeColor: Colors.deepOrange, onChanged: (val) => setModalState(() => deliveryMethod = val!))),
                      Expanded(child: RadioListTile<String>(contentPadding: EdgeInsets.zero, title: const Text('Courier Service', style: TextStyle(fontSize: 14)), value: 'courier', groupValue: deliveryMethod, activeColor: Colors.deepOrange, onChanged: (val) => setModalState(() => deliveryMethod = val!))),
                    ]
                  ),
                  const Divider(),

                  if (deliveryMethod == 'rider') ...[
                    const Text('Select Available Rider:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                    const SizedBox(height: 10),
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance.collection('users').where('role', isEqualTo: 'rider').snapshots(),
                      builder: (context, snapshot) {
                        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                        var riders = snapshot.data!.docs;
                        if (riders.isEmpty) return const Text('No riders available!', style: TextStyle(color: Colors.red));
                        
                        return Container(
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true, hint: const Padding(padding: EdgeInsets.all(10.0), child: Text('Choose a rider')), value: selectedRiderId,
                              items: riders.map((r) {
                                var rData = r.data() as Map<String, dynamic>;
                                return DropdownMenuItem<String>(value: r.id, child: Padding(padding: const EdgeInsets.all(10.0), child: Text('${rData['name']} (${rData['phone'] ?? 'No Phone'})')));
                              }).toList(),
                              onChanged: (val) => setModalState(() => selectedRiderId = val),
                            ),
                          ),
                        );
                      }
                    )
                  ] 
                  else ...[
                    const Text('Enter Courier Details:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                    const SizedBox(height: 10),
                    TextField(controller: courierNameCtrl, decoration: const InputDecoration(labelText: 'Courier Name (e.g. Sundarban, Pathao)', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: trackingIdCtrl, decoration: const InputDecoration(labelText: 'Tracking ID / Memo No.', border: OutlineInputBorder(), isDense: true)),
                  ],

                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity, height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                      onPressed: () async {
                        if (deliveryMethod == 'rider' && selectedRiderId == null) return;
                        if (deliveryMethod == 'courier' && (courierNameCtrl.text.isEmpty || trackingIdCtrl.text.isEmpty)) return;

                        Map<String, dynamic> updateData = {
                          'status': 'Dispatched',
                          'delivery_type': deliveryMethod,
                          'dispatched_at': FieldValue.serverTimestamp(),
                        };

                        if (deliveryMethod == 'rider') {
                          updateData['assigned_rider_id'] = selectedRiderId;
                        } else { updateData['courier_name'] = courierNameCtrl.text.trim(); updateData['tracking_id'] = trackingIdCtrl.text.trim(); }

                        await FirebaseFirestore.instance.collection('orders').doc(orderId).update(updateData);

                        if (deliveryMethod == 'rider' && selectedRiderId != null) {
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'target_user_id': selectedRiderId,
                            'title': 'New Delivery Task 📦',
                            'message': 'Admin has FORCE ASSIGNED a parcel to you. Check your Active Tasks.',
                            'sent_at': FieldValue.serverTimestamp(),
                          });
                        }
                        
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Assigned Successfully! 🚀')));
                        }
                      }, 
                      child: const Text('CONFIRM DISPATCH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    )
                  ),
                  const SizedBox(height: 20),
                ]
              )
            );
          }
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));

        var allOrders = snapshot.hasData ? snapshot.data!.docs.toList() : <QueryDocumentSnapshot>[];
        allOrders.sort((a, b) {
          var tA = (a.data() as Map<String, dynamic>)['order_date'];
          var tB = (b.data() as Map<String, dynamic>)['order_date'];
          if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
          return 0;
        });
        
        var pendingOrders = allOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList();
        var processingOrders = allOrders.where((doc) =>['Processing', 'Ready to Ship'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
        var dispatchedOrders = allOrders.where((doc) =>['Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
        var doneOrders = allOrders.where((doc) =>['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            backgroundColor: Colors.grey.shade100,
            appBar: AppBar(
              backgroundColor: Colors.amber[100], 
              title: const Text('Logistics & Operations', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              bottom: TabBar(
                isScrollable: false, 
                labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs:[
                  _buildTabWithBadge('Pending', pendingOrders.length), 
                  _buildTabWithBadge('Process', processingOrders.length), 
                  _buildTabWithBadge('Transit', dispatchedOrders.length), 
                  const Tab(text: 'Done')
                ]
              ),
            ),
            body: TabBarView(
              children:[
                _buildOrderListView(pendingOrders),
                _buildOrderListView(processingOrders),
                _buildOrderListView(dispatchedOrders),
                _buildOrderListView(doneOrders),
              ],
            )
          ),
        );
      }
    );
  }

  Widget _buildOrderListView(List<QueryDocumentSnapshot> orders) {
    if (orders.isEmpty) return const Center(child: Text('এই সেকশনে কোনো অর্ডার নেই।', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(15), 
      itemCount: orders.length,
      itemBuilder: (context, index) {
        var doc = orders[index];
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        List<dynamic> items = data['items'] ??[];
        String firstItemName = items.isNotEmpty ? items[0]['product_name'] : 'Unknown Item';
        String itemSummary = items.length > 1 ? '$firstItemName ...(+${items.length - 1} more)' : firstItemName;
        String status = data['status'] ?? 'Pending';

        return Container(
          margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15), 
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text('ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)), Text('৳${data['total_amount']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16))]),
              
              const SizedBox(height: 8),
              Text('Placed: ${_formatTime(data['order_date'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (data['dispatched_at'] != null) Text('Dispatched: ${_formatTime(data['dispatched_at'])}', style: const TextStyle(fontSize: 11, color: Colors.teal)),
              if (data['delivered_at'] != null) Text('Delivered: ${_formatTime(data['delivered_at'])}', style: const TextStyle(fontSize: 11, color: Colors.green)),
              if (data['failed_at'] != null) Text('Failed: ${_formatTime(data['failed_at'])}', style: const TextStyle(fontSize: 11, color: Colors.red)),

              const Divider(height: 15),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.shopping_bag, color: Colors.blue)),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children:[
                        Text(itemSummary, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis), 
                        const SizedBox(height: 5),
                        Text('Customer: ${data['shipping_name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 12, color: Colors.black87)), 
                        if (data.containsKey('delivery_type')) ...[
                           const SizedBox(height: 5),
                           Text(data['delivery_type'] == 'rider' ? 'Assigned: Internal Rider' : 'Courier: ${data['courier_name']} (Trk: ${data['tracking_id']})', style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold))
                        ]
                      ]
                    )
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('Status: $status', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  Row(
                    children:[
                      OutlinedButton(
                        onPressed: () => _showOrderFullDetailsModal(data, doc.id),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, side: const BorderSide(color: Colors.teal), padding: const EdgeInsets.symmetric(horizontal: 10)),
                        child: const Text('Details', style: TextStyle(fontSize: 12, color: Colors.teal)),
                      ),
                      const SizedBox(width: 8),
                      _buildActionButton(context, doc.id, status, data, orders.length), // 🔴 context এবং length যোগ করা হলো
                    ],
                  )
                ],
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildActionButton(BuildContext context, String orderId, String status, Map<String, dynamic> orderData, int listLength) {
    if (status == 'Pending') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔴 Cancel Button (No Spinner, Instant Action)
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), visualDensity: VisualDensity.compact),
            onPressed: () {
              // ১. সাথে সাথে ডাটাবেস আপডেট (কোনো লোডিং ছাড়া)
              FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Cancelled'});
              
              // ২. ব্যাকগ্রাউন্ডে নোটিফিকেশন পাঠানো
              FirebaseFirestore.instance.collection('notifications').add({
                'target_user_id': orderData['user_id'],
                'title': 'Order Cancelled ❌',
                'message': 'দুঃখিত, কোনো বিশেষ কারণে আপনার অর্ডারটি বাতিল করা হয়েছে।',
                'sent_at': FieldValue.serverTimestamp(),
              });
              
              // ৩. সাথে সাথে মেসেজ দেখানো
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Cancelled!'), backgroundColor: Colors.red));
            },
            child: const Text('Cancel', style: TextStyle(fontSize: 12))
          ),
          const SizedBox(width: 8),
          
          // 🔵 Confirm Button
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, visualDensity: VisualDensity.compact), 
            onPressed: () async {
              await FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Processing', 'processing_at': FieldValue.serverTimestamp()});
              
              if (listLength <= 1) {
                DefaultTabController.of(context).animateTo(1); 
              }
              
              List<dynamic> items = orderData['items'] ?? [];
              Set<String> sellerIds = {};
              for(var item in items) {
                if(item['seller_id'] != null && item['seller_id'] != 'unknown') {
                  sellerIds.add(item['seller_id']);
                }
              }
              
              for(String sId in sellerIds) {
                await FirebaseFirestore.instance.collection('notifications').add({
                  'target_user_id': sId,
                  'title': 'New Order to Process 📦',
                  'message': 'অ্যাডমিন একটি অর্ডার কনফার্ম করেছেন (#${orderId.substring(0, 8).toUpperCase()})। দয়া করে প্যাক করুন।',
                  'sent_at': FieldValue.serverTimestamp(),
                  'data': {'screen': 'seller_orders'} 
                });
              }

              if (orderData['user_id'] != null) {
                await FirebaseFirestore.instance.collection('notifications').add({
                  'target_user_id': orderData['user_id'],
                  'title': 'Order Confirmed! ✅',
                  'message': 'আপনার অর্ডারটি অ্যাডমিন কনফার্ম করেছেন। সেলার এখন প্যাকিং শুরু করবেন।',
                  'sent_at': FieldValue.serverTimestamp(),
                  'data': {'screen': 'orders'} 
                });
              }
            }, 
            child: const Text('Confirm', style: TextStyle(color: Colors.white, fontSize: 12))
          )
        ],
      );
    } 
    else if (status == 'Processing') {
      return const Text('Wait for Seller', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11));
    }
    else if (status == 'Ready to Ship') {
      return ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, visualDensity: VisualDensity.compact), onPressed: () => _showAssignDeliveryModal(orderId), icon: const Icon(Icons.local_shipping, color: Colors.white, size: 14), label: const Text('Assign', style: TextStyle(color: Colors.white, fontSize: 12)));
    }
    else if (status == 'Dispatched' || status == 'In-Transit') {
      return const Text('Out for Delivery', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 11));
    }
    return const SizedBox();
  }
}

// ==========================================
// অ্যাডমিন পেজ ৪: Finance & Reports (Real-time Cash Flow, Payouts & Rider Settlement)
// ==========================================
class AdminFinanceReports extends StatefulWidget {
  const AdminFinanceReports({super.key});

  @override
  State<AdminFinanceReports> createState() => _AdminFinanceReportsState();
}

class _AdminFinanceReportsState extends State<AdminFinanceReports> {
  double platformCommissionRate = 0.10; // ১০% অ্যাডমিন কমিশন

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.amber.shade300, 
        title: const Text('Financial Oversight', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData) return const Center(child: Text('No financial data available.'));

          double totalDeliveredRevenue = 0; 
          double expectedPendingRevenue = 0; 
          int criticalCount = 0;
          int codCount = 0;
          int onlineCount = 0;

          // ১. সেলারদের মোট আর্নিং হিসাব করার ম্যাপ
          Map<String, double> sellerTotalEarnings = {};
          Map<String, double> sellerPendingEarnings = {}; // [NEW] পেন্ডিং হিসাবের জন্য
          
          // ২. রাইডারদের কাছে থাকা ক্যাশ হিসাব করার ম্যাপ
          Map<String, double> riderPendingCash = {};
          Map<String, List<String>> riderUnsettledOrderIds = {};

          for (var doc in snapshot.data!.docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String status = data['status'] ?? 'Pending';
            double amount = double.tryParse(data['total_amount'].toString()) ?? 0;
            String paymentMethod = data['payment_method'] ?? 'Cash on Delivery';

            if (status == 'Delivered') {
              totalDeliveredRevenue += amount;
              
              if (paymentMethod.contains('Cash') || paymentMethod == 'COD') {
                codCount++;
                // রাইডারের ক্যাশ সেটেলমেন্ট লজিক
                bool isRiderSettled = data['is_rider_settled'] ?? false;
                if (!isRiderSettled) {
                  String rId = data['assigned_rider_id'] ?? 'Unknown';
                  if (rId != 'Unknown') {
                    riderPendingCash[rId] = (riderPendingCash[rId] ?? 0) + amount;
                    if (riderUnsettledOrderIds[rId] == null) riderUnsettledOrderIds[rId] = [];
                    riderUnsettledOrderIds[rId]!.add(doc.id);
                  }
                }
              } else {
                onlineCount++;
              }

              // সেলারের মোট পাওনা হিসাব
              List<dynamic> items = data['items'] ?? [];
              for (var item in items) {
                String sId = item['seller_id'] ?? 'Unknown';
                if (sId != 'Unknown' && sId != 'unknown') {
                  double price = double.tryParse(item['price'].toString()) ?? 0;
                  int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                  double sellerCut = (price * qty) * (1 - platformCommissionRate);
                  sellerTotalEarnings[sId] = (sellerTotalEarnings[sId] ?? 0) + sellerCut;
                }
              }
            } else if (status != 'Cancelled') {
              expectedPendingRevenue += amount;
              criticalCount++; 
              
              // [NEW] সেলারের পেন্ডিং/প্রসেসিং এ থাকা টাকার হিসাব
              List<dynamic> items = data['items'] ?? [];
              for (var item in items) {
                String sId = item['seller_id'] ?? 'Unknown';
                if (sId != 'Unknown' && sId != 'unknown') {
                  double price = double.tryParse(item['price'].toString()) ?? 0;
                  int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                  double sellerCut = (price * qty) * (1 - platformCommissionRate);
                  sellerPendingEarnings[sId] = (sellerPendingEarnings[sId] ?? 0) + sellerCut;
                }
              }
            }
          }

          int totalPayments = codCount + onlineCount;
          double codPercentage = totalPayments > 0 ? (codCount / totalPayments) * 100 : 0;
          double onlinePercentage = totalPayments > 0 ? (onlineCount / totalPayments) * 100 : 0;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                // ১. Total Revenue Card
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(20), 
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors:[Colors.amber.shade200, Colors.amber.shade100]), 
                    borderRadius: BorderRadius.circular(15),
                    boxShadow:[BoxShadow(color: Colors.amber.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))]
                  ), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children: [
                      const Text('Total Successful Revenue', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), 
                      const SizedBox(height: 5),
                      Text('৳${totalDeliveredRevenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                      const Text('From all delivered orders', style: TextStyle(fontSize: 12, color: Colors.black54)), 
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity, 
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminProfitLossReportPage()));
                          }, 
                          icon: const Icon(Icons.analytics, color: Colors.white), 
                          label: const Text('VIEW MONTHLY P&L & SALARIES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                        ),
                      ),

                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity, 
                        height: 50,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.teal),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSettlementHistoryPage()));
                          }, 
                          icon: const Icon(Icons.receipt_long, color: Colors.teal), 
                          label: const Text('SETTLEMENT HISTORY & SLIPS', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold))
                        ),
                      ),
                    ]
                  )
                ),
                const SizedBox(height: 15),
                
                // ২. Expected Revenue
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(15), 
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.red.shade100)), 
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                    children:[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children:[
                          const Text('Expected Pipeline (Pending/Transit)', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)), 
                          Text('৳${expectedPendingRevenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red))
                        ]
                      ), 
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), 
                        child: Text('Active: $criticalCount', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))
                      )
                    ]
                  )
                ),
                const SizedBox(height: 25),
                
                // ৩. Rider Settlements (NEW SECTION)
                Row(
                  children: const [
                    Icon(Icons.motorcycle, color: Colors.teal),
                    SizedBox(width: 8),
                    Text('Rider Cash Collections (Pending)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 10),
                if (riderPendingCash.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('All rider cash settled.', style: TextStyle(color: Colors.grey))))
                else
                  ListView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
                    itemCount: riderPendingCash.keys.length, 
                    itemBuilder: (context, index) {
                      String rId = riderPendingCash.keys.elementAt(index);
                      double cashAmount = riderPendingCash[rId]!;
                      List<String> rOrderIds = riderUnsettledOrderIds[rId] ?? [];
                      
                      // নতুন স্পিনার কার্ড কল করা হচ্ছে
                      return RiderSettlementCard(
                        riderId: rId,
                        cashAmount: cashAmount,
                        orderIds: rOrderIds,
                      );
                    }
                  ),
                const SizedBox(height: 25),
                
                // ৪. Seller Payouts (FIXED SECTION)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Seller Payouts (Due)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('10% Platform Fee Applied', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 10),
                
                if (sellerTotalEarnings.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No delivered sales to settle yet.', style: TextStyle(color: Colors.grey))))
                else
                  ListView.builder(
                    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
                    itemCount: sellerTotalEarnings.keys.length, 
                    itemBuilder: (context, index) {
                      String sId = sellerTotalEarnings.keys.elementAt(index);
                      double totalEarned = sellerTotalEarnings[sId]!;
                      
                      // নতুন স্পিনার কার্ড এবং পেমেন্ট ডিটেইলস কালেকশন কার্ড
                      return SellerPayoutCard(
                        sellerId: sId,
                        totalEarned: totalEarned,
                        pendingEarned: sellerPendingEarnings[sId] ?? 0.0, // [NEW] পেন্ডিং ডাটা পাস করা হলো
                      );
                    }
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
// অ্যাডমিন পেজ ৫: System Settings & Admin (With Promo Control)
// ==========================================
class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});

  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _logAdminAction(String action, String details) async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    
    await FirebaseFirestore.instance.collection('security_logs').add({
      'admin_email': currentUser.email ?? 'Unknown Admin',
      'action': action,
      'details': details,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _uploadAdminProfilePicture() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (image == null || currentUser == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      String fileName = 'admin_profile_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child('profile_pictures').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();
      
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'profile_image_url': downloadUrl});
      await _logAdminAction('Profile Update', 'Admin updated their profile picture.');

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin profile picture updated! 🎉')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showAppConfigDialog() {
    TextEditingController commissionCtrl = TextEditingController();
    
    FirebaseFirestore.instance.collection('app_config').doc('finance_settings').get().then((doc) {
      if (doc.exists) commissionCtrl.text = (doc['platform_commission'] ?? 10).toString();
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('App Configuration'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            const Text('Set Platform Commission (%)', style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 5),
            TextField(controller: commissionCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'e.g. 10', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            const Text('*This % will be deducted from seller payouts.', style: TextStyle(fontSize: 10, color: Colors.deepOrange)),
          ],
        ),
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              String newVal = commissionCtrl.text.trim();
              await FirebaseFirestore.instance.collection('app_config').doc('finance_settings').set({
                'platform_commission': double.tryParse(newVal) ?? 10.0,
              }, SetOptions(merge: true));
              
              await _logAdminAction('Commission Update', 'Platform commission changed to $newVal%');

              if(mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commission Rate Updated Successfully!')));
            }, 
            child: const Text('Save', style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  // =====================================
  // [NEW] ফার্স্ট টাইম প্রোমো এবং জালিয়াতি রোধ কন্ট্রোলার
  // =====================================
  void _showPromoSettingsDialog() {
    TextEditingController discountCtrl = TextEditingController();
    bool isActive = false;

    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    FirebaseFirestore.instance.collection('app_config').doc('promos').get().then((doc) {
      Navigator.pop(context); 
      if (doc.exists) {
        discountCtrl.text = (doc['welcome_discount'] ?? 0).toString();
        isActive = doc['is_welcome_active'] ?? false;
      }
      
      showDialog(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Row(children:[Icon(Icons.local_offer, color: Colors.deepOrange), SizedBox(width: 8), Text('Welcome Promo')]),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  SwitchListTile(
                    title: const Text('Enable First-Time Discount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    value: isActive,
                    activeThumbColor: Colors.deepOrange,
                    onChanged: (val) => setDialogState(() => isActive = val),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: discountCtrl, 
                    keyboardType: TextInputType.number, 
                    enabled: isActive,
                    decoration: const InputDecoration(labelText: 'Discount Percentage (%)', hintText: 'e.g. 50', border: OutlineInputBorder(), isDense: true)
                  ),
                  const SizedBox(height: 10),
                  const Text('⚠️ Anti-Fraud System Active:\nএই ডিসকাউন্টটি শুধুমাত্র একজন ইউজারের প্রথম অর্ডারে কাজ করবে। আমাদের সিস্টেম ডিভাইস আইডি (Device MAC) ট্র্যাক করে, তাই নতুন সিম কিনে লগিন করলেও একই মোবাইল থেকে দ্বিতীয়বার অফার নেওয়া যাবে না!', style: TextStyle(fontSize: 10, color: Colors.grey)),
                ],
              ),
              actions:[
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                  onPressed: () async {
                    await FirebaseFirestore.instance.collection('app_config').doc('promos').set({
                      'is_welcome_active': isActive,
                      'welcome_discount': double.tryParse(discountCtrl.text.trim()) ?? 0.0,
                    }, SetOptions(merge: true));
                    
                    await _logAdminAction('Promo Update', 'Welcome Promo set to ${isActive ? 'ON (${discountCtrl.text}%)' : 'OFF'}');

                    if(mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Promo Settings Updated Successfully! 🎁')));
                  }, 
                  child: const Text('Save Settings', style: TextStyle(color: Colors.white))
                )
              ],
            );
          }
        )
      );
    });
  }

  void _showRoleManagementDialog() {
    TextEditingController emailCtrl = TextEditingController();
    String selectedRole = 'admin'; 

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Change User Role'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:[
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'User Email Address', border: OutlineInputBorder(), isDense: true)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Assign New Role', border: OutlineInputBorder(), isDense: true),
                  items:['super_admin', 'admin', 'seller', 'rider', 'customer'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
                  onChanged: (val) => setDialogState(() => selectedRole = val!),
                )
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: () async {
                  if(emailCtrl.text.isEmpty) return;
                  String targetEmail = emailCtrl.text.trim();
                  
                  var snap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: targetEmail).get();
                  if(snap.docs.isNotEmpty) {
                    await snap.docs.first.reference.update({'role': selectedRole});
                    await _logAdminAction('Role Change', 'Changed role of $targetEmail to $selectedRole');

                    if(mounted) Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Role updated to ${selectedRole.toUpperCase()} successfully!')));
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User not found with this email!')));
                  }
                }, 
                child: const Text('Update Role', style: TextStyle(color: Colors.white))
              )
            ],
          );
        }
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(backgroundColor: Colors.deepOrange, title: const Text('D Shop ADMIN', style: TextStyle(color: Colors.white)), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          children:[
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                
                var data = snapshot.hasData && snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : {};
                String name = data['name'] ?? 'Admin';
                String role = data['role'] ?? 'admin';
                String img = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';
                
                bool isSuperAdmin = role == 'super_admin';

                return Column(
                  children:[
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white), 
                      child: Column(
                        children:[
                          Stack(
                            alignment: Alignment.bottomRight,
                            children:[
                              CircleAvatar(
                                radius: 45, backgroundColor: Colors.deepPurple.shade50,
                                backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                                child: img.isEmpty ? const Icon(Icons.admin_panel_settings, size: 50, color: Colors.deepPurple) : null,
                              ),
                              InkWell(
                                onTap: _uploadAdminProfilePicture,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, color: Colors.white, size: 16)
                                ),
                              )
                            ],
                          ),
                          const SizedBox(height: 15), 
                          Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), 
                          Container(
                            margin: const EdgeInsets.only(top: 5),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSuperAdmin ? Colors.deepOrange.shade100 : Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(10)
                            ),
                            child: Text(isSuperAdmin ? 'SUPER ADMIN' : 'STAFF ADMIN', style: TextStyle(color: isSuperAdmin ? Colors.deepOrange : Colors.blue, fontSize: 10, fontWeight: FontWeight.bold)),
                          )
                        ]
                      )
                    ),
                    
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Text('Control Center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          
                          _buildSettingItem(Icons.store, 'Store Details', onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminStoreDetailsPage()));
                          }),
                          _buildSettingItem(Icons.people, 'Customer & Staff List', trailingText: 'View', onTap: () {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserStatusPage(role: 'admin', title: 'Staff & Admins')));
                          }),
                          
                          if (isSuperAdmin) ...[
                            const SizedBox(height: 20),
                            const Text('Super Admin Privileges', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            const SizedBox(height: 10),
                            
                            // [NEW] প্রোমো সেটিংস যুক্ত করা হলো
                            _buildSettingItem(Icons.local_offer, 'First-Time Promo Settings', trailingText: 'Setup', onTap: _showPromoSettingsDialog),
                            _buildSettingItem(Icons.admin_panel_settings, 'Global App Settings (COD)', trailingText: 'Live', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminGlobalSettingsPage()))),
                            
                            _buildSettingItem(Icons.settings_applications, 'App Config (Commission)', onTap: _showAppConfigDialog),
                            _buildSettingItem(Icons.admin_panel_settings, 'Role Management', onTap: _showRoleManagementDialog),
                            _buildSettingItem(Icons.security, 'Security Log', onTap: () {
                               Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSecurityLogPage()));
                            }),
                          ],
                          
                          if (!isSuperAdmin) ...[
                            const SizedBox(height: 20),
                            Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade100)),
                              child: Row(
                                children: const[
                                  Icon(Icons.lock, color: Colors.redAccent),
                                  SizedBox(width: 10),
                                  Expanded(child: Text('You are logged in as a Staff Admin. Some sensitive settings are hidden from your account.', style: TextStyle(color: Colors.redAccent, fontSize: 12))),
                                ],
                              ),
                            )
                          ],

                          const SizedBox(height: 30),
                          SizedBox(
                            width: double.infinity, 
                            child: TextButton.icon(
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
                              label: const Text('Log Out', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))
                            )
                          )
                        ],
                      ),
                    )
                  ],
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(IconData icon, String title, {String? trailingText, VoidCallback? onTap}) {
    return Card(
      elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: trailingText != null ? Text(trailingText, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)) : const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

// ==========================================
// নতুন পেজ ১: Admin Store Details Page (Global Platform Info)
// ==========================================
class AdminStoreDetailsPage extends StatefulWidget {
  const AdminStoreDetailsPage({super.key});

  @override
  State<AdminStoreDetailsPage> createState() => _AdminStoreDetailsPageState();
}

class _AdminStoreDetailsPageState extends State<AdminStoreDetailsPage> {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStoreDetails();
  }

  Future<void> _loadStoreDetails() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('app_config').doc('store_details').get();
      if (doc.exists) {
        var data = doc.data()!;
        nameCtrl.text = data['platform_name'] ?? 'D Shop';
        phoneCtrl.text = data['support_phone'] ?? '';
        emailCtrl.text = data['support_email'] ?? '';
        addressCtrl.text = data['office_address'] ?? '';
      }
    } catch (e) {}
    setState(() => isLoading = false);
  }

  Future<void> _saveStoreDetails() async {
    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('store_details').set({
        'platform_name': nameCtrl.text.trim(),
        'support_phone': phoneCtrl.text.trim(),
        'support_email': emailCtrl.text.trim(),
        'office_address': addressCtrl.text.trim(),
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store details saved successfully! ✅')));
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
      appBar: AppBar(title: const Text('Store Details'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Global Platform Information', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('These details will be visible to customers in their Support section.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 25),
                
                TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Platform Name', prefixIcon: Icon(Icons.store), border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'Support Phone Number', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: emailCtrl, decoration: const InputDecoration(labelText: 'Support Email', prefixIcon: Icon(Icons.email), border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: addressCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Physical Office Address', prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: _saveStoreDetails, 
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('SAVE DETAILS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                  )
                )
              ],
            ),
          )
    );
  }
}

// ==========================================
// নতুন পেজ ২: Admin Security Log Page (Tracks Staff Actions)
// ==========================================
class AdminSecurityLogPage extends StatelessWidget {
  const AdminSecurityLogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('System Security Logs'), backgroundColor: Colors.blueGrey, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        // লগের ডাটাবেস থেকে লেটেস্ট লগগুলো আগে আনবে (limit 50)
        stream: FirebaseFirestore.instance.collection('security_logs').orderBy('timestamp', descending: true).limit(50).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const[
                  Icon(Icons.verified_user, size: 80, color: Colors.grey),
                  SizedBox(height: 10),
                  Text('No security logs found. System is quiet.', style: TextStyle(color: Colors.grey))
                ],
              )
            );
          }

          var logs = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              var data = logs[index].data() as Map<String, dynamic>;
              
              String timeStr = 'Just now';
              if (data['timestamp'] != null) {
                DateTime dt = (data['timestamp'] as Timestamp).toDate();
                timeStr = '${dt.day}/${dt.month}/${dt.year} - ${dt.hour}:${dt.minute}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Colors.blueGrey.shade50, child: const Icon(Icons.admin_panel_settings, color: Colors.blueGrey)),
                  title: Text(data['action'] ?? 'Unknown Action', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Text(data['details'] ?? 'No details provided.', style: const TextStyle(color: Colors.black87, fontSize: 13)),
                      const SizedBox(height: 5),
                      Text('By: ${data['admin_email']} • $timeStr', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
              );
            }
          );
        },
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ: পুশ নোটিফিকেশন কন্ট্রোল
// ==========================================
class AdminNotificationPage extends StatefulWidget {
  const AdminNotificationPage({super.key});

  @override
  State<AdminNotificationPage> createState() => _AdminNotificationPageState();
}

class _AdminNotificationPageState extends State<AdminNotificationPage> {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController bodyController = TextEditingController();
  bool _isSending = false;

  // নোটিফিকেশন পাঠানোর ফাংশন (এটি ফায়ারবেস বা আপনার সার্ভার API কল করবে)
  Future<void> sendNotificationToAll() async {
    if (titleController.text.isEmpty || bodyController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('দয়া করে শিরোনাম এবং মেসেজ লিখুন!'))
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      // এখানে ফায়ারবেস স্টোরে একটি লগ রাখা হচ্ছে যেন ইউজাররা তাদের ইনবক্সেও দেখতে পায়
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': titleController.text.trim(),
        'message': bodyController.text.trim(),
        'sent_at': FieldValue.serverTimestamp(),
        'topic': 'all_users',  // 🔴 এটা আগের মতোই আছে
        'type': 'broadcast',
        'data': {  // 🔴 এই অংশ যোগ করুন
          'screen': 'home',
        }
      });

      // মনে রাখবেন: সরাসরি অ্যাপ থেকে অন্য ফোনে FCM পাঠাতে সার্ভার-সাইড কোড বা ফায়ারবেস ফাংশন প্রয়োজন।
      // বর্তমানে এটি ডাটাবেসে সেভ হচ্ছে।
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('নোটিফিকেশন সফলভাবে পাঠানো হয়েছে! 🚀'))
      );
      titleController.clear();
      bodyController.clear();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'))
      );
    } finally {
      setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Push Notification'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ব্রডকাস্ট মেসেজ পাঠান',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 5),
            const Text(
              'এই মেসেজটি সকল কাস্টমারদের মোবাইল স্ক্রিনে দেখা যাবে।',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: titleController,
              decoration: const InputDecoration(
                labelText: 'Notification Title',
                hintText: 'উদা: বিশাল ছাড়!',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: bodyController,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Message Body',
                hintText: 'সব পণ্যে ২০% ডিসকাউন্ট পেতে এখনই অর্ডার করুন...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                ),
                onPressed: _isSending ? null : sendNotificationToAll,
                icon: _isSending 
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.send, color: Colors.white),
                label: const Text(
                  'SEND NOTIFICATION',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ: রাইডার ম্যানেজমেন্ট (Approval & Status Control)
// ==========================================
class AdminManageRidersPage extends StatefulWidget {
  const AdminManageRidersPage({super.key});

  @override
  State<AdminManageRidersPage> createState() => _AdminManageRidersPageState();
}

class _AdminManageRidersPageState extends State<AdminManageRidersPage> {
  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Manage Riders'),
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // সার্চ বার (নাম বা ইমেইল দিয়ে রাইডার খোঁজার জন্য)
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: TextField(
              onChanged: (value) => setState(() => searchQuery = value.toLowerCase().trim()),
              decoration: InputDecoration(
                hintText: 'Search by name or email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // শুধুমাত্র যাদের রোল 'rider' তাদের ডাটাবেস থেকে আনা হচ্ছে
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'rider')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No riders registered yet.'));

                var riders = snapshot.data!.docs;

                // সার্চ ফিল্টার লজিক
                if (searchQuery.isNotEmpty) {
                  riders = riders.where((doc) {
                    String name = doc['name'].toString().toLowerCase();
                    String email = doc['email'].toString().toLowerCase();
                    return name.contains(searchQuery) || email.contains(searchQuery);
                  }).toList();
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: riders.length,
                  itemBuilder: (context, index) {
                    var riderDoc = riders[index];
                    Map<String, dynamic> data = riderDoc.data() as Map<String, dynamic>;
                    
                    bool isVerified = data.containsKey('is_verified') ? data['is_verified'] : false;
                    bool isOnline = data.containsKey('is_online') ? data['is_online'] : false;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOnline ? Colors.green.shade100 : Colors.grey.shade200,
                          child: Icon(Icons.motorcycle, color: isOnline ? Colors.green : Colors.grey),
                        ),
                        title: Text(data['name'] ?? 'Unknown Rider', style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(data['email'] ?? 'No email'),
                            const SizedBox(height: 5),
                            Row(
                              children: [
                                Icon(Icons.circle, size: 10, color: isOnline ? Colors.green : Colors.red),
                                const SizedBox(width: 5),
                                Text(isOnline ? 'Online' : 'Offline', style: TextStyle(fontSize: 12, color: isOnline ? Colors.green : Colors.red)),
                                const SizedBox(width: 15),
                                Icon(Icons.verified, size: 14, color: isVerified ? Colors.blue : Colors.grey),
                                const SizedBox(width: 4),
                                Text(isVerified ? 'Verified' : 'Pending Approval', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton(
                          onSelected: (value) async {
                            if (value == 'verify') {
                              await riderDoc.reference.update({'is_verified': !isVerified});
                            } else if (value == 'delete') {
                              await riderDoc.reference.delete();
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'verify',
                              child: Text(isVerified ? 'Unverify Rider' : 'Approve/Verify Rider'),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete Rider Account', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ: ডেলিভারি চার্জ সেটিং (Dynamic Distance Based)
// ==========================================
class AdminDeliveryZonePage extends StatefulWidget {
  const AdminDeliveryZonePage({super.key});

  @override
  State<AdminDeliveryZonePage> createState() => _AdminDeliveryZonePageState();
}

class _AdminDeliveryZonePageState extends State<AdminDeliveryZonePage> {
  // কন্ট্রোলারগুলো
  final TextEditingController baseDistanceCtrl = TextEditingController();
  final TextEditingController baseChargeCtrl = TextEditingController();
  final TextEditingController midDistanceCtrl = TextEditingController();
  final TextEditingController midChargeCtrl = TextEditingController();
  final TextEditingController extraPerKmCtrl = TextEditingController();

  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  // ফায়ারবেস থেকে বর্তমান সেটিংস লোড করা
  Future<void> _loadCurrentSettings() async {
    try {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        baseDistanceCtrl.text = data['base_distance'].toString();
        baseChargeCtrl.text = data['base_charge'].toString();
        midDistanceCtrl.text = data['mid_distance'].toString();
        midChargeCtrl.text = data['mid_charge'].toString();
        extraPerKmCtrl.text = data['extra_per_km'].toString();
      } else {
        // যদি ডাটাবেসে না থাকে, তবে ডিফল্ট কিছু ভ্যালু দিয়ে দেওয়া
        baseDistanceCtrl.text = '2';
        baseChargeCtrl.text = '30';
        midDistanceCtrl.text = '5';
        midChargeCtrl.text = '50';
        extraPerKmCtrl.text = '10';
      }
    } catch (e) {
      // Error handling
    }
    setState(() => isLoading = false);
  }

  // ফায়ারবেসে নতুন সেটিংস সেভ করা
  Future<void> _updateSettings() async {
    if (baseDistanceCtrl.text.isEmpty || baseChargeCtrl.text.isEmpty || extraPerKmCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সবগুলো ঘর পূরণ করুন!')));
      return;
    }

    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').set({
        'base_distance': double.parse(baseDistanceCtrl.text.trim()),
        'base_charge': int.parse(baseChargeCtrl.text.trim()),
        'mid_distance': double.parse(midDistanceCtrl.text.trim()),
        'mid_charge': int.parse(midChargeCtrl.text.trim()),
        'extra_per_km': int.parse(extraPerKmCtrl.text.trim()),
        'updated_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডেলিভারি চার্জ সফলভাবে আপডেট হয়েছে! 🎉')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Delivery Distance & Charges', style: TextStyle(fontSize: 16)), 
        backgroundColor: Colors.deepOrange, 
        foregroundColor: Colors.white
      ),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Set Distance Based Charges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('এখানে আপনি যে চার্জ সেট করবেন, কাস্টমারের কার্ট পেজে ম্যাপের দূরত্ব অনুযায়ী ঠিক সেই চার্জই অটোমেটিক হিসাব হবে।', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 25),

                // বেস চার্জ (প্রথম ধাপ)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('Level 1: Base Charge (কাছের জন্য)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                        const SizedBox(height: 15),
                        Row(
                          children:[
                            Expanded(child: TextField(controller: baseDistanceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Distance up to (KM)', border: OutlineInputBorder()))),
                            const SizedBox(width: 15),
                            Expanded(child: TextField(controller: baseChargeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Charge (৳)', border: OutlineInputBorder()))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // মিডিয়াম চার্জ (দ্বিতীয় ধাপ)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('Level 2: Mid Range Charge (একটু দূরের জন্য)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                        const SizedBox(height: 15),
                        Row(
                          children:[
                            Expanded(child: TextField(controller: midDistanceCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Distance up to (KM)', border: OutlineInputBorder()))),
                            const SizedBox(width: 15),
                            Expanded(child: TextField(controller: midChargeCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Charge (৳)', border: OutlineInputBorder()))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 15),

                // এক্সট্রা চার্জ (অনেক দূরের জন্য)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('Level 3: Extra Distance (অনেক দূরের জন্য)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                        const SizedBox(height: 15),
                        TextField(
                          controller: extraPerKmCtrl, 
                          keyboardType: TextInputType.number, 
                          decoration: const InputDecoration(labelText: 'Extra charge per KM (৳)', border: OutlineInputBorder(), helperText: 'উদাহরণ: ৫ কি.মি. এর বেশি হলে প্রতি কিলোমিটারের জন্য কত টাকা যোগ হবে?')
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 30),

                // সেভ বাটন
                SizedBox(
                  width: double.infinity, height: 55,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: _updateSettings,
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('UPDATE DELIVERY CHARGES', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
    );
  }
}


// ==========================================
// অ্যাডমিন পেজ: Monthly Profit & Loss (Ledger & Tax PDF Generator)
// ==========================================
class AdminProfitLossReportPage extends StatefulWidget {
  const AdminProfitLossReportPage({super.key});

  @override
  State<AdminProfitLossReportPage> createState() => _AdminProfitLossReportPageState();
}

class _AdminProfitLossReportPageState extends State<AdminProfitLossReportPage> {
  final TextEditingController amountCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  String selectedCategory = 'Staff Salary';
  double platformCommissionRate = 0.10; 

  // [NEW] মাস ও বছর ফিল্টার করার জন্য ভেরিয়েবল
  int selectedMonth = DateTime.now().month;
  int selectedYear = DateTime.now().year;
  
  final List<String> monthNames =['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

  @override
  void initState() {
    super.initState();
    _fetchCommissionRate();
  }

  Future<void> _fetchCommissionRate() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('app_config').doc('finance_settings').get();
      if (doc.exists) {
        setState(() {
          platformCommissionRate = ((doc.data()?['platform_commission'] ?? 10) as num).toDouble() / 100;
        });
      }
    } catch (e) {}
  }

  void _addExpense() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Add Expense / Salary'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children:[
                DropdownButtonFormField<String>(
                  initialValue: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Expense Category', border: OutlineInputBorder(), isDense: true),
                  items:['Staff Salary', 'Rider Payment', 'Server/API Cost', 'Marketing', 'Office Rent', 'Others']
                      .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (val) => setDialogState(() => selectedCategory = val!),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount (৳)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 15),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Description (e.g. Rahim Salary)', border: OutlineInputBorder(), isDense: true),
                ),
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  if (amountCtrl.text.isEmpty || descCtrl.text.isEmpty) return;
                  
                  await FirebaseFirestore.instance.collection('expenses').add({
                    'category': selectedCategory,
                    'amount': double.parse(amountCtrl.text.trim()),
                    'description': descCtrl.text.trim(),
                    'date': FieldValue.serverTimestamp(),
                  });
                  
                  amountCtrl.clear(); descCtrl.clear();
                  if (mounted) Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Expense Added Successfully!')));
                },
                child: const Text('Add Expense', style: TextStyle(color: Colors.white)),
              )
            ],
          );
        }
      )
    );
  }

  // =====================================
  // [NEW] PDF Ledger Generator (For Tax & Audit)
  // =====================================
  Future<void> _generateLedgerPDF(double totalIncome, double totalExpense, double netProfit, List<Map<String, dynamic>> expensesList) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children:[
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children:[
                  pw.Text('D Shop', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)),
                  pw.Text('FINANCIAL LEDGER', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey)),
                ]
              ),
              pw.SizedBox(height: 10),
              pw.Text('Statement for: ${monthNames[selectedMonth - 1]} $selectedYear', style: const pw.TextStyle(fontSize: 14)),
              pw.Text('Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'),
              pw.SizedBox(height: 30),
              
              // Summary Box
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(color: PdfColors.grey100, border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children:[
                    pw.Column(children:[pw.Text('Total Income', style: const pw.TextStyle(color: PdfColors.grey700)), pw.Text('Tk ${totalIncome.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.green))]),
                    pw.Column(children:[pw.Text('Total Expense', style: const pw.TextStyle(color: PdfColors.grey700)), pw.Text('Tk ${totalExpense.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.red))]),
                    pw.Column(children:[pw.Text('NET PROFIT/LOSS', style: const pw.TextStyle(color: PdfColors.grey700)), pw.Text('Tk ${netProfit.toStringAsFixed(2)}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: netProfit >= 0 ? PdfColors.teal : PdfColors.red))]),
                  ]
                )
              ),
              pw.SizedBox(height: 30),
              
              pw.Text('Expense Breakdown', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              
              // Expense Table
              if (expensesList.isNotEmpty)
                pw.Table.fromTextArray(
                  headers:['Date', 'Category', 'Description', 'Amount'],
                  data: expensesList.map((item) {
                    return[
                      item['date'],
                      item['category'],
                      item['description'],
                      'Tk ${item['amount']}'
                    ];
                  }).toList(),
                  headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey),
                  cellAlignment: pw.Alignment.centerLeft,
                )
              else
                pw.Text('No expenses recorded for this month.', style: const pw.TextStyle(color: PdfColors.grey)),
                
              pw.Spacer(),
              pw.Divider(),
              pw.Center(child: pw.Text('This is a system generated financial document for tax and audit purposes.', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey)))
            ]
          );
        }
      )
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'DShop_Ledger_${monthNames[selectedMonth - 1]}_$selectedYear.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Monthly Ledger & P&L'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: Column(
        children: [
          // [NEW] Month & Year Picker
          Container(
            padding: const EdgeInsets.all(15),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:[
                const Icon(Icons.calendar_month, color: Colors.teal),
                const SizedBox(width: 10),
                DropdownButton<int>(
                  value: selectedMonth,
                  items: List.generate(12, (index) => DropdownMenuItem(value: index + 1, child: Text(monthNames[index]))),
                  onChanged: (val) => setState(() => selectedMonth = val!),
                ),
                const SizedBox(width: 20),
                DropdownButton<int>(
                  value: selectedYear,
                  items:[2024, 2025, 2026, 2027, 2028].map((y) => DropdownMenuItem(value: y, child: Text(y.toString()))).toList(),
                  onChanged: (val) => setState(() => selectedYear = val!),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, orderSnapshot) {
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('expenses').snapshots(),
                  builder: (context, expenseSnapshot) {
                    
                    if (orderSnapshot.connectionState == ConnectionState.waiting || expenseSnapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    double totalIncome = 0; 
                    double totalExpense = 0; 

                    if (orderSnapshot.hasData) {
                      for (var doc in orderSnapshot.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        if (data['status'] == 'Delivered' && data['order_date'] != null) {
                          DateTime orderDate = (data['order_date'] as Timestamp).toDate();
                          
                          //[NEW] ফিল্টার করা মাস ও বছর অনুযায়ী ইনকাম হিসাব
                          if (orderDate.month == selectedMonth && orderDate.year == selectedYear) {
                            List<dynamic> items = data['items'] ??[];
                            for (var item in items) {
                              double price = double.tryParse(item['price'].toString()) ?? 0;
                              int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                              totalIncome += (price * qty) * platformCommissionRate; 
                            }
                          }
                        }
                      }
                    }

                    List<Map<String, dynamic>> thisMonthExpenses =[];
                    if (expenseSnapshot.hasData) {
                      for (var doc in expenseSnapshot.data!.docs) {
                        var data = doc.data() as Map<String, dynamic>;
                        if (data['date'] != null) {
                          DateTime expDate = (data['date'] as Timestamp).toDate();
                          
                          //[NEW] ফিল্টার করা মাস ও বছর অনুযায়ী খরচ হিসাব
                          if (expDate.month == selectedMonth && expDate.year == selectedYear) {
                            double amt = (data['amount'] as num).toDouble();
                            totalExpense += amt;
                            thisMonthExpenses.add({
                              'date': '${expDate.day}/${expDate.month}/${expDate.year}',
                              'category': data['category'],
                              'description': data['description'],
                              'amount': amt.toStringAsFixed(0)
                            });
                          }
                        }
                      }
                    }

                    double netProfit = totalIncome - totalExpense;

                    return ListView(
                      padding: const EdgeInsets.all(15),
                      children:[
                        Row(
                          children:[
                            _buildSummaryCard('Total Income', totalIncome, Colors.green),
                            const SizedBox(width: 10),
                            _buildSummaryCard('Total Expenses', totalExpense, Colors.red),
                          ],
                        ),
                        const SizedBox(height: 15),
                        Container(
                          width: double.infinity, padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: netProfit >= 0 ? Colors.teal.shade800 : Colors.red.shade800,
                            borderRadius: BorderRadius.circular(15)
                          ),
                          child: Column(
                            children:[
                              const Text('NET PROFIT / LOSS', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 5),
                              Text('৳${netProfit.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 15),

                        // [NEW] PDF Download Button
                        SizedBox(
                          width: double.infinity, height: 45,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal)),
                            onPressed: () => _generateLedgerPDF(totalIncome, totalExpense, netProfit, thisMonthExpenses), 
                            icon: const Icon(Icons.picture_as_pdf), 
                            label: const Text('DOWNLOAD TAX LEDGER (PDF)', style: TextStyle(fontWeight: FontWeight.bold))
                          ),
                        ),
                        
                        const SizedBox(height: 30),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children:[
                            const Text('Expense History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              onPressed: _addExpense, 
                              icon: const Icon(Icons.add, color: Colors.white, size: 16),
                              label: const Text('Add', style: TextStyle(color: Colors.white))
                            )
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (thisMonthExpenses.isEmpty)
                          const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No expenses recorded for this month.', style: TextStyle(color: Colors.grey))))
                        else
                          ...thisMonthExpenses.map((item) {
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.money_off, color: Colors.white)),
                                title: Text(item['description'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('${item['category']} • ${item['date']}', style: const TextStyle(fontSize: 12)),
                                trailing: Text('- ৳${item['amount']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                              ),
                            );
                          })
                      ],
                    );
                  }
                );
              }
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: color.withOpacity(0.3))),
        child: Column(
          children:[
            Text(title, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            Text('৳${amount.toStringAsFixed(0)}', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// Admin Manage Categories Page (With Edit & Subcategory Images)
// ==========================================
class AdminManageCategoriesPage extends StatefulWidget {
  const AdminManageCategoriesPage({super.key});

  @override
  State<AdminManageCategoriesPage> createState() => _AdminManageCategoriesPageState();
}

class _AdminManageCategoriesPageState extends State<AdminManageCategoriesPage> {
  final TextEditingController categoryNameController = TextEditingController();
  final TextEditingController subCategoryController = TextEditingController();
  
  final ImagePicker _picker = ImagePicker();
  
  // মেইন ক্যাটাগরির জন্য
  XFile? selectedMainImage;
  String? existingMainImageUrl;
  
  // এডিট মোড ট্র্যাক করার জন্য
  String? editingCategoryId; 

  // সাব-ক্যাটাগরির লিস্ট (নাম এবং ছবির ডাটা থাকবে)
  List<Map<String, dynamic>> subcategories =[]; 

  // মেইন ক্যাটাগরির ছবি পিক করা
  Future<void> pickMainImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) setState(() => selectedMainImage = image);
  }

  // সাব-ক্যাটাগরির ছবি পিক করা
  Future<void> pickSubImage(int index) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      setState(() {
        subcategories[index]['image_file'] = image;
      });
    }
  }

  // ফর্ম রিসেট করা
  void resetForm() {
    setState(() {
      editingCategoryId = null;
      categoryNameController.clear();
      subCategoryController.clear();
      selectedMainImage = null;
      existingMainImageUrl = null;
      subcategories.clear();
    });
  }

  // সেভ বা আপডেট করার মূল ফাংশন
  Future<void> saveCategory() async {
    if (categoryNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter category name!')));
      return;
    }
    if (selectedMainImage == null && existingMainImageUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a main image!')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      // ১. মেইন ছবি আপলোড (যদি নতুন সিলেক্ট করে)
      String mainImageUrl = existingMainImageUrl ?? '';
      if (selectedMainImage != null) {
        String fileName = 'cat_main_${DateTime.now().millisecondsSinceEpoch}.jpg';
        Reference ref = FirebaseStorage.instance.ref().child('category_images').child(fileName);
        if (kIsWeb) {
          await ref.putData(await selectedMainImage!.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(selectedMainImage!.path));
        }
        mainImageUrl = await ref.getDownloadURL();
      }

      // ২. সাব-ক্যাটাগরির ছবিগুলো আপলোড করা
      List<Map<String, dynamic>> finalSubcategories = [];
      for (var sub in subcategories) {
        String subImageUrl = sub['image_url'] ?? '';
        if (sub['image_file'] != null) {
          String subFileName = 'subcat_${DateTime.now().millisecondsSinceEpoch}_${sub['name']}.jpg';
          Reference subRef = FirebaseStorage.instance.ref().child('category_images/subs').child(subFileName);
          if (kIsWeb) {
            await subRef.putData(await (sub['image_file'] as XFile).readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
          } else {
            await subRef.putFile(File((sub['image_file'] as XFile).path));
          }
          subImageUrl = await subRef.getDownloadURL();
        }
        
        finalSubcategories.add({
          'name': sub['name'],
          'image_url': subImageUrl,
        });
      }

      // ৩. ডাটাবেসে সেভ অথবা আপডেট করা
      Map<String, dynamic> categoryData = {
        'name': categoryNameController.text.trim(),
        'image_url': mainImageUrl,
        'subcategories': finalSubcategories,
        'updated_at': FieldValue.serverTimestamp(),
      };

      if (editingCategoryId != null) {
        // Update Existing
        await FirebaseFirestore.instance.collection('categories').doc(editingCategoryId).update(categoryData);
      } else {
        // Create New
        categoryData['created_at'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('categories').add(categoryData);
      }

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      resetForm();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(editingCategoryId != null ? 'Category Updated Successfully! ✅' : 'Category Added Successfully! 🎉'), backgroundColor: Colors.green));
    } catch (e) {
      if(mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('Manage Categories'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children:[
          // ফর্ম সেকশন
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    Text(editingCategoryId != null ? 'Edit Category' : 'Add New Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: editingCategoryId != null ? Colors.blue : Colors.black)),
                    if (editingCategoryId != null)
                      TextButton.icon(onPressed: resetForm, icon: const Icon(Icons.cancel, size: 16, color: Colors.red), label: const Text('Cancel Edit', style: TextStyle(color: Colors.red)))
                  ],
                ),
                const SizedBox(height: 10),
                
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    InkWell(
                      onTap: pickMainImage,
                      child: Container(
                        height: 60, width: 60,
                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.deepOrange)),
                        child: selectedMainImage != null 
                            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: kIsWeb ? Image.network(selectedMainImage!.path, fit: BoxFit.cover) : Image.file(File(selectedMainImage!.path), fit: BoxFit.cover))
                            : (existingMainImageUrl != null 
                                ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(existingMainImageUrl!, fit: BoxFit.cover))
                                : const Icon(Icons.add_photo_alternate, color: Colors.deepOrange)),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        children:[
                          TextField(
                            controller: categoryNameController,
                            decoration: const InputDecoration(labelText: 'Main Category (e.g. Mobiles)', border: OutlineInputBorder(), isDense: true),
                          ),
                          const SizedBox(height: 10),
                          
                          Row(
                            children:[
                              Expanded(
                                child: TextField(
                                  controller: subCategoryController,
                                  decoration: const InputDecoration(labelText: 'Subcategory (e.g. Vivo)', border: OutlineInputBorder(), isDense: true, hintText: 'Type & Add'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                                onPressed: () {
                                  if (subCategoryController.text.trim().isNotEmpty) {
                                    setState(() {
                                      subcategories.add({
                                        'name': subCategoryController.text.trim(),
                                        'image_file': null,
                                        'image_url': null
                                      });
                                      subCategoryController.clear();
                                    });
                                  }
                                },
                                child: const Text('Add', style: TextStyle(color: Colors.white)),
                              )
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                
                // সাব-ক্যাটাগরির ছবি ও লিস্ট দেখানোর জায়গা
                if (subcategories.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 15),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blueGrey.shade100)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Text('Subcategories (Click icon to add image):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 10, runSpacing: 10,
                            children: subcategories.asMap().entries.map((entry) {
                              int idx = entry.key;
                              var sub = entry.value;
                              return Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children:[
                                    InkWell(
                                      onTap: () => pickSubImage(idx),
                                      child: Container(
                                        width: 35, height: 35,
                                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5)),
                                        child: sub['image_file'] != null 
                                            ? ClipRRect(borderRadius: BorderRadius.circular(5), child: kIsWeb ? Image.network(sub['image_file'].path, fit: BoxFit.cover) : Image.file(File(sub['image_file'].path), fit: BoxFit.cover))
                                            : (sub['image_url'] != null 
                                                ? ClipRRect(borderRadius: BorderRadius.circular(5), child: Image.network(sub['image_url'], fit: BoxFit.cover))
                                                : const Icon(Icons.add_a_photo, size: 16, color: Colors.grey)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(sub['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    const SizedBox(width: 5),
                                    InkWell(onTap: () => setState(() => subcategories.removeAt(idx)), child: const Icon(Icons.cancel, color: Colors.red, size: 16))
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ),

                const SizedBox(height: 15),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: editingCategoryId != null ? Colors.blue : Colors.teal, padding: const EdgeInsets.symmetric(vertical: 12)),
                    onPressed: saveCategory,
                    child: Text(editingCategoryId != null ? 'UPDATE CATEGORY' : 'SAVE NEW CATEGORY', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                )
              ],
            ),
          ),
          
          const SizedBox(height: 10),
          const Padding(padding: EdgeInsets.all(15.0), child: Align(alignment: Alignment.centerLeft, child: Text('Existing Categories (Click to Edit)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)))),
          
          // ডাটাবেস থেকে রিয়েল-টাইম ক্যাটাগরি লিস্ট
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('categories').orderBy('created_at', descending: true).snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No categories found. Add some!'));

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var doc = snapshot.data!.docs[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    List<dynamic> subcats = data['subcategories'] ??[];

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: editingCategoryId == doc.id ? Colors.blue : Colors.transparent, width: 2)),
                      child: ListTile(
                        onTap: () {
                          // [NEW] এডিট করার জন্য ডাটা উপরে ফর্মে নিয়ে যাওয়া
                          setState(() {
                            editingCategoryId = doc.id;
                            categoryNameController.text = data['name'];
                            existingMainImageUrl = data['image_url'];
                            selectedMainImage = null;
                            // সাব-ক্যাটাগরিগুলো লোড করা
                            subcategories = List<Map<String, dynamic>>.from(subcats.map((e) => {
                              'name': e['name'],
                              'image_url': e['image_url'],
                              'image_file': null
                            }));
                          });
                        },
                        leading: CircleAvatar(backgroundColor: Colors.grey.shade100, backgroundImage: NetworkImage(data['image_url'])),
                        title: Text(data['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text('${subcats.length} subcategories', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => doc.reference.delete()),
                      ),
                    );
                  }
                );
              }
            ),
          )
        ],
      ),
    );
  }
}


// ==========================================
// উন্নত ব্যানার ম্যানেজমেন্ট পেজ (Multi-upload & Toggle Status)
// ==========================================
class AdminBannerManagementPage extends StatefulWidget {
  const AdminBannerManagementPage({super.key});

  @override
  State<AdminBannerManagementPage> createState() => _AdminBannerManagementPageState();
}

class _AdminBannerManagementPageState extends State<AdminBannerManagementPage> {
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

  // একসাথে একাধিক ব্যানার আপলোড করার ফাংশন
  Future<void> uploadMultipleBanners() async {
    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1080);// একাধিক ছবি সিলেক্ট 
    if (images.isEmpty) return;

    setState(() => _isUploading = true);

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      for (var image in images) {
        String fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child('banners').child(fileName);
        
        // Web এবং Mobile সাপোর্ট [cite: 367, 368]
        if (kIsWeb) {
          Uint8List bytes = await image.readAsBytes();
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
        } else {
          await ref.putFile(File(image.path));
        }
        
        String downloadUrl = await ref.getDownloadURL();

        // ডাটাবেসে সেভ (isActive: true ডিফল্ট) [cite: 693]
        await FirebaseFirestore.instance.collection('banners').add({
          'image_url': downloadUrl,
          'uploaded_at': FieldValue.serverTimestamp(),
          'isActive': true, 
        });
      }

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ব্যানারগুলো সফলভাবে আপলোড হয়েছে! 🎉')));
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Banners'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children: [
          // 🔴 নতুন: Default Background Banner Upload & Delete Section
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('app_config').doc('default_banner').snapshots(),
            builder: (context, snapshot) {
              bool hasBanner = false;
              if (snapshot.hasData && snapshot.data!.exists) {
                var data = snapshot.data!.data() as Map<String, dynamic>?;
                if (data != null && data['image_url'] != null && data['image_url'].toString().isNotEmpty) {
                  hasBanner = true;
                }
              }

              return Container(
                color: Colors.white,
                padding: const EdgeInsets.all(15),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.wallpaper, color: Colors.deepOrange),
                  ),
                  title: const Text('Set Default Background', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: const Text('ব্যানার লোড হতে দেরি হলে এই ছবিটি কাস্টমার দেখতে পাবে।', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasBanner)
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          tooltip: 'Remove Background',
                          onPressed: () async {
                            await FirebaseFirestore.instance.collection('app_config').doc('default_banner').delete();
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Background Removed!')));
                          }
                        ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange), foregroundColor: Colors.deepOrange),
                        onPressed: () async {
                          final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                          if (image == null) return;
                          
                          showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
                          
                          String fileName = 'default_banner_bg.jpg';
                          Reference ref = FirebaseStorage.instance.ref().child('banners').child(fileName);
                          if (kIsWeb) {
                            await ref.putData(await image.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
                          } else {
                            await ref.putFile(File(image.path));
                          }
                          
                          String downloadUrl = await ref.getDownloadURL();
                          await FirebaseFirestore.instance.collection('app_config').doc('default_banner').set({
                            'image_url': downloadUrl,
                            'updated_at': FieldValue.serverTimestamp()
                          });
                          
                          if(context.mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Background Image Updated!'), backgroundColor: Colors.green));
                          }
                        }, 
                        child: const Text('Upload')
                      ),
                    ],
                  ),
                ),
              );
            }
          ),
          const Divider(height: 1, thickness: 3, color: Color(0xFFEEEEEE)),

          Padding(
            padding: const EdgeInsets.all(15.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, minimumSize: const Size(double.infinity, 50)),
              onPressed: _isUploading ? null : uploadMultipleBanners, 
              icon: const Icon(Icons.add_photo_alternate, color: Colors.white), 
              label: const Text('Add Multiple Banners', style: TextStyle(color: Colors.white, fontSize: 16))
            ),
          ),
          const Expanded(child: BannerListWithToggle()),
        ],
      ),
    );
  }
}

class BannerListWithToggle extends StatelessWidget {
  const BannerListWithToggle({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('banners').orderBy('uploaded_at', descending: true).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        if (snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো ব্যানার নেই।'));

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            bool isActive = data.containsKey('isActive') ? data['isActive'] : true;

            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              child: Column(
                children: [
                  Container(
                    height: 150, width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      image: DecorationImage(
                        image: NetworkImage(doc['image_url']), 
                        fit: BoxFit.cover,
                        colorFilter: isActive ? null : ColorFilter.mode(Colors.black.withOpacity(0.5), BlendMode.darken)
                      )
                    ),
                    child: isActive ? null : const Center(child: Text('DISABLED', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                  ),
                  ListTile(
                    title: Text(isActive ? "Active" : "Disabled", style: TextStyle(color: isActive ? Colors.green : Colors.red)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: isActive, 
                          activeThumbColor: Colors.teal,
                          onChanged: (val) => doc.reference.update({'isActive': val}) // স্ট্যাটাস এডিট
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => doc.reference.delete() // ডিলিট [cite: 702]
                        ),
                      ],
                    ),
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }
}

class BannerList extends StatelessWidget {
  const BannerList({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: FirebaseFirestore.instance.collection('banners').orderBy('uploaded_at', descending: true).snapshots(),
      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No banners uploaded yet.'));

        return ListView.builder(
          padding: const EdgeInsets.all(15),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 15),
              child: Column(
                children:[
                  Container(
                    height: 150, width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      image: DecorationImage(image: NetworkImage(doc['image_url']), fit: BoxFit.cover)
                    ),
                  ),
                  Container(
                    color: Colors.grey.shade100,
                    child: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        FirebaseFirestore.instance.collection('banners').doc(doc.id).delete();
                      },
                    ),
                  )
                ],
              ),
            );
          },
        );
      }
    );
  }
}


// ==========================================
//[NEW] অ্যাডমিন পেজ: Global App Settings (Dynamic Control)
// ==========================================
class AdminGlobalSettingsPage extends StatefulWidget {
  const AdminGlobalSettingsPage({super.key});

  @override
  State<AdminGlobalSettingsPage> createState() => _AdminGlobalSettingsPageState();
}

class _AdminGlobalSettingsPageState extends State<AdminGlobalSettingsPage> {
  bool isCodEnabled = true;
  bool isAppUnderMaintenance = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGlobalSettings();
  }

  Future<void> _loadGlobalSettings() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('app_config').doc('global_settings').get();
      if (doc.exists) {
        setState(() {
          isCodEnabled = doc['enable_cod'] ?? true;
          isAppUnderMaintenance = doc['maintenance_mode'] ?? false;
        });
      }
    } catch (e) {}
    setState(() => isLoading = false);
  }

  Future<void> _updateSettings(String key, bool value) async {
    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('app_config').doc('global_settings').set({
        key: value,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings Updated Instantly! ⚡'), backgroundColor: Colors.green));
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
    _loadGlobalSettings();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Global App Settings'), backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children:[
                const Text('Real-time Dynamic Controls', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('এখান থেকে কোনো সেটিং পরিবর্তন করলে সাথে সাথে সকল ইউজারের অ্যাপে সেটি কাজ করা শুরু করবে। কোনো অ্যাপ আপডেটের প্রয়োজন নেই!', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 25),

                // 1. Global COD Control
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isCodEnabled ? Colors.teal : Colors.red)),
                  child: SwitchListTile(
                    title: const Text('Enable Cash on Delivery (COD)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(isCodEnabled ? 'বর্তমানে সবার জন্য COD চালু আছে।' : 'খারাপ আবহাওয়া বা অন্য কারণে COD বন্ধ রাখা হয়েছে। কাস্টমার শুধু ডিজিটাল পেমেন্ট করতে পারবে।', style: const TextStyle(fontSize: 11)),
                    value: isCodEnabled,
                    activeThumbColor: Colors.teal,
                    onChanged: (val) => _updateSettings('enable_cod', val),
                  ),
                ),
                const SizedBox(height: 15),

                // 2. Maintenance Mode
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: isAppUnderMaintenance ? Colors.red : Colors.grey.shade300)),
                  child: SwitchListTile(
                    title: const Text('Maintenance Mode (Server Down)', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(isAppUnderMaintenance ? 'অ্যাপ এখন মেইনটেন্যান্সে আছে। কেউ অর্ডার করতে পারবে না।' : 'অ্যাপ স্বাভাবিকভাবে চলছে।', style: const TextStyle(fontSize: 11)),
                    value: isAppUnderMaintenance,
                    activeThumbColor: Colors.red,
                    onChanged: (val) => _updateSettings('maintenance_mode', val),
                  ),
                ),
              ],
            ),
    );
  }
}

class AdminNotificationTester extends StatelessWidget {
  const AdminNotificationTester({super.key});

  Future<void> sendTest(String title, String msg, String role) async {
    String topicName = 'all_users';
    if (role == 'rider') topicName = 'riders';
    if (role == 'seller') topicName = 'sellers'; // সেলারের জন্য 'sellers'

    await FirebaseFirestore.instance.collection('notifications').add({
      'title': title,
      'message': msg,
      'topic': topicName, // ডাটাবেসে topic ফিল্ডটি সেভ হবে
      'sent_at': FieldValue.serverTimestamp(),
      'data': {
        'screen': role == 'rider' ? 'rider_dashboard' : 'notifications',
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notification Tester'), backgroundColor: Colors.redAccent),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Text('নিচের বাটনগুলো ক্লিক করে চেক করুন কোন ফোনে নোটিফিকেশন কেমন আসে।', 
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),
            
            // কাস্টমারদের জন্য টেস্ট
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: const Size(double.infinity, 50)),
              icon: const Icon(Icons.people, color: Colors.white),
              label: const Text('Test Customer (Broadcast)'),
              onPressed: () => sendTest('বিশাল অফার!', 'সব পণ্যে ৫০% ছাড়। এখনই কিনুন!', 'customer'),
            ),
            const SizedBox(height: 15),

            // সেলারদের জন্য টেস্ট
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, minimumSize: const Size(double.infinity, 50)),
              icon: const Icon(Icons.store, color: Colors.white),
              label: const Text('Test Seller Notification'),
              onPressed: () => sendTest('অর্ডার আপডেট', 'আপনার দোকানে ১টি নতুন অর্ডার এসেছে।', 'seller'),
            ),
            const SizedBox(height: 15),

            // রাইডারদের জন্য রিংটোন টেস্ট
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, minimumSize: const Size(double.infinity, 50)),
              icon: const Icon(Icons.motorcycle, color: Colors.white),
              label: const Text('Test Rider Job (RINGING SOUND)'),
              onPressed: () => sendTest('🚨 নতুন জব রিকোয়েস্ট!', 'একটি পার্সেল ডেলিভারি করতে হবে। দ্রুত এক্সেপ্ট করুন।', 'rider'),
            ),
            
            const Spacer(),
            const Text('নোট: টেস্টিং শেষ হলে এই পেজটি রিমুভ করে দেবেন।', 
              style: TextStyle(fontSize: 11, color: Colors.red)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// [NEW] Rider Settlement Card (Inline Loading Fix)
// ==========================================
class RiderSettlementCard extends StatefulWidget {
  final String riderId;
  final double cashAmount;
  final List<String> orderIds;

  const RiderSettlementCard({
    super.key,
    required this.riderId,
    required this.cashAmount,
    required this.orderIds,
  });

  @override
  State<RiderSettlementCard> createState() => _RiderSettlementCardState();
}

class _RiderSettlementCardState extends State<RiderSettlementCard> {
  bool _isProcessing = false;

  Future<void> _receiveCash() async {
    setState(() => _isProcessing = true);

    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      
      // ফায়ারবেস ব্যাচ লিমিট (৫০০) হ্যান্ডেল করার লজিক
      int count = 0;
      for (String oId in widget.orderIds) {
        batch.update(FirebaseFirestore.instance.collection('orders').doc(oId), {'is_rider_settled': true});
        count++;
        if (count == 490) {
          await batch.commit();
          batch = FirebaseFirestore.instance.batch();
          count = 0;
        }
      }
      if (count > 0) {
        await batch.commit();
      }

      await FirebaseFirestore.instance.collection('notifications').add({
        'target_user_id': widget.riderId,
        'title': 'Cash Settled! ✅',
        'message': 'অ্যাডমিন আপনার কাছ থেকে ৳${widget.cashAmount.toStringAsFixed(0)} ক্যাশ বুঝে পেয়েছেন।',
        'sent_at': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider Cash Settled Successfully! ✅'), backgroundColor: Colors.teal));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
      }
    }
    
    // ডাটাবেস আপডেট হওয়ার পর স্ট্রিম এটিকে রিমুভ করে দিবে, তবুও সেফটির জন্য mounted চেক
    if (mounted) setState(() => _isProcessing = false);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(widget.riderId).get(),
      builder: (context, rSnap) {
        String rName = 'Loading...';
        if (rSnap.hasData && rSnap.data!.exists) {
          rName = rSnap.data!['name'] ?? 'Unknown Rider';
        }
        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.teal.shade200)),
          child: ListTile(
            leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.attach_money, color: Colors.white)),
            title: Text(rName, style: const TextStyle(fontWeight: FontWeight.bold)), 
            subtitle: Text('Holding Cash: ৳${widget.cashAmount.toStringAsFixed(0)} \n(${widget.orderIds.length} orders)', style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)), 
            trailing: _isProcessing
              ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.teal))
              : ElevatedButton(
                  onPressed: _receiveCash, 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
                  child: const Text('Receive Cash', style: TextStyle(color: Colors.white))
                )
          ),
        );
      }
    );
  }
}


// ==========================================
// [NEW] Seller Payout Card (With Proof Image & Financial Snapshot)
// ==========================================
class SellerPayoutCard extends StatefulWidget {
  final String sellerId;
  final double totalEarned;
  final double pendingEarned;

  const SellerPayoutCard({super.key, required this.sellerId, required this.totalEarned, required this.pendingEarned});

  @override
  State<SellerPayoutCard> createState() => _SellerPayoutCardState();
}

class _SellerPayoutCardState extends State<SellerPayoutCard> {
  bool _isProcessing = false;
  final ImagePicker _picker = ImagePicker();
  XFile? _proofImage;

  Future<void> _processPayout(double amountDue, Map<String, dynamic> sellerData) async {
    TextEditingController amountCtrl = TextEditingController(text: amountDue.toStringAsFixed(0));
    TextEditingController trxCtrl = TextEditingController();
    String selectedMethod = 'Bank Transfer';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Settle Payment Details'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Total Due: ৳${amountDue.toStringAsFixed(0)}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                  Text('Pending/Processing: ৳${widget.pendingEarned.toStringAsFixed(0)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount Paying Now (৳)', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder(), isDense: true),
                    items: ['Bank Transfer', 'bKash', 'Nagad', 'Cash (Hand to Hand)'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                    onChanged: (val) => setDialogState(() => selectedMethod = val!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: trxCtrl,
                    decoration: const InputDecoration(labelText: 'Transaction ID / Note', border: OutlineInputBorder(), isDense: true),
                  ),
                  const SizedBox(height: 15),
                  
                  // প্রুফ ছবি আপলোড (বিশেষ করে ক্যাশের জন্য)
                  const Text('Payment Proof / Signature', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 5),
                  InkWell(
                    onTap: () async {
                      final XFile? img = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
                      if (img != null) setDialogState(() => _proofImage = img);
                    },
                    child: Container(
                      height: 80, width: double.infinity,
                      decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: _proofImage != null 
                        ? (kIsWeb ? Image.network(_proofImage!.path, fit: BoxFit.cover) : Image.file(File(_proofImage!.path), fit: BoxFit.cover))
                        : Column(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.add_a_photo, color: Colors.grey), Text('Upload Proof/Signature', style: TextStyle(color: Colors.grey, fontSize: 11))]),
                    ),
                  )
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: () => Navigator.pop(context, true), 
                child: const Text('Confirm', style: TextStyle(color: Colors.white))
              )
            ],
          );
        }
      )
    ).then((confirmed) async {
      if (confirmed == true) {
        double payAmount = double.tryParse(amountCtrl.text) ?? 0;
        if (payAmount <= 0) return;

        setState(() => _isProcessing = true);

        try {
          // ১. প্রুফ ছবি স্টোরেজে আপলোড
          String? proofUrl;
          if (_proofImage != null) {
            String fileName = 'settlement_${widget.sellerId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
            Reference ref = FirebaseStorage.instance.ref().child('settlement_proofs').child(fileName);
            if (kIsWeb) {
              await ref.putData(await _proofImage!.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
            } else {
              await ref.putFile(File(_proofImage!.path));
            }
            proofUrl = await ref.getDownloadURL();
          }

          // ২. লাস্ট পেমেন্ট ডেট বের করা (হিস্ট্রির জন্য)
          var lastPaySnap = await FirebaseFirestore.instance.collection('settlements').where('user_id', isEqualTo: widget.sellerId).orderBy('timestamp', descending: true).limit(1).get();
          Timestamp? lastPaymentDate = lastPaySnap.docs.isNotEmpty ? lastPaySnap.docs.first['timestamp'] : null;

          double previousPaid = (sellerData['total_withdrawn'] as num?)?.toDouble() ?? 0.0;
          double balanceDueAfter = amountDue - payAmount; // এই পেমেন্টের পর কত বকেয়া থাকল

          // ৩. সেলারের প্রোফাইলে total_withdrawn ফিল্ড আপডেট
          await FirebaseFirestore.instance.collection('users').doc(widget.sellerId).set({
            'total_withdrawn': FieldValue.increment(payAmount)
          }, SetOptions(merge: true));

          // ৪. সম্পূর্ণ ফাইন্যান্সিয়াল স্ন্যাপশট সহ ট্রানজেকশন হিস্ট্রি সেভ করা
          await FirebaseFirestore.instance.collection('settlements').add({
            'type': 'seller_payout',
            'user_id': widget.sellerId,
            'seller_name': sellerData['name'] ?? 'Unknown',
            'shop_name': sellerData['shop_name'] ?? 'Unknown',
            'shop_address': sellerData['shop_address'] ?? 'N/A',
            'phone': sellerData['phone'] ?? 'N/A',
            
            // Financial Snapshot
            'lifetime_earnings': widget.totalEarned,
            'previous_paid': previousPaid,
            'amount': payAmount, // Current paying amount
            'balance_due': balanceDueAfter, // Remaining due
            'pending_amount': widget.pendingEarned, // Pipeline amount
            'last_payment_date': lastPaymentDate,
            
            'method': selectedMethod,
            'trx_id': trxCtrl.text.trim(),
            'proof_image_url': proofUrl,
            'timestamp': FieldValue.serverTimestamp(),
          });

          // ৫. সেলারকে নোটিফিকেশন পাঠানো
          await FirebaseFirestore.instance.collection('notifications').add({
            'target_user_id': widget.sellerId,
            'title': 'Payment Processed 💸',
            'message': 'আপনার ৳${payAmount.toStringAsFixed(0)} পেমেন্ট ক্লিয়ার করা হয়েছে। মানি রিসিট অ্যাপে দেখতে পারবেন।',
            'sent_at': FieldValue.serverTimestamp(),
          });

          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('৳$payAmount Settled Successfully! ✅')));
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
        }

        if (mounted) {
          setState(() {
            _isProcessing = false;
            _proofImage = null;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(widget.sellerId).get(),
      builder: (context, userSnap) {
        if (!userSnap.hasData) return const SizedBox();
        
        var uData = userSnap.data!.data() as Map<String, dynamic>? ?? {};
        String shopName = uData['shop_name'] ?? uData['name'] ?? 'Unknown Shop';
        double totalWithdrawn = (uData['total_withdrawn'] as num?)?.toDouble() ?? 0.0;
        
        double amountDue = widget.totalEarned - totalWithdrawn;

        if (amountDue <= 0.5) return const SizedBox(); 

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(backgroundColor: Colors.orange.shade100, child: const Icon(Icons.store, color: Colors.deepOrange)),
            title: Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold)), 
            subtitle: Text('Ready Due: ৳${amountDue.toStringAsFixed(0)}\nPending: ৳${widget.pendingEarned.toStringAsFixed(0)}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12)), 
            trailing: _isProcessing 
              ? const SizedBox(width: 30, height: 30, child: CircularProgressIndicator(color: Colors.deepOrange))
              : ElevatedButton(
                  onPressed: () => _processPayout(amountDue, uData), 
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
                  child: const Text('Settle', style: TextStyle(color: Colors.white))
                )
          ),
        );
      }
    );
  }
}

// ==========================================
// [NEW] Professional Settlement History & A4 PDF Receipt Page
// ==========================================
class AdminSettlementHistoryPage extends StatelessWidget {
  const AdminSettlementHistoryPage({super.key});

  Future<void> _generateProfessionalPayslip(Map<String, dynamic> data, String docId) async {
    final pdf = pw.Document();
    
    DateTime dt = (data['timestamp'] as Timestamp).toDate();
    String dateStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    
    String lastPayStr = 'N/A';
    if (data['last_payment_date'] != null) {
      DateTime lDt = (data['last_payment_date'] as Timestamp).toDate();
      lastPayStr = '${lDt.day}/${lDt.month}/${lDt.year}';
    }

    // ছবি ইন্টারনেট থেকে লোড করে PDF এ বসানোর জন্য
    pw.ImageProvider? proofImageProvider;
    if (data['proof_image_url'] != null && data['proof_image_url'].toString().isNotEmpty) {
      try {
        final response = await http.get(Uri.parse(data['proof_image_url']));
        if (response.statusCode == 200) {
          proofImageProvider = pw.MemoryImage(response.bodyBytes);
        }
      } catch (e) {
        // ছবি লোড না হলে ইগনোর করবে
      }
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('D Shop', style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)),
                      pw.SizedBox(height: 5),
                      pw.Text('Dhaka, Bangladesh', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                      pw.Text('support@dshop.com | 01700-000000', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ]
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('SELLER PAYSLIP', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                      pw.SizedBox(height: 5),
                      pw.Text('Slip No: ${docId.toUpperCase()}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 11)),
                    ]
                  )
                ]
              ),
              
              pw.SizedBox(height: 30),
              pw.Divider(color: PdfColors.grey400),
              pw.SizedBox(height: 15),

              // Seller Details
              pw.Text('PAID TO:', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.grey700)),
              pw.SizedBox(height: 5),
              pw.Text(data['shop_name'] ?? 'Unknown Shop', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.Text('Proprietor: ${data['seller_name'] ?? 'N/A'}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Phone: ${data['phone'] ?? 'N/A'}', style: const pw.TextStyle(fontSize: 11)),
              pw.Text('Address: ${data['shop_address'] ?? 'N/A'}', style: const pw.TextStyle(fontSize: 11)),

              pw.SizedBox(height: 30),

              // Financial Snapshot Table
              pw.Text('FINANCIAL SNAPSHOT (At the time of payment)', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300),
                children: [
                  _buildPdfTableRow('Lifetime Gross Earnings', 'Tk ${(data['lifetime_earnings'] ?? 0).toStringAsFixed(2)}', isHeader: true),
                  _buildPdfTableRow('Previously Paid Amount', 'Tk ${(data['previous_paid'] ?? 0).toStringAsFixed(2)}'),
                  _buildPdfTableRow('Amount Paid This Transaction', 'Tk ${(data['amount'] ?? 0).toStringAsFixed(2)}', highlight: true),
                  _buildPdfTableRow('Remaining Balance Due', 'Tk ${(data['balance_due'] ?? 0).toStringAsFixed(2)}'),
                  _buildPdfTableRow('Pending/Pipeline Amount (In-transit)', 'Tk ${(data['pending_amount'] ?? 0).toStringAsFixed(2)}', textColor: PdfColors.orange700),
                ]
              ),

              pw.SizedBox(height: 30),

              // Transaction Details
              pw.Text('TRANSACTION DETAILS', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
              pw.SizedBox(height: 10),
              pw.Container(
                padding: const pw.EdgeInsets.all(15),
                decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(5)),
                child: pw.Column(
                  children: [
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Payment Method:'), pw.Text(data['method'] ?? 'N/A', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
                    pw.SizedBox(height: 8),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Transaction ID / Note:'), pw.Text(data['trx_id'] ?? 'N/A', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))]),
                    pw.SizedBox(height: 8),
                    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [pw.Text('Previous Payment Date:'), pw.Text(lastPayStr)]),
                  ]
                )
              ),

              pw.SizedBox(height: 30),

              // Proof Image (If exists)
              if (proofImageProvider != null) ...[
                pw.Text('ATTACHED PROOF / SIGNATURE', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfColors.teal)),
                pw.SizedBox(height: 10),
                pw.Container(
                  height: 150, width: 250,
                  decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                  child: pw.Image(proofImageProvider, fit: pw.BoxFit.contain)
                ),
              ],

              pw.Spacer(),

              // Signatures
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text('Authorized Admin Signature', style: const pw.TextStyle(fontSize: 10)),
                    ]
                  ),
                  pw.Column(
                    children: [
                      pw.Container(width: 150, height: 1, color: PdfColors.black),
                      pw.SizedBox(height: 5),
                      pw.Text('Seller / Receiver Signature', style: const pw.TextStyle(fontSize: 10)),
                    ]
                  )
                ]
              ),

              pw.SizedBox(height: 20),
              pw.Center(child: pw.Text('This is a system-generated secure payslip. Thank you for doing business with D Shop.', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600))),
            ]
          );
        }
      )
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Payslip_${data['shop_name']}_${dt.month}-${dt.year}.pdf');
  }

  pw.TableRow _buildPdfTableRow(String title, String value, {bool isHeader = false, bool highlight = false, PdfColor textColor = PdfColors.black}) {
    return pw.TableRow(
      decoration: highlight ? const pw.BoxDecoration(color: PdfColors.teal50) : null,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(title, style: pw.TextStyle(fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal, fontSize: 11)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(8),
          child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: highlight ? PdfColors.teal : textColor)),
        ),
      ]
    );
  }

  // [NEW] ফুল-স্ক্রিন প্রুফ ছবি দেখার ডায়ালগ
  void _showProofImage(BuildContext context, String imageUrl) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          alignment: Alignment.center,
          children:[
            InteractiveViewer(panEnabled: true, minScale: 0.5, maxScale: 4, child: Image.network(imageUrl, fit: BoxFit.contain, width: double.infinity, height: double.infinity)),
            Positioned(top: 40, right: 20, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.white, size: 35), onPressed: () => Navigator.pop(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Settlement Records'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('settlements').orderBy('timestamp', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No transactions found.'));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              String dateStr = 'Unknown Date';
              if (data['timestamp'] != null) {
                DateTime dt = (data['timestamp'] as Timestamp).toDate();
                dateStr = '${dt.day}/${dt.month}/${dt.year}';
              }

              bool isSeller = data['type'] == 'seller_payout';
              String name = data['shop_name'] ?? data['seller_name'] ?? 'Unknown';

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: isSeller ? Colors.orange.shade50 : Colors.teal.shade50,
                                child: Icon(isSeller ? Icons.store : Icons.motorcycle, color: isSeller ? Colors.deepOrange : Colors.teal),
                              ),
                              const SizedBox(width: 10),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  Text(dateStr, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ],
                              ),
                            ],
                          ),
                          Text('৳${data['amount']}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isSeller ? Colors.red : Colors.green)),
                        ],
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text('Method: ${data['method']} \nTrxID: ${data['trx_id'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.black87))),
                          
                          // যদি ছবি থাকে তবে দেখার বাটন
                          if (data['proof_image_url'] != null)
                            IconButton(
                              icon: const Icon(Icons.image, color: Colors.blue),
                              onPressed: () => _showProofImage(context, data['proof_image_url']),
                              tooltip: 'View Signature/Proof',
                            ),
                          
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal)),
                            onPressed: () => _generateProfessionalPayslip(data, doc.id), 
                            icon: const Icon(Icons.print, size: 16), 
                            label: const Text('Payslip')
                          )
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        }
      ),
    );
  }
}

// ==========================================
// [FINAL VERSION] Admin Tele-Sales (Manual Order Page)
// ==========================================

class AdminManualOrderPage extends StatefulWidget {
  const AdminManualOrderPage({super.key});

  @override
  State<AdminManualOrderPage> createState() => _AdminManualOrderPageState();
}

class _AdminManualOrderPageState extends State<AdminManualOrderPage> {
  // টেক্সট কন্ট্রোলার
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController skuCtrl = TextEditingController(); // শুধু নাম্বার নিবে

  // ডাটা ভেরিয়েবল
  Map<String, dynamic>? foundProduct;
  String? foundProductId;
  Map<String, dynamic>? sellerData;
  
  // ভেরিয়েন্ট সিলেকশন
  String? selectedColor;
  String? selectedSize;
  int displayedPrice = 0;
  int displayedStock = 0;
  String? activeImageUrl;
  
  // কোয়ান্টিটি
  int orderQty = 1; 

  // লোকেশন ও দূরত্ব
  LatLng? pinnedCustomerLocation;
  double distanceInKm = 0.0;
  int calculatedDeliveryFee = 0;

  bool isSearchingProduct = false;

  // মোট দাম হিসাব করার গেটার
  int get finalTotalAmount => (displayedPrice * orderQty) + calculatedDeliveryFee;

  // ১. প্রোডাক্ট সার্চ (অটোমেটিক DS- যুক্ত হবে)
  Future<void> _searchProduct() async {
    if (skuCtrl.text.isEmpty) return;
    setState(() {
      isSearchingProduct = true;
      foundProduct = null;
      selectedColor = null;
      selectedSize = null;
      orderQty = 1;
    });

    // 🔴 ইউজারের টাইপ করা নাম্বারের আগে DS- যুক্ত করা হচ্ছে
    String searchSku = 'DS-${skuCtrl.text.trim()}'.toUpperCase();

    var prodSnap = await FirebaseFirestore.instance.collection('products')
        .where('sku', isEqualTo: searchSku)
        .limit(1).get();

    if (prodSnap.docs.isNotEmpty) {
      var pData = prodSnap.docs.first.data();
      var sSnap = await FirebaseFirestore.instance.collection('users').doc(pData['seller_id']).get();
      
      setState(() {
        foundProduct = pData;
        foundProductId = prodSnap.docs.first.id;
        displayedPrice = pData['price'] ?? 0;
        displayedStock = pData['stock'] ?? 0;
        activeImageUrl = (pData['image_urls'] as List).isNotEmpty ? pData['image_urls'][0] : '';
        if (sSnap.exists) sellerData = sSnap.data() as Map<String, dynamic>?;
      });
      _updatePriceAndStock(); 
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product not found! ❌'), backgroundColor: Colors.red));
    }
    setState(() => isSearchingProduct = false);
  }

  // ২. প্রাইস ও স্টক আপডেট
  void _updatePriceAndStock() {
    if (foundProduct == null || foundProduct!['variants'] == null) return;
    List variants = foundProduct!['variants'];
    int basePrice = foundProduct!['price'] ?? 0;

    var match = variants.firstWhere((v) => 
      (selectedColor == null || v['color'] == selectedColor) && 
      (selectedSize == null || v['size'] == selectedSize), 
      orElse: () => null
    );

    if (match != null) {
      setState(() {
        displayedPrice = basePrice + (int.tryParse(match['price'].toString()) ?? 0);
        displayedStock = int.tryParse(match['stock'].toString()) ?? 0;
        if (match['color_image_url'] != null) activeImageUrl = match['color_image_url'];
        
        if (orderQty > displayedStock && displayedStock > 0) {
          orderQty = displayedStock;
        } else if (displayedStock == 0) {
          orderQty = 1;
        }
      });
    }
  }

  // ৩. ম্যাপ থেকে লোকেশন নেওয়া এবং Google API দিয়ে অটোমেটিক ঠিকানা ফিলআপ করা
  Future<void> _pickCustomerLocation() async {
    if (sellerData == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আগে প্রোডাক্ট কোড দিয়ে সেলার নিশ্চিত করুন!')));
      return;
    }

    LatLng? pickedLocation = await Navigator.push(
      context, MaterialPageRoute(builder: (context) => const LocationPickerScreen())
    );

    if (pickedLocation != null) {
      // 🔴 Google Maps API (Geocoding) ব্যবহার করে সরাসরি পিনের জায়গার নাম বের করা
      try {
        String apiKey = "AIzaSyC6C-fHPPbo5xdDDuNhEm4wDfVci9BZI0M"; // আপনার API Key
        String url = "https://maps.googleapis.com/maps/api/geocode/json?latlng=${pickedLocation.latitude},${pickedLocation.longitude}&key=$apiKey&language=bn"; // language=bn দিলে লোকাল নাম সুন্দরভাবে আসবে

        var response = await http.get(Uri.parse(url));
        var data = json.decode(response.body);

        if (data['status'] == 'OK' && data['results'].isNotEmpty) {
          // গুগল থেকে পাওয়া সবচেয়ে স্পেসিফিক ঠিকানা (বাড়ি/দোকান/প্রতিষ্ঠানের নাম সহ)
          String fullAddress = data['results'][0]['formatted_address'];
          
          setState(() {
            // বক্সে অটোমেটিক ঠিকানা বসিয়ে দেওয়া
            addressCtrl.text = fullAddress;
          });
        }
      } catch (e) {
        debugPrint("Google API Address Fetch Failed: $e");
      }

      // দূরত্ব এবং ডেলিভারি ফি হিসাব করা
      double sLat = sellerData!['latitude'] ?? 0.0;
      double sLng = sellerData!['longitude'] ?? 0.0;
      double dist = Geolocator.distanceBetween(sLat, sLng, pickedLocation.latitude, pickedLocation.longitude) / 1000;

      setState(() {
        pinnedCustomerLocation = pickedLocation;
        distanceInKm = dist;
        _calculateDeliveryCharge(dist);
      });
    }
  }

  // ৪. ডেলিভারি চার্জ
  void _calculateDeliveryCharge(double km) {
    if (km <= 2) calculatedDeliveryFee = 30;
    else if (km <= 5) calculatedDeliveryFee = 50;
    else calculatedDeliveryFee = 50 + ((km - 5).toInt() * 10); 
  }

  // ৫. অর্ডার প্লেস করা এবং সঠিক নোটিফিকেশন পাঠানো
  Future<void> _placeManualOrder() async {
    if (foundProduct == null || pinnedCustomerLocation == null || nameCtrl.text.isEmpty || phoneCtrl.text.isEmpty || addressCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সব তথ্য এবং ম্যাপ লোকেশন নিশ্চিত করুন!'), backgroundColor: Colors.red));
      return;
    }

    List variants = foundProduct!['variants'] ?? [];
    Set<String> colors = variants.map((v) => v['color'].toString()).toSet();
    Set<String> sizes = variants.map((v) => v['size'].toString()).toSet();

    if ((colors.length > 1 || colors.first != 'Default') && selectedColor == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে কালার সিলেক্ট করুন!'), backgroundColor: Colors.red));
       return;
    }
    if ((sizes.length > 1 || sizes.first != 'Default') && selectedSize == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে সাইজ সিলেক্ট করুন!'), backgroundColor: Colors.red));
       return;
    }

    if (displayedStock < orderQty) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('স্টকে পর্যাপ্ত পণ্য নেই!'), backgroundColor: Colors.red));
       return;
    }

    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

    try {
      String secretPickupOTP = (1000 + math.Random().nextInt(9000)).toString(); 
      User? adminUser = FirebaseAuth.instance.currentUser;

      Map<String, dynamic> orderItem = {
        'product_id': foundProductId,
        'product_name': foundProduct!['product_name'],
        'price': displayedPrice,
        'quantity': orderQty,
        'seller_id': foundProduct!['seller_id'],
        'image_url': activeImageUrl ?? '',
        'selected_color': selectedColor ?? '',
        'selected_size': selectedSize ?? '',
      };

      await FirebaseFirestore.instance.collection('orders').add({
        'user_id': adminUser?.uid ?? 'manual_admin',
        'items': [orderItem],
        'total_amount': finalTotalAmount,
        'delivery_fee': calculatedDeliveryFee,
        'payment_method': 'Cash on Delivery',
        'status': 'Processing', 
        'pickup_otp': secretPickupOTP,
        'order_date': FieldValue.serverTimestamp(),
        'shipping_name': nameCtrl.text.trim(),
        'shipping_phone': phoneCtrl.text.trim(),
        'shipping_address_text': addressCtrl.text.trim(),
        'customer_lat': pinnedCustomerLocation!.latitude,
        'customer_lng': pinnedCustomerLocation!.longitude,
        'is_manual_order': true, 
        'order_source': 'tele_sales',
      });

      DocumentReference pRef = FirebaseFirestore.instance.collection('products').doc(foundProductId);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        DocumentSnapshot pSnap = await transaction.get(pRef);
        if (pSnap.exists) {
          Map<String, dynamic> pData = pSnap.data() as Map<String, dynamic>;
          int currentTotalStock = int.tryParse(pData['stock'].toString()) ?? 0;
          List<dynamic> vList = pData['variants'] ?? [];

          for (int i = 0; i < vList.length; i++) {
            if (vList[i]['color'] == (selectedColor ?? 'Default') && vList[i]['size'] == (selectedSize ?? 'Default')) {
              int vStock = int.tryParse(vList[i]['stock'].toString()) ?? 0;
              vList[i]['stock'] = (vStock - orderQty) >= 0 ? (vStock - orderQty) : 0;
              break;
            }
          }

          transaction.update(pRef, {
            'stock': (currentTotalStock - orderQty) >= 0 ? (currentTotalStock - orderQty) : 0,
            'sales_count': FieldValue.increment(orderQty),
            'variants': vList
          });
        }
      });

      // 🔴 সেলারকে পুশ নোটিফিকেশন পাঠানো
      await FirebaseFirestore.instance.collection('notifications').add({
        'target_user_id': foundProduct!['seller_id'],
        'title': 'New Tele-Sales Order! 📦',
        'message': 'অফিস থেকে আপনার একটি পণ্য অর্ডার করা হয়েছে। দয়া করে প্যাক করুন।',
        'target_role': 'seller', // পুশ যাওয়ার জন্য গুরুত্বপূর্ণ
        'data': {'screen': 'seller_orders'},
        'sent_at': FieldValue.serverTimestamp(),
      });

      // 🔴 অ্যাডমিন প্যানেলে রেকর্ড রাখার জন্য নোটিফিকেশন
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'Manual Order Placed ✅',
        'message': '${nameCtrl.text.trim()} এর জন্য একটি ম্যানুয়াল অর্ডার প্লেস করা হয়েছে।',
        'topic': 'admins',
        'type': 'new_order',
        'data': {'screen': 'admin_orders'},
        'sent_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('অর্ডার সফলভাবে সেলারের কাছে পাঠানো হয়েছে! ✅'), backgroundColor: Colors.green));
      
      setState(() {
        phoneCtrl.clear();
        nameCtrl.clear();
        addressCtrl.clear();
        skuCtrl.clear();
        foundProduct = null;
        pinnedCustomerLocation = null;
        distanceInKm = 0.0;
        calculatedDeliveryFee = 0;
        orderQty = 1;
      });

    } catch (e) {
       Navigator.pop(context);
       ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Tele-Sales (Manual Order)'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  _buildCard('Customer & Delivery Info', Icons.person, Colors.deepOrange, [
                    TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Phone Number', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Customer Name', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: addressCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Detailed Address', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 15),
                    
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _pickCustomerLocation, 
                        icon: const Icon(Icons.location_on), 
                        label: const Text('Pin Customer Location on Map'),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                      ),
                    ),
                    if (pinnedCustomerLocation != null)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Text('Distance (Seller to Pinned): ${distanceInKm.toStringAsFixed(2)} KM\nDelivery Fee: ৳$calculatedDeliveryFee', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      )
                  ]),

                  const SizedBox(height: 15),

                  _buildCard('Product & Seller Details', Icons.shopping_bag, Colors.teal, [
                    Row(
                      children:[
                        // 🔴 सिर्फ Number Type करने के लिए Keyboard, Prefix 'DS-' Add किया गया
                        Expanded(
                          child: TextField(
                            controller: skuCtrl, 
                            keyboardType: TextInputType.number, 
                            decoration: const InputDecoration(
                              labelText: 'Enter Product Code', 
                              prefixText: 'DS- ', // 🔴 ডিফল্ট প্রিফিক্স
                              prefixStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                              border: OutlineInputBorder(), 
                              isDense: true
                            )
                          )
                        ),
                        const SizedBox(width: 10),
                        IconButton(onPressed: _searchProduct, icon: const Icon(Icons.search, color: Colors.teal), style: IconButton.styleFrom(backgroundColor: Colors.teal.shade50)),
                      ]
                    ),
                    if (isSearchingProduct) const LinearProgressIndicator(),

                    if (foundProduct != null) ...[
                      const Divider(height: 30),
                      Row(
                        children: [
                          CircleAvatar(backgroundImage: NetworkImage(sellerData?['profile_image_url'] ?? '')),
                          const SizedBox(width: 10),
                          Text(sellerData?['shop_name'] ?? 'Loading Shop...', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        children: [
                          Container(height: 70, width: 70, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(activeImageUrl ?? ''), fit: BoxFit.cover))),
                          const SizedBox(width: 15),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(foundProduct!['product_name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('Price: ৳$displayedPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 18)),
                                Text('Stock Available: $displayedStock', style: TextStyle(color: displayedStock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          )
                        ],
                      ),
                      const SizedBox(height: 20),

                      if (foundProduct!['variants'] != null) ...[
                        const Text('Select Variants (কালার/সাইজ ক্লিক করুন):', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 8),
                        _buildVariantChips(),
                      ],

                      const SizedBox(height: 20),
                      
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Order Quantity:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle, color: Colors.redAccent, size: 28),
                                  onPressed: () {
                                    if (orderQty > 1) setState(() => orderQty--);
                                  },
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 15),
                                  child: Text('$orderQty', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add_circle, color: Colors.teal, size: 28),
                                  onPressed: () {
                                    if (orderQty < displayedStock) {
                                      setState(() => orderQty++);
                                    } else {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('স্টকে এর চেয়ে বেশি পণ্য নেই!')));
                                    }
                                  },
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    ]
                  ]),
                  const SizedBox(height: 10), 
                ],
              ),
            ),
          ),
          
          if (foundProduct != null)
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.white, boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
              child: SizedBox(
                width: double.infinity, height: 60,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                  ),
                  onPressed: _placeManualOrder, 
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                       Text('Total: ৳$finalTotalAmount', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                       Row(
                         children: const [
                           Text('PLACE MANUAL ORDER', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                           SizedBox(width: 5),
                           Icon(Icons.check_circle, color: Colors.white),
                         ],
                       )
                    ]
                  )
                ),
              ),
            )
        ],
      ),
    );
  }

  Widget _buildVariantChips() {
    List variants = foundProduct!['variants'];
    Set<String> colors = variants.map((v) => v['color'].toString()).toSet();
    Set<String> sizes = variants.map((v) => v['size'].toString()).toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (colors.length > 1 || colors.first != 'Default')
          Wrap(spacing: 8, children: colors.map((c) => ChoiceChip(label: Text(c), selectedColor: Colors.deepOrange.shade100, selected: selectedColor == c, onSelected: (val) { setState(() => selectedColor = val ? c : null); _updatePriceAndStock(); })).toList()),
        const SizedBox(height: 10),
        if (sizes.length > 1 || sizes.first != 'Default')
          Wrap(spacing: 8, children: sizes.map((s) => ChoiceChip(label: Text(s), selectedColor: Colors.teal.shade100, selected: selectedSize == s, onSelected: (val) { setState(() => selectedSize = val ? s : null); _updatePriceAndStock(); })).toList()),
      ],
    );
  }

  Widget _buildCard(String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.2))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(icon, color: color), const SizedBox(width: 10), Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color))]),
          const Divider(height: 25),
          ...children
        ],
      ),
    );
  }
}