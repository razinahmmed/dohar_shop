import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart'; 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';

// আমাদের নিজেদের ফাইলগুলোর লিংক (যাতে এক পেজ থেকে অন্য পেজে যাওয়া যায়)

import 'auth_screens.dart';
import 'seller_screens.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../notification_service.dart';
import 'package:share_plus/share_plus.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

// ==========================================
// মেইন স্ক্রিন (Customer Bottom Navigation Bar + Notification Setup)
// ==========================================
class MainScreen extends StatefulWidget {
  final int initialPage;
  const MainScreen({super.key, this.initialPage = 0});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _selectedIndex;

  final List<Widget> _pages = [
    const ShopeeHome(),
    const CategoryPage(),
    const CartPage(),
    const UserDashboard(), // ইনডেক্স ৩ (Profile/Orders)
  ];

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialPage; 
    _setupFCMForAllRoles(); 
  }

  // ✅ নতুন এবং ফিক্সড FCM সেটআপ ফাংশন
  void _setupFCMForAllRoles() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      // টোকেন আপডেট
      String? token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'fcm_token': token});
      }

      // ডাটাবেস থেকে রোল চেক করে সঠিক টপিকে সাবস্ক্রাইব করা
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (userDoc.exists) {
        String role = (userDoc.data() as Map<String, dynamic>)['role'] ?? 'customer';

        // পরিষ্কার করার জন্য প্রথমে আন-সাবস্ক্রাইব করা (জরুরি)
        await messaging.unsubscribeFromTopic('riders');
        await messaging.unsubscribeFromTopic('sellers');
        await messaging.unsubscribeFromTopic('all_users');

        // রোল অনুযায়ী নতুন করে সাবস্ক্রাইব
        if (role == 'rider') {
          await messaging.subscribeToTopic('riders');
          print("FCM: Subscribed as Rider");
        } else if (role == 'seller') {
          await messaging.subscribeToTopic('sellers');
          print("FCM: Subscribed as Seller");
        } else {
          await messaging.subscribeToTopic('all_users');
          print("FCM: Subscribed as Customer");
        }
        // রাইডার বা সেলার হলেও যেন অল ইউজার মেসেজ পায়
        if (role != 'customer') await messaging.subscribeToTopic('all_users');
      }
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        NotificationService.showFcmNotification(message);
      }
    });
  }

  void _onItemTapped(int index) {
    User? user = FirebaseAuth.instance.currentUser;
    if (index == 2) {
      if (user == null) {
        _showLoginPopup(context, "Please login to view your Cart!");
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage()));
      }
    } else if (index == 3) {
      if (user == null) {
        _showLoginPopup(context, "Please login to access your Profile!");
      } else {
        setState(() { _selectedIndex = index; });
      }
    } else {
      setState(() { _selectedIndex = index; });
    }
  }

  void _showLoginPopup(BuildContext context, String message) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              const Icon(Icons.lock_outline, size: 50, color: Colors.deepOrange),
              const SizedBox(height: 15),
              Text(message, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
                  },
                  child: const Text('LOGIN / REGISTER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Continue as Guest', style: TextStyle(color: Colors.grey)))
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey[600],
        showUnselectedLabels: true,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        onTap: _onItemTapped,
        items: const[
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded), label: 'Categories'),
          BottomNavigationBarItem(icon: Icon(Icons.shopping_cart_outlined), label: 'Cart'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ==========================================
// ৪ নম্বর পেজ: Cart Page (Fixed Currency, Single Delete & Dynamic Free Shipping)
// ==========================================
class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  Set<String> selectedItems = {};
  Set<String> selectedShops = {}; 
  bool selectAll = false;
  int freeShippingThreshold = 0; // অ্যাডমিন সেট করা ফ্রি শিপিং টার্গেট
  
  final Color shopeeOrange = const Color(0xFFEE4D2D);
  final Color shopeeGreen = const Color(0xFF00BFA5);

  @override
  void initState() {
    super.initState();
    _fetchFreeShippingPromo();
  }

  // ফায়ারবেস থেকে ফ্রি শিপিংয়ের এমাউন্ট আনা
  Future<void> _fetchFreeShippingPromo() async {
    try {
      DocumentSnapshot settingsDoc = await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').get();
      if (settingsDoc.exists) {
        Map<String, dynamic> data = settingsDoc.data() as Map<String, dynamic>;
        setState(() {
          freeShippingThreshold = (data['free_shipping_threshold'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('দয়া করে লগইন করুন'));

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFFEE4D2D), size: 28), onPressed: () => Navigator.pop(context)),
        title: StreamBuilder(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').snapshots(),
          builder: (context, snapshot) {
            int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
            return Text('Shopping Cart ($count)', style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w500));
          }
        ),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          bool isCartEmpty = !snapshot.hasData || snapshot.data!.docs.isEmpty;

          Map<String, List<QueryDocumentSnapshot>> groupedItems = {};
          double grandTotalTaka = 0;
          int totalSelectedCount = 0;
          double totalSaved = 0;

          // কার্ট খালি না হলে হিসাবগুলো করবে
          if (!isCartEmpty) {
            for (var doc in snapshot.data!.docs) {
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              String sellerId = data['seller_id'] ?? 'unknown_seller';
              if (!groupedItems.containsKey(sellerId)) groupedItems[sellerId] = [];
              groupedItems[sellerId]!.add(doc);

              if (selectedItems.contains(doc.id)) {
                double price = double.tryParse(data['price'].toString()) ?? 0.0;
                double originalPrice = double.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : price.toString()) ?? price;
                int qty = int.tryParse(data['quantity'].toString()) ?? 1;
                
                grandTotalTaka += (price * qty);
                totalSelectedCount += qty;
                if (originalPrice > price) {
                  totalSaved += ((originalPrice - price) * qty);
                }
              }
            }
          }

          return Column(
            children:[
              Expanded(
                child: isCartEmpty 
                  // 🔴 কার্ট খালি থাকলে এই সুন্দর ডিজাইনটি দেখাবে
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.remove_shopping_cart_outlined, size: 80, color: Colors.grey.shade300),
                          const SizedBox(height: 15),
                          const Text('আপনার কার্ট খালি!', style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 5),
                          const Text('পছন্দের প্রোডাক্ট কার্টে যুক্ত করুন', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    )
                  // 🟢 কার্টে প্রোডাক্ট থাকলে লিস্ট দেখাবে
                  : ListView(
                      children:[
                        ...groupedItems.entries.map((entry) {
                          String sellerId = entry.key;
                          List<QueryDocumentSnapshot> items = entry.value;
                          bool isShopSelected = shopItemsAllSelected(items);

                          double shopTotal = items.fold(0.0, (sum, doc) {
                            double p = double.tryParse(doc['price'].toString()) ?? 0.0;
                            int q = int.tryParse(doc['quantity'].toString()) ?? 1;
                            return sum + (p * q);
                          });

                          return Container(
                            margin: const EdgeInsets.only(top: 10),
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:[
                                FutureBuilder<DocumentSnapshot>(
                                  future: FirebaseFirestore.instance.collection('users').doc(sellerId).get(),
                                  builder: (context, shopSnapshot) {
                                    String shopName = 'Unknown Shop';
                                    String shopLogo = '';
                                    if (shopSnapshot.hasData && shopSnapshot.data!.exists) {
                                      var shopData = shopSnapshot.data!.data() as Map<String, dynamic>;
                                      shopName = shopData.containsKey('shop_name') && shopData['shop_name'].toString().isNotEmpty ? shopData['shop_name'] : shopData['name'] ?? 'Unknown Shop';
                                      shopLogo = shopData['profile_image_url'] ?? '';
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                      child: Row(
                                        children:[
                                          _buildShopeeCheckbox(
                                            value: isShopSelected,
                                            onChanged: (val) {
                                              setState(() {
                                                if (val == true) {
                                                  selectedShops.add(sellerId);
                                                  for (var item in items) {
                                                    selectedItems.add(item.id);
                                                  }
                                                } else {
                                                  selectedShops.remove(sellerId);
                                                  for (var item in items) {
                                                    selectedItems.remove(item.id);
                                                  }
                                                }
                                              });
                                            }
                                          ),
                                          CircleAvatar(radius: 12, backgroundColor: Colors.grey[200], backgroundImage: shopLogo.isNotEmpty ? NetworkImage(shopLogo) : null, child: shopLogo.isEmpty ? const Icon(Icons.storefront, size: 14, color: Colors.grey) : null),
                                          const SizedBox(width: 8),
                                          Expanded(child: Text('$shopName >', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                                        ],
                                      ),
                                    );
                                  }
                                ),
                                const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE)),
                                
                                if (freeShippingThreshold > 0)
                                  Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: const Color(0xFFF1FDFB), borderRadius: BorderRadius.circular(4)),
                                    child: Row(
                                      children:[
                                        Icon(Icons.local_shipping, color: shopeeGreen, size: 18),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children:[
                                              Text(
                                                shopTotal >= freeShippingThreshold 
                                                  ? "You've unlocked Free Shipping!" 
                                                  : "Add ৳${(freeShippingThreshold - shopTotal).toStringAsFixed(0)} more to get Free Shipping!",
                                                style: const TextStyle(color: Colors.black87, fontSize: 12),
                                              ),
                                              const SizedBox(height: 4),
                                              Container(
                                                height: 3, width: double.infinity, color: Colors.grey.shade200, alignment: Alignment.centerLeft, 
                                                child: FractionallySizedBox(widthFactor: (shopTotal / freeShippingThreshold).clamp(0.0, 1.0), child: Container(color: shopeeGreen))
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                ...items.map((cartItem) {
                                  Map<String, dynamic> data = cartItem.data() as Map<String, dynamic>;
                                  String imageUrl = data['image_url'] ?? '';
                                  bool isSelected = selectedItems.contains(cartItem.id);

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children:[
                                        Padding(
                                          padding: const EdgeInsets.only(top: 20),
                                          child: _buildShopeeCheckbox(
                                            value: isSelected,
                                            onChanged: (val) {
                                              setState(() {
                                                val == true ? selectedItems.add(cartItem.id) : selectedItems.remove(cartItem.id);
                                              });
                                            }
                                          ),
                                        ),
                                        Container(height: 85, width: 85, decoration: BoxDecoration(color: Colors.yellow[100], borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade300)), child: imageUrl.isNotEmpty ? Image.network(imageUrl, fit: BoxFit.cover) : const Center(child: Icon(Icons.image))),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children:[
                                              Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(child: Text(data['product_name'] ?? 'Product Name', style: const TextStyle(fontSize: 13, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis)),
                                                  InkWell(
                                                    onTap: () => FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).delete(),
                                                    child: const Padding(padding: EdgeInsets.only(left: 8.0), child: Icon(Icons.close, size: 18, color: Colors.grey)),
                                                  )
                                                ],
                                              ),
                                              const SizedBox(height: 5),
                                              if (data['selected_color']?.toString().isNotEmpty == true || data['selected_size']?.toString().isNotEmpty == true)
                                                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(2)), child: Text('${data['selected_color']} ${data['selected_size']}'.trim(), style: const TextStyle(fontSize: 11, color: Colors.black54))),
                                              const SizedBox(height: 8),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children:[
                                                  Text('৳${data['price']}', style: TextStyle(color: shopeeOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                                                  Row(
                                                    children:[
                                                      InkWell(onTap: () { if (data['quantity'] > 1) cartItem.reference.update({'quantity': FieldValue.increment(-1)}); }, child: Container(width: 25, height: 25, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Icon(Icons.remove, size: 14, color: Colors.black54))),
                                                      Container(width: 35, height: 25, decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300), bottom: BorderSide(color: Colors.grey.shade300))), alignment: Alignment.center, child: Text('${data['quantity']}', style: const TextStyle(fontSize: 13))),
                                                      InkWell(onTap: () => cartItem.reference.update({'quantity': FieldValue.increment(1)}), child: Container(width: 25, height: 25, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300)), child: const Icon(Icons.add, size: 14, color: Colors.black54))),
                                                    ],
                                                  )
                                                ],
                                              )
                                            ],
                                          ),
                                        )
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 20),
                      ],
                    ),
              ),

              // 🔴 এই বটম বারটি এখন সবসময় নিচে ফিক্সড থাকবে (কার্ট খালি থাকলেও)
              Container(
                decoration: BoxDecoration(color: Colors.white, boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))]),
                child: Row(
                  children:[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children:[
                          _buildShopeeCheckbox(
                            value: selectedItems.length == snapshot.data!.docs.length && snapshot.data!.docs.isNotEmpty,
                            onChanged: isCartEmpty ? (val){} : (val) {
                              setState(() {
                                if (val == true) {
                                  for (var doc in snapshot.data!.docs) {
                                    selectedItems.add(doc.id);
                                  }
                                } else {
                                  selectedItems.clear(); selectedShops.clear();
                                }
                              });
                            }
                          ),
                          const Text('All', style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children:[
                        RichText(
                          text: TextSpan(
                            children:[
                              const TextSpan(text: 'Total ', style: TextStyle(color: Colors.black87, fontSize: 13)),
                              TextSpan(text: '৳${grandTotalTaka.toStringAsFixed(0)} ', style: TextStyle(color: shopeeOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                            ]
                          )
                        ),
                        if(totalSaved > 0)
                          Text('Saved ৳${totalSaved.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFEE4D2D), fontSize: 11)),
                      ],
                    ),
                    const SizedBox(width: 10),
                    InkWell(
                      onTap: totalSelectedCount > 0 ? () {
                         Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(grandTotal: grandTotalTaka.toInt(), selectedItemIds: selectedItems.toList(), freeShippingThreshold: freeShippingThreshold)));
                      } : null,
                      child: Container(
                        height: 55, width: 120,
                        alignment: Alignment.center,
                        color: totalSelectedCount > 0 ? shopeeOrange : Colors.grey, // 🔴 কার্ট খালি থাকলে বাটনটি অটোমেটিক গ্রে (Disable) হয়ে থাকবে
                        child: Text('Check Out ($totalSelectedCount)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      ),
                    )
                  ],
                ),
              )
            ],
          );
        },
      ),
    );
  }

  bool shopItemsAllSelected(List<QueryDocumentSnapshot> items) {
    if (items.isEmpty) return false;
    for (var item in items) {
      if (!selectedItems.contains(item.id)) return false;
    }
    return true;
  }

  Widget _buildShopeeCheckbox({required bool value, required Function(bool?) onChanged}) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Container(margin: const EdgeInsets.only(right: 10), width: 22, height: 22, decoration: BoxDecoration(color: value ? shopeeOrange : Colors.white, borderRadius: BorderRadius.circular(3), border: Border.all(color: value ? shopeeOrange : Colors.grey.shade400, width: 1.5)), child: value ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
    );
  }
}

// ==========================================
// ৫ নম্বর পেজ: Checkout Page (Smart COD, Promo Anti-Fraud)
// ==========================================
class CheckoutPage extends StatefulWidget {
  final int grandTotal;
  final List<String> selectedItemIds;
  final int freeShippingThreshold;
  
  const CheckoutPage({super.key, required this.grandTotal, required this.selectedItemIds, required this.freeShippingThreshold});
  
  @override 
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final Color shopeeOrange = const Color(0xFFEE4D2D);
  final Color shopeeGreen = const Color(0xFF00BFA5);
  
  String selectedPayment = 'bKash'; 

  bool isLoadingData = true;
  bool isCodDisabled = false; 
  int _customerFailCount = 0; 
  
  Map<String, dynamic>? userAddress;
  List<Map<String, dynamic>> checkoutItems =[];
  Map<String, List<Map<String, dynamic>>> groupedItems = {};
  
  Map<String, double> shopDeliveryFees = {}; 
  Map<String, String> shopDistanceInfo = {}; 
  Map<String, String> shopDeliveryMethod = {}; 
  
  double productTotal = 0;
  double totalSaved = 0;
  double finalGrandTotal = 0; 

  int availableCoins = 0;
  bool useCoins = false;

  // [NEW] Promo Variables
  double welcomePromoDiscount = 0;
  bool isWelcomePromoApplied = false;
  String currentDeviceId = '';
  double promoPercentage = 0;

  @override
  void initState() {
    super.initState();
    _initializeCheckoutData();
  }

  Future<void> _initializeCheckoutData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ১. ইউজারের ডিফল্ট অ্যাড্রেস নিয়ে আসা
    var addrSnap = await FirebaseFirestore.instance.collection('users')
        .doc(user.uid)
        .collection('addresses')
        .where('is_default', isEqualTo: true)
        .limit(1)
        .get();
    if (addrSnap.docs.isNotEmpty) userAddress = addrSnap.docs.first.data();

    // ২. ইউজারের ওয়ালেটে কত কয়েন আছে তা চেক করা
    var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (userDoc.exists) availableCoins = (userDoc.data() as Map<String, dynamic>)['d_coins'] ?? 0;

    // ==========================================
    // [NEW LOGIC] Global COD Check & Customer History Check
    // ==========================================
    
    bool isGlobalCodEnabled = true;
    try {
      // অ্যাডমিন প্যানেল থেকে COD সবার জন্য চালু কি না তা চেক করা
      var globalDoc = await FirebaseFirestore.instance.collection('app_config').doc('global_settings').get();
      if (globalDoc.exists) {
        isGlobalCodEnabled = globalDoc.data()?['enable_cod'] ?? true;
      }
    } catch (e) {
      print("Error fetching global settings: $e");
    }

    // ইউজারের আগের কোনো ডেলিভারি ফেইল হয়েছে কি না তা চেক করা
    var failedOrdersSnap = await FirebaseFirestore.instance.collection('orders')
        .where('user_id', isEqualTo: user.uid)
        .where('status', isEqualTo: 'Delivery Failed')
        .get(); 
        
    _customerFailCount = failedOrdersSnap.docs.length;
    
    // [SMART LOGIC] 
    // ১. অ্যাডমিন যদি গ্লোবালি COD বন্ধ করে দেয় অথবা 
    // ২. ইউজারের যদি আগে ডেলিভারি ফেইল হওয়ার রেকর্ড থাকে
    // তাহলে COD অপশনটি ডিজেবল হয়ে যাবে এবং অটোমেটিক 'bKash' সিলেক্ট হবে।
    
    if (!isGlobalCodEnabled || _customerFailCount > 0) {
      isCodDisabled = true; 
      selectedPayment = 'bKash'; 
    } else {
      isCodDisabled = false;
      selectedPayment = 'Cash on Delivery'; 
    }
    
    

    var cartSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').get();
    for (var doc in cartSnapshot.docs) { 
      if (widget.selectedItemIds.contains(doc.id)) {
        Map<String, dynamic> itemData = doc.data();
        itemData['id'] = doc.id;
        String sId = itemData['seller_id'] ?? 'Unknown Shop';
        if (sId != 'Unknown Shop') {
          var shopDoc = await FirebaseFirestore.instance.collection('users').doc(sId).get();
          if (shopDoc.exists) {
            itemData['seller_name'] = (shopDoc.data() as Map<String, dynamic>)['shop_name'] ?? (shopDoc.data() as Map<String, dynamic>)['name'];
            itemData['seller_lat'] = (shopDoc.data() as Map<String, dynamic>)['latitude'] ?? 23.6062;
            itemData['seller_lng'] = (shopDoc.data() as Map<String, dynamic>)['longitude'] ?? 90.1345;
          } else {
            itemData['seller_name'] = sId;
          }
        }
        checkoutItems.add(itemData);
      }
    }

    for (var item in checkoutItems) {
      String sellerName = item['seller_name'] ?? 'Unknown Shop';
      if (!groupedItems.containsKey(sellerName)) groupedItems[sellerName] =[];
      groupedItems[sellerName]!.add(item);
      double price = double.tryParse(item['price'].toString()) ?? 0;
      int qty = int.tryParse(item['quantity'].toString()) ?? 1;
      productTotal += (price * qty);
    }

    for (var entry in groupedItems.entries) {
      String shopName = entry.key;
      var firstItem = entry.value.first;
      double sLat = firstItem['seller_lat'] ?? 23.6062;
      double sLng = firstItem['seller_lng'] ?? 90.1345;
      shopDeliveryMethod[shopName] = 'Standard Delivery';

      var chargeData = await _calculateChargeFromAPI(sLat, sLng);
      double thisShopTotal = entry.value.fold(0.0, (sum, i) => sum + ((double.tryParse(i['price'].toString()) ?? 0) * (int.tryParse(i['quantity'].toString()) ?? 1)));
      
      if (widget.freeShippingThreshold > 0 && thisShopTotal >= widget.freeShippingThreshold) {
        shopDeliveryFees[shopName] = 0.0;
        shopDistanceInfo[shopName] = "ফ্রি শিপিং উপভোগ করুন! (${chargeData['dist']})";
      } else {
        shopDeliveryFees[shopName] = chargeData['fee'];
        shopDistanceInfo[shopName] = "${chargeData['dist']} (${chargeData['time']})";
      }
    }

    // ==========================================
    // [NEW] Anti-Fraud Device ID Checking & Promo
    // ==========================================
    try {
      DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
      if (kIsWeb) {
        WebBrowserInfo webBrowserInfo = await deviceInfo.webBrowserInfo;
        currentDeviceId = webBrowserInfo.userAgent ?? 'web_user_${user.uid}';
      } else if (Platform.isAndroid) {
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        currentDeviceId = androidInfo.id; // Unique Hardware ID
      }
    } catch(e) {
      currentDeviceId = user.uid; // Fallback
    }

    var promoDoc = await FirebaseFirestore.instance.collection('app_config').doc('promos').get();
    if (promoDoc.exists && promoDoc['is_welcome_active'] == true) {
      promoPercentage = (promoDoc['welcome_discount'] as num).toDouble();

      // ১. চেক করবে ইউজারের কোনো আগের অর্ডার আছে কিনা
      var pastOrders = await FirebaseFirestore.instance.collection('orders').where('user_id', isEqualTo: user.uid).limit(1).get();
      
      // ২. চেক করবে এই ডিভাইসে আগে অফার নেওয়া হয়েছে কিনা
      var deviceUsed = await FirebaseFirestore.instance.collection('promo_devices').doc(currentDeviceId).get();

      if (pastOrders.docs.isEmpty && !deviceUsed.exists && currentDeviceId.isNotEmpty) {
        isWelcomePromoApplied = true;
        welcomePromoDiscount = (productTotal * promoPercentage) / 100;
      }
    }

    _updateGrandTotal();
    setState(() => isLoadingData = false);
  }

  Future<Map<String, dynamic>> _calculateChargeFromAPI(double sLat, double sLng) async {
    double baseFee = 60.0;
    if (userAddress == null) return {'fee': baseFee, 'dist': 'ঠিকানা নেই', 'time': ''};
    try {
      String apiKey = "AIzaSyC6C-fHPPbo5xdDDuNhEm4wDfVci9BZI0M"; 
      String url = "https://maps.googleapis.com/maps/api/distancematrix/json?origins=$sLat,$sLng&destinations=${userAddress!['latitude']},${userAddress!['longitude']}&key=$apiKey";
      var response = await http.get(Uri.parse(url));
      var data = json.decode(response.body);
      if (data['status'] == 'OK' && data['rows'][0]['elements'][0]['status'] == 'OK') {
        var element = data['rows'][0]['elements'][0];
        double km = element['distance']['value'] / 1000.0;
        var setDoc = await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').get();
        if (setDoc.exists) {
          var conf = setDoc.data()!;
          if (km <= conf['base_distance']) { baseFee = conf['base_charge'].toDouble(); } 
          else if (km <= conf['mid_distance']) baseFee = conf['mid_charge'].toDouble();
          else baseFee = conf['mid_charge'] + ((km - conf['mid_distance']) * conf['extra_per_km']);
        }
        return {'fee': baseFee, 'dist': element['distance']['text'], 'time': element['duration']['text']};
      }
    } catch (e) {}
    return {'fee': baseFee, 'dist': 'Unknown', 'time': ''};
  }

  void _updateGrandTotal() {
    double totalFees = shopDeliveryFees.values.fold(0.0, (sum, fee) => sum + fee);
    finalGrandTotal = productTotal + totalFees;
    
    // [NEW] ডিসকাউন্ট মাইনাস করা
    if (isWelcomePromoApplied) {
      finalGrandTotal -= welcomePromoDiscount;
    }
    
    if (useCoins && availableCoins > 0) {
      finalGrandTotal -= availableCoins;
    }
    
    if (finalGrandTotal < 0) finalGrandTotal = 0;
  }

  void _placeRealOrder() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || userAddress == null || checkoutItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে ডেলিভারি ঠিকানা যুক্ত করুন!'), backgroundColor: Colors.red));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      List<Map<String, dynamic>> itemsToOrder =[];
      Set<String> sellerIds = {}; 

      for (var item in checkoutItems) {
        sellerIds.add(item['seller_id'] ?? 'unknown');
        itemsToOrder.add({
          'product_id': item['product_id'] ?? item['id'],
          'product_name': item['product_name'],
          'price': item['price'],
          'quantity': item['quantity'],
          'seller_id': item['seller_id'] ?? 'unknown',
          'image_url': item['image_url'] ?? '',
          'selected_color': item['selected_color'] ?? '',
          'selected_size': item['selected_size'] ?? '',
        });
      }

      String secretPickupOTP = (1000 + math.Random().nextInt(9000)).toString(); 
      String initialStatus = selectedPayment == 'bKash' ? 'Processing' : 'Pending';

      await FirebaseFirestore.instance.collection('orders').add({
        'user_id': user.uid,
        'items': itemsToOrder,
        'total_amount': finalGrandTotal.toInt(),
        'payment_method': selectedPayment,
        'status': initialStatus, 
        'pickup_otp': secretPickupOTP, 
        'used_d_coins': useCoins ? availableCoins : 0, 
        
        // [NEW] প্রোমো ডাটা সেভ
        'welcome_promo_applied': isWelcomePromoApplied,
        'promo_discount_amount': isWelcomePromoApplied ? welcomePromoDiscount : 0,
        
        'order_date': FieldValue.serverTimestamp(),
        'shipping_name': userAddress!['shipping_name'],
        'shipping_phone': userAddress!['shipping_phone'],
        'shipping_address_text': userAddress!['shipping_address_text'],
        'customer_lat': userAddress!['latitude'],
        'customer_lng': userAddress!['longitude'],
      });

      // [NEW] জালিয়াতি রোধ: ডিভাইসটি ডাটাবেসে ব্লক লিস্টে ফেলে দেওয়া
      if (isWelcomePromoApplied && currentDeviceId.isNotEmpty) {
        await FirebaseFirestore.instance.collection('promo_devices').doc(currentDeviceId).set({
          'user_id': user.uid,
          'used_at': FieldValue.serverTimestamp()
        });
      }

      if (useCoins && availableCoins > 0) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({'d_coins': 0});
      }

        // অ্যাডমিনকে নোটিফিকেশন পাঠানো (New Order Alarm)
        if (initialStatus == 'Pending') {
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': 'New Order Received! 🛒',
            'message': '${userAddress!['shipping_name']} একটি নতুন অর্ডার করেছেন।',
            'topic': 'admins', 
            'type': 'new_order', // 🔴 এটি দেওয়ার কারণেই এডমিনের রিংটোন বাজবে!
            'data': {'screen': 'admin_orders'},
            'sent_at': FieldValue.serverTimestamp(),
          });
        } else {
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'New bKash Order Paid! 💰',
          'message': 'একটি বিকাশ পেমেন্ট অর্ডার রিসিভ হয়েছে (Auto Approved)।',
          'target_role': 'admin',
          'sent_at': FieldValue.serverTimestamp(),
        });
        
        for (String sId in sellerIds) {
          if (sId != 'unknown') {
            await FirebaseFirestore.instance.collection('notifications').add({
              'title': 'New Order Received! 📦',
              'message': 'আপনার একটি নতুন অর্ডার এসেছে। দয়া করে প্যাক করুন।',
              'target_user_id': sId,
              'sent_at': FieldValue.serverTimestamp(),
            });
          }
        }
      }

      for (var item in checkoutItems) {
        String? productId = item['product_id']; 
        if (productId != null && productId.isNotEmpty) {
          int orderQty = int.tryParse(item['quantity'].toString()) ?? 1;
          String sColor = item['selected_color'] ?? '';
          String sSize = item['selected_size'] ?? '';
          DocumentReference pRef = FirebaseFirestore.instance.collection('products').doc(productId);

          await FirebaseFirestore.instance.runTransaction((transaction) async {
            DocumentSnapshot pSnap = await transaction.get(pRef);
            if (pSnap.exists) {
              Map<String, dynamic> pData = pSnap.data() as Map<String, dynamic>;
              int currentTotalStock = int.tryParse(pData['stock'].toString()) ?? 0;
              List<dynamic> variants = pData['variants'] ??[];

              for (int i = 0; i < variants.length; i++) {
                if (variants[i]['color'] == sColor && variants[i]['size'] == sSize) {
                  int vStock = int.tryParse(variants[i]['stock'].toString()) ?? 0;
                  variants[i]['stock'] = (vStock - orderQty) >= 0 ? (vStock - orderQty) : 0;
                  break; 
                }
              }

              transaction.update(pRef, {
                'stock': (currentTotalStock - orderQty) >= 0 ? (currentTotalStock - orderQty) : 0,
                'sales_count': FieldValue.increment(orderQty), 
                'variants': variants
              });
            }
          });
        }
      }

      for (String docId in widget.selectedItemIds) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(docId).delete();
      }

      if (!mounted) return;
      Navigator.pop(context); 

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          contentPadding: const EdgeInsets.all(20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              const Icon(Icons.check_circle, color: Colors.green, size: 80),
              const SizedBox(height: 15),
              const Text('Order Successful! 🎉', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
              const SizedBox(height: 10),
              Text(
                initialStatus == 'Pending' 
                  ? 'আপনার অর্ডারটি সফলভাবে প্লেস হয়েছে। আমাদের প্রতিনিধি খুব দ্রুত কনফার্ম করবেন।'
                  : 'পেমেন্ট সফল! আপনার অর্ডারটি সরাসরি সেলারের কাছে প্যাকিংয়ের জন্য পাঠানো হয়েছে।', 
                textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)
              ),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false); Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage())); }, child: const Text('View Order', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () { Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false); }, child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                ],
              )
            ],
          ),
        )
      );

    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showDeliveryMethodSelector(String shopName, double currentFee) {
    Navigator.pop(context);
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 1,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFFEE4D2D), size: 28), onPressed: () => Navigator.pop(context)),
        title: const Text('Checkout', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 20)),
      ),
      body: isLoadingData 
      ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[CircularProgressIndicator(), SizedBox(height: 10), Text('Preparing your checkout...')]))
      : Column(
          children:[
            // [NEW] Welcome Promo Banner
            if (isWelcomePromoApplied)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.amber.shade100, border: const Border(bottom: BorderSide(color: Colors.amber))),
                child: Row(
                  children:[
                    const Icon(Icons.celebration, color: Colors.deepOrange),
                    const SizedBox(width: 10),
                    Expanded(child: Text('অভিনন্দন! আপনার প্রথম অর্ডারের জন্য ৳${welcomePromoDiscount.toStringAsFixed(0)} (${promoPercentage.toStringAsFixed(0)}%) স্পেশাল ডিসকাউন্ট দেওয়া হয়েছে!', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
              ),

            Expanded(
              child: ListView(
                children:[
                  InkWell(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddressListPage())),
                    child: Container(
                      color: Colors.white, padding: const EdgeInsets.all(15),
                      child: Row(children:[
                        Icon(Icons.location_on, color: shopeeOrange, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                          Text(userAddress != null ? '${userAddress!['shipping_name']} (${userAddress!['shipping_phone']})' : 'Delivery Address', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(userAddress != null ? userAddress!['shipping_address_text'] : 'Please update your delivery address to proceed.', style: TextStyle(color: userAddress != null ? Colors.black54 : Colors.redAccent, fontSize: 13)),
                        ])),
                        const Icon(Icons.chevron_right, color: Colors.black54),
                      ]),
                    ),
                  ),
                  Container(height: 3, width: double.infinity, decoration: const BoxDecoration(gradient: LinearGradient(colors:[Colors.redAccent, Colors.white, Colors.blueAccent, Colors.white], stops:[0.25, 0.25, 0.75, 0.75], tileMode: TileMode.repeated))),

                  ...groupedItems.entries.map((entry) {
                      String shopName = entry.key;
                      List<Map<String, dynamic>> items = entry.value;
                      double fee = shopDeliveryFees[shopName] ?? 0;
                      String method = shopDeliveryMethod[shopName] ?? 'Standard Delivery';
                      String info = shopDistanceInfo[shopName] ?? '';

                      return Container(
                        margin: const EdgeInsets.only(top: 10), color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:[
                            Padding(padding: const EdgeInsets.all(15), child: Row(children:[const Icon(Icons.storefront, size: 20, color: Colors.black87), const SizedBox(width: 8), Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))])),
                            const Divider(height: 1),
                            ...items.map((item) {
                                return Container(
                                  padding: const EdgeInsets.all(15), color: const Color(0xFFFAFAFA),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children:[
                                      Container(height: 60, width: 60, decoration: BoxDecoration(color: Colors.yellow[100], border: Border.all(color: Colors.grey.shade300)), child: item['image_url'].toString().isNotEmpty ? Image.network(item['image_url'], fit: BoxFit.cover) : null),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(item['product_name'], style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                                            const SizedBox(height: 15),
                                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text('৳${item['price']} ', style: TextStyle(color: shopeeOrange, fontSize: 14)), Text('x${item['quantity']}', style: const TextStyle(fontSize: 12, color: Colors.black54))])
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                );
                            }),
                            
                            Container(
                              margin: const EdgeInsets.fromLTRB(15, 10, 15, 15), padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFF1FDFB), border: Border.all(color: shopeeGreen), borderRadius: BorderRadius.circular(4)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, 
                                children:[
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text("রাস্তার দূরত্ব: $info", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)), const Icon(Icons.check_circle, size: 14, color: Colors.green)]),
                                  const SizedBox(height: 8),
                                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Row(children:[Icon(method == 'Standard Delivery' ? Icons.local_shipping : Icons.flash_on, color: method == 'Standard Delivery' ? shopeeGreen : Colors.orange, size: 18), const SizedBox(width: 8), Text(method, style: TextStyle(color: method == 'Standard Delivery' ? shopeeGreen : Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))]), Text(fee == 0 ? 'Free' : '৳${fee.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))]),
                                ]
                              ),
                            ),
                          ],
                        ),
                      );
                  }),
                  
                  if (availableCoins > 0)
                    Container(
                      margin: const EdgeInsets.only(top: 10), color: Colors.white, padding: const EdgeInsets.all(15),
                      child: Row(
                        children:[
                          Icon(Icons.monetization_on, color: Colors.amber.shade700),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                            const Text('Use D-Coins', style: TextStyle(fontWeight: FontWeight.bold)),
                            Text('You have $availableCoins coins (Save ৳$availableCoins)', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          ])),
                          Switch(
                            value: useCoins, 
                            activeThumbColor: Colors.amber.shade700,
                            onChanged: (val) {
                              setState(() {
                                useCoins = val;
                                _updateGrandTotal();
                              });
                            }
                          )
                        ],
                      ),
                    ),

                  // Payment Method Section
                  Container(
                    margin: const EdgeInsets.only(top: 10), color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Padding(padding: EdgeInsets.only(left: 15, bottom: 5), child: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold))),
                        
                        _buildPaymentOption('bKash', Icons.account_balance_wallet, Colors.pink, false),
                        const Divider(height: 1), 
                        
                        _buildPaymentOption('Cash on Delivery', Icons.local_shipping, Colors.teal, isCodDisabled),
                        
                        if (isCodDisabled)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade200)),
                              child: Row(
                                children:[
                                  const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _customerFailCount > 0 
                                      ? '⚠️ আপনার প্রোফাইলে "Delivery Failed" রেকর্ড থাকায় Cash on Delivery সাময়িকভাবে বন্ধ রাখা হয়েছে।'
                                      : '⚠️ প্রতিকূল আবহাওয়া বা সিস্টেম আপডেটের কারণে সাময়িকভাবে Cash on Delivery বন্ধ রয়েছে। দয়া করে ডিজিটাল পেমেন্ট ব্যবহার করুন।', 
                                      style: TextStyle(color: Colors.red.shade700, fontSize: 11)
                                    ),
                                  ),
                                ],
                              ),
                            )
                          )
                      ]
                    )
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            
            // Bottom Checkout Bar
            Container(
              decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children:[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children:[
                      RichText(text: TextSpan(children:[
                        const TextSpan(text: 'Total Payment ', style: TextStyle(color: Colors.black87, fontSize: 13)),
                        TextSpan(text: '৳${finalGrandTotal.toStringAsFixed(0)}', style: TextStyle(color: shopeeOrange, fontWeight: FontWeight.bold, fontSize: 18)),
                      ])),
                      if(useCoins && availableCoins > 0) Text('Coins Applied: -৳$availableCoins', style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
                      // [NEW] প্রোমো ব্যালেন্স দেখানো
                      if(isWelcomePromoApplied) Text('New User Discount: -৳${welcomePromoDiscount.toStringAsFixed(0)}', style: const TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(width: 15),
                  InkWell(
                    onTap: _placeRealOrder, 
                    child: Container(height: 60, width: 130, alignment: Alignment.center, color: shopeeOrange, child: const Text('Place Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                  )
                ],
              ),
            )
          ],
        ),
    );
  }

  Widget _buildPaymentOption(String title, IconData icon, Color iconColor, bool isDisabled) {
    return RadioListTile<String>(
      title: Row(
        children:[
          Icon(icon, color: isDisabled ? Colors.grey : iconColor), 
          const SizedBox(width: 15), 
          Text(title, style: TextStyle(fontSize: 14, color: isDisabled ? Colors.grey : Colors.black, decoration: isDisabled ? TextDecoration.lineThrough : null))
        ]
      ), 
      value: title, 
      groupValue: selectedPayment, 
      activeColor: const Color(0xFFEE4D2D), 
      onChanged: isDisabled ? null : (value) => setState(() => selectedPayment = value!),
    );
  }
}

// ==========================================
// ৩ নম্বর পেজ: Product Details (With Rocket Shake & Haptic Feedback)
// ==========================================
// [NEW] SingleTickerProviderStateMixin যুক্ত করা হলো এনিমেশন কন্ট্রোল করার জন্য
class ProductDetailsPage extends StatefulWidget {
  final QueryDocumentSnapshot product; 
  const ProductDetailsPage({super.key, required this.product});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> with SingleTickerProviderStateMixin {
  final GlobalKey _cartKey = GlobalKey();
  final GlobalKey _imageKey = GlobalKey();
  final GlobalKey _variantKey = GlobalKey(); 
  final GlobalKey _addToCartBtnKey = GlobalKey(); 
  
  late AnimationController _cartShakeController; // [NEW] কার্ট ঝাঁকুনির কন্ট্রোলার
  
  int _selectedImageIndex = 0; 
  bool _isDescExpanded = false; 
  bool _hasVariantError = false; 
  
  String? selectedColorName;
  String? selectedSizeName;
  String adminPhoneNumber = "01700000000"; 

  @override
  void initState() {
    super.initState();
    //[NEW] এনিমেশন কন্ট্রোলার চালু করা হলো
    _cartShakeController = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    
    _saveToRecentlyViewed(); 
    _fetchAdminPhoneNumber(); 
  }

  @override
  void dispose() {
    _cartShakeController.dispose(); // মেমরি বাঁচাতে এটি জরুরি
    super.dispose();
  }

  Future<void> _fetchAdminPhoneNumber() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('app_config').doc('store_details').get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          adminPhoneNumber = doc['support_phone']?.toString() ?? "01700000000";
        });
      }
    } catch (e) {}
  }

  // =====================================
  // [NEW] ফ্লাই এনিমেশন এবং কার্ট ঝাঁকুনি! 🚀
  // =====================================
  void runAddToCartAnimation() {
    RenderBox? startBox = _addToCartBtnKey.currentContext?.findRenderObject() as RenderBox?;
    RenderBox? cartBox = _cartKey.currentContext?.findRenderObject() as RenderBox?;
    if (startBox == null || cartBox == null) return;
    
    // বাটনের ঠিক মাঝখান থেকে শুরু হবে
    Offset startPos = startBox.localToGlobal(Offset(startBox.size.width / 2 - 20, 0));
    Offset cartPos = cartBox.localToGlobal(const Offset(10, 10));

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (context) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 900), // স্পিড পারফেক্ট করা হলো
          curve: Curves.easeOutCubic, 
          builder: (context, value, child) {
            double left = startPos.dx + (cartPos.dx - startPos.dx) * value;
            double top = startPos.dy + (cartPos.dy - startPos.dy) * value;
            
            double size = 45 * (1.0 - value);
            if (size < 15) size = 15;
            
            return Positioned(
              left: left, top: top, 
              child: Opacity(
                opacity: (1.0 - value).clamp(0.0, 1.0), // [FIXED] Opacity Error
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color.fromARGB(255, 252, 76, 23), 
                    shape: BoxShape.circle,
                    boxShadow:[BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))]
                  ),
                  child: Icon(Icons.shopping_bag, color: Colors.white, size: size),
                )
              )
            );
          },
        );
      },
    );
    Overlay.of(context).insert(entry);
    
    // শপিং ব্যাগটি কার্টে পৌঁছানোর ঠিক মুহূর্তে
    Future.delayed(const Duration(milliseconds: 900), () {
      entry?.remove();
      _cartShakeController.forward(from: 0.0); // কার্ট ঝাঁকুনি শুরু হবে
      HapticFeedback.heavyImpact(); // ফোন আপনার হাতে থপ করে কাঁপবে! (রকেট ইফেক্ট)
    });
  }

  void addToCart(BuildContext context, String imageUrl, int finalPrice, int currentStock, bool hasColors, bool hasSizes, {bool isBuyNow = false}) async {
    User? user = FirebaseAuth.instance.currentUser;
    
    if (user == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          contentPadding: const EdgeInsets.all(20),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children:[
              const Icon(Icons.lock_outline, size: 60, color: Colors.deepOrange),
              const SizedBox(height: 15),
              const Text('লগিন প্রয়োজন!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('অর্ডার করতে বা কার্টে অ্যাড করতে দয়া করে লগিন করুন।', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 25),
              Row(
                children:[
                  Expanded(child: OutlinedButton(style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () => Navigator.pop(context), child: const Text('Skip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage())); }, child: const Text('Login Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                ]
              )
            ],
          ),
        )
      );
      return; 
    }

    if ((hasColors && selectedColorName == null) || (hasSizes && selectedSizeName == null)) { 
      if (_variantKey.currentContext != null) {
        Scrollable.ensureVisible(_variantKey.currentContext!, alignment: 0.5, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
      setState(() => _hasVariantError = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _hasVariantError = false);
      });
      return; 
    }

    if (currentStock < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দুঃখিত, এই প্রোডাক্টটি স্টকে নেই!'), backgroundColor: Colors.red));
      return;
    }

    // [FIXED] এনিমেশনে আর ইমেজ পাঠানো হচ্ছে না, সরাসরি ব্যাগ উড়বে!
    if (!isBuyNow) runAddToCartAnimation(); 

    var cartRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart');
    var existingItem = await cartRef
        .where('product_id', isEqualTo: widget.product.id)
        .where('selected_color', isEqualTo: selectedColorName ?? '')
        .where('selected_size', isEqualTo: selectedSizeName ?? '')
        .get();

    String cartDocId = '';
    int currentQty = 1;

    if (existingItem.docs.isNotEmpty) {
      cartDocId = existingItem.docs.first.id;
      if (isBuyNow) {
        currentQty = 1;
        await cartRef.doc(cartDocId).update({'quantity': 1});
      } else {
        currentQty = (existingItem.docs.first.data())['quantity'] + 1;
        await cartRef.doc(cartDocId).update({'quantity': FieldValue.increment(1)});
      }
    } else {
      Map<String, dynamic> pData = widget.product.data() as Map<String, dynamic>;
      var newDoc = await cartRef.add({
        'product_id': widget.product.id, 
        'product_name': pData['product_name'],
        'price': finalPrice, 
        'original_price': pData['original_price'] ?? pData['price'],
        'quantity': 1,
        'image_url': imageUrl,
        'selected_color': selectedColorName ?? '',
        'selected_size': selectedSizeName ?? '',
        'max_stock': currentStock, 
        'seller_id': pData.containsKey('seller_id') ? pData['seller_id'] : 'unknown',
        'added_at': FieldValue.serverTimestamp(),
      });
      cartDocId = newDoc.id;
    }

    if (!mounted) return;

    if (isBuyNow) { 
      int freeShippingThreshold = 0;
      try {
        DocumentSnapshot settingsDoc = await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').get();
        if (settingsDoc.exists) freeShippingThreshold = ((settingsDoc.data() as Map<String, dynamic>)['free_shipping_threshold'] as num?)?.toInt() ?? 0;
      } catch (e) {}

      Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(grandTotal: finalPrice * currentQty, selectedItemIds:[cartDocId], freeShippingThreshold: freeShippingThreshold))); 
    } 
  }

  void _saveToRecentlyViewed() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var recentRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('recently_viewed');
    await recentRef.doc(widget.product.id).set({'product_id': widget.product.id, 'category': widget.product['category'], 'viewed_at': FieldValue.serverTimestamp()}, SetOptions(merge: true));
  }

  Widget _buildMiniProductCard(QueryDocumentSnapshot doc, {bool isGrid = false}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    String firstImage = images.isNotEmpty ? images[0]?.toString() ?? '' : '';
    
    String displayPrice = data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty ? data['discount_price'].toString() : data['price'].toString();
    int curP = int.tryParse(displayPrice) ?? 0;
    int origP = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int discount = origP > curP ? (((origP - curP) / origP) * 100).round() : 0;

    return InkWell(
      onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: doc))),
      child: Container(
        width: isGrid ? null : 140, margin: isGrid ? null : const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Expanded(child: Stack(children:[Container(width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))), child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)), if (discount > 0) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomLeft: Radius.circular(8))), child: Text('-$discount%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold))))])),
            Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(data['product_name']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)), const SizedBox(height: 4), Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14))]))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = widget.product.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    List<dynamic> variants = data.containsKey('variants') ? data['variants'] :[];
    String unit = data['variant_unit']?.toString() ?? '';
    
    int basePrice = int.tryParse(data['price']?.toString() ?? '0') ?? 0;
    int originalPrice = int.tryParse(data['original_price']?.toString() ?? '0') ?? 0;
    int totalStock = int.tryParse(data['stock']?.toString() ?? '0') ?? 0;

    Set<String> uniqueColors = {};
    Set<String> uniqueSizes = {};
    
    if (variants.isNotEmpty) {
      if (variants.length > 1 || (variants[0]['color'] != 'Default' || variants[0]['size'] != 'Default')) {
        for (var v in variants) {
          if (v['color'] != 'Default') uniqueColors.add(v['color'].toString());
          if (v['size'] != 'Default') uniqueSizes.add(v['size'].toString());
        }
      } else {
        selectedColorName = 'Default';
        selectedSizeName = 'Default';
      }
    }
    
    bool hasColors = uniqueColors.isNotEmpty;
    bool hasSizes = uniqueSizes.isNotEmpty;
    bool hasRealVariants = hasColors || hasSizes;

    int finalCurrentPrice = basePrice;
    int currentDisplayedStock = totalStock;
    String? activeColorImage;

    if (hasRealVariants) {
      try {
         var match = variants.firstWhere((v) => 
            (!hasColors || v['color'] == selectedColorName) && 
            (!hasSizes || v['size'] == selectedSizeName)
         , orElse: () => {});

         if (match.isNotEmpty) {
           if ((!hasColors || selectedColorName != null) && (!hasSizes || selectedSizeName != null)) {
              finalCurrentPrice = basePrice + (int.tryParse(match['price'].toString()) ?? 0);
              currentDisplayedStock = int.tryParse(match['stock'].toString()) ?? 0;
           } else if (selectedColorName != null || selectedSizeName != null) {
              int tempStock = 0;
              for(var vx in variants) {
                if ((selectedColorName != null && vx['color'] == selectedColorName) || (selectedSizeName != null && vx['size'] == selectedSizeName)) {
                   tempStock += (int.tryParse(vx['stock'].toString()) ?? 0);
                }
              }
              currentDisplayedStock = tempStock;
           }
         }
         if (selectedColorName != null) {
            var colorMatch = variants.firstWhere((v) => v['color'] == selectedColorName && v['color_image_url'] != null, orElse: () => {});
            if(colorMatch.isNotEmpty) activeColorImage = colorMatch['color_image_url']?.toString();
         }
      } catch(e){}
    }

    String firstFallbackImage = '';
    if (images.isNotEmpty && images.length > _selectedImageIndex) {
      firstFallbackImage = images[_selectedImageIndex]?.toString() ?? '';
    }
    String mainImage = activeColorImage ?? firstFallbackImage;

    int finalOriginalPrice = originalPrice > basePrice ? (originalPrice + (finalCurrentPrice - basePrice)) : 0;
    int discountPercent = finalOriginalPrice > finalCurrentPrice ? (((finalOriginalPrice - finalCurrentPrice) / finalOriginalPrice) * 100).round() : 0;

    String errorMsg = 'দয়া করে সঠিক অপশন সিলেক্ট করুন';
    if (hasColors && selectedColorName == null && hasSizes && selectedSizeName == null) {
        errorMsg = 'দয়া করে সাইজ ও কালার সিলেক্ট করুন';
    } else if (hasColors && selectedColorName == null) {
        errorMsg = 'দয়া করে কালার সিলেক্ট করুন';
    } else if (hasSizes && selectedSizeName == null) {
        errorMsg = 'দয়া করে সাইজ সিলেক্ট করুন';
    }

    String productCode = data['sku']?.toString() ?? 'N/A';

    return Scaffold(
      backgroundColor: Colors.grey.shade100, 
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20), onPressed: () => Navigator.pop(context)),
        actions:[
          // =====================================
          // [RESTORED] Wishlist (Love) Button
          // =====================================
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser != null ? FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('wishlist').doc(widget.product.id).snapshots() : const Stream<DocumentSnapshot>.empty(),
            builder: (context, snapshot) {
              bool isWished = snapshot.hasData && snapshot.data!.exists;
              return IconButton(
                icon: Icon(isWished ? Icons.favorite : Icons.favorite_border, color: isWished ? Colors.red : Colors.black),
                onPressed: () async {
                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে লগইন করুন!')));
                    return;
                  }
                  var ref = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wishlist').doc(widget.product.id);
                  if (isWished) { 
                    await ref.delete(); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Wishlist 💔'))); 
                  } else { 
                    await ref.set(widget.product.data() as Map<String, dynamic>); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Wishlist ❤️'))); 
                  }
                },
              );
            },
          ),
          // 🔴 শেয়ার বাটন (IMO, FB, WhatsApp সব অপশন আসবে)
          IconButton(
            icon: const Icon(Icons.share, color: Colors.black), 
            onPressed: () {
              String shareText = 'D Shop এ অসাধারণ একটি প্রোডাক্ট দেখলাম!\n\n'
                               'পণ্য: ${data['product_name']}\n'
                               'দাম: ৳$finalCurrentPrice\n'
                               'কোড: $productCode\n\n'
                               'অ্যাপটি ডাউনলোড করে এখনই অর্ডার করুন!';
              Share.share(shareText);
            }
          ), 
          
          // =====================================
          // [NEW] Cart Icon with Shake Animation
          // =====================================
          AnimatedBuilder(
            animation: _cartShakeController,
            builder: (context, child) {
              // ডানে-বামে ঝাঁকুনির জন্য math.sin ব্যবহার করা হয়েছে
              final dx = math.sin(_cartShakeController.value * math.pi * 4) * 4; 
              return Transform.translate(
                offset: Offset(dx, 0),
                child: child,
              );
            },
            child: IconButton(
              key: _cartKey, 
              icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black), 
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage()))
            ),
          )
        ],
      ),
      body: Column(
        children:[
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  Container(
                    color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        Center(child: Container(height: 300, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: mainImage.isNotEmpty ? Image.network(mainImage, fit: BoxFit.contain) : const Icon(Icons.image, size: 100, color: Colors.grey))),
                        const SizedBox(height: 15),
                        if (images.length > 1) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: images.length, itemBuilder: (context, index) { bool isSelected = _selectedImageIndex == index; return InkWell(onTap: () => setState(() { _selectedImageIndex = index; activeColorImage = null; }), child: Container(margin: const EdgeInsets.only(right: 10), height: 60, width: 60, decoration: BoxDecoration(border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 1.5), borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(images[index]?.toString() ?? ''), fit: BoxFit.cover)))); })),
                        const SizedBox(height: 20),
                        
                        Text(data['product_name']?.toString() ?? 'Product Name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 15),

                        // =====================================
                        // [RESTORED] সহজে কল/মেসেজ করে অর্ডার করার অপশন
                        // =====================================
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                              const Text('সহজে অর্ডার করতে কল বা মেসেজ করুন:', style: TextStyle(fontSize: 16, color: Color.fromARGB(255, 3, 46, 238), fontWeight: FontWeight.bold)),
                              const SizedBox(height: 10),
                              Row(
                                children:[
                                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.grey.shade300)), child: Text('Code: $productCode', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87))),
                                  const Spacer(),
                                  InkWell(onTap: () async { final Uri url = Uri.parse('tel:$adminPhoneNumber'); if (await canLaunchUrl(url)) await launchUrl(url); }, child: Container(width: 32, height: 32, decoration: const BoxDecoration(color: Colors.green, shape: BoxShape.circle), child: const Icon(Icons.call, size: 18, color: Colors.white))),
                                  const SizedBox(width: 10),
                                  // 🔴 হোয়াটসঅ্যাপ ফিক্সড লজিক
                                InkWell(
                                  onTap: () async {
                                    String msg = "হ্যালো, আমি এই প্রোডাক্টটি অর্ডার করতে চাই।\nপ্রোডাক্ট কোড: $productCode\nনাম: ${data['product_name']}";
                                    
                                    // নাম্বার থেকে স্পেস বা + সরিয়ে শুধু 88 দিয়ে শুরু করা হচ্ছে
                                    String cleanPhone = adminPhoneNumber.replaceAll('+', '').replaceAll('-', '').replaceAll(' ', '');
                                    if (cleanPhone.startsWith('0')) {
                                      cleanPhone = '88$cleanPhone';
                                    }

                                    final Uri waUrl = Uri.parse("https://wa.me/$cleanPhone?text=${Uri.encodeComponent(msg)}");

                                    if (await canLaunchUrl(waUrl)) {
                                      await launchUrl(waUrl, mode: LaunchMode.externalApplication);
                                    } else {
                                      if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('WhatsApp ওপেন করা যাচ্ছে না!')));
                                    }
                                  },
                                  child: ClipOval(
                                    child: Image.asset('assets/icons/whatsapp.png', width: 43, height: 43, fit: BoxFit.cover),
                                  ),
                                ),
                                

                                const SizedBox(width: 10),

                                InkWell(
                                  onTap: () async {
                                    await Clipboard.setData(ClipboardData(text: adminPhoneNumber));

                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'অফিস নাম্বার ($adminPhoneNumber) কপি হয়েছে! ইমুতে গিয়ে মেসেজ দিন।'),
                                          backgroundColor: Colors.blue,
                                        ),
                                      );
                                    }
                                  },
                                  child: ClipOval(
                                    child: Image.asset(
                                      'assets/icons/imo.png', // ✅ আপনার ফোল্ডার path
                                      width: 43,
                                      height: 43,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                                ],
                              ),
                            ]
                          )
                        ),
                        const SizedBox(height: 15),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end,
                          children:[
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:[
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children:[
                                    Text('৳$finalCurrentPrice', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                    const SizedBox(width: 8),
                                    if (discountPercent > 0) ...[Text('৳$finalOriginalPrice', style: const TextStyle(fontSize: 16, decoration: TextDecoration.lineThrough, color: Colors.grey)), const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(3)), child: Text('-$discountPercent%', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12)))],
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Row(children: List.generate(5, (index) => Icon(Icons.star, color: Colors.grey.shade400, size: 18))),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children:[
                                Text('Stock: $currentDisplayedStock', style: TextStyle(color: currentDisplayedStock > 0 ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                                if (currentDisplayedStock == 0) Text('Out of Stock', style: TextStyle(color: Colors.red.shade400, fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10), 
                  
                  if (hasRealVariants)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      key: _variantKey, width: double.infinity, padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: _hasVariantError ? Colors.red.shade50 : Colors.white,
                        border: Border.all(color: _hasVariantError ? Colors.red.shade300 : Colors.transparent, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          if (_hasVariantError)
                            Padding(padding: const EdgeInsets.only(bottom: 15), child: Row(mainAxisAlignment: MainAxisAlignment.center, children:[const Icon(Icons.warning, color: Colors.red, size: 18), const SizedBox(width: 5), Text(errorMsg, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),])),

                          if(hasColors) ...[
                            const Text('Select Color', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 10), 
                            Wrap(spacing: 10, runSpacing: 10, children: uniqueColors.map((colorName) {
                                bool isSelected = selectedColorName == colorName;
                                return InkWell(
                                  onTap: () => setState(() => selectedColorName = isSelected ? null : colorName),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                    decoration: BoxDecoration(color: isSelected ? Colors.deepOrange.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 1.5), borderRadius: BorderRadius.circular(5)), 
                                    child: Text(colorName, style: TextStyle(color: isSelected ? Colors.deepOrange : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))
                                  )
                                );
                              }).toList()
                            ), 
                            const SizedBox(height: 20)
                          ],
                          if(hasSizes) ...[
                            Text('Select Option ($unit)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 10), 
                            Wrap(spacing: 10, runSpacing: 10, children: uniqueSizes.map((sizeName) {
                                bool isSelected = selectedSizeName == sizeName;
                                return InkWell(
                                  onTap: () => setState(() => selectedSizeName = isSelected ? null : sizeName),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                    decoration: BoxDecoration(color: isSelected ? Colors.teal.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.teal : Colors.grey.shade300, width: 1.5), borderRadius: BorderRadius.circular(5)), 
                                    child: Text(sizeName, style: TextStyle(color: isSelected ? Colors.teal : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))
                                  )
                                );
                              }).toList()
                            ), 
                          ],
                        ],
                      ),
                    ),
                  if (hasRealVariants) const SizedBox(height: 10),

                  Container(
                    color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Row(
                      children:[
                        CircleAvatar(radius: 25, backgroundColor: Colors.teal.shade50, child: const Icon(Icons.storefront, color: Colors.teal, size: 28)), const SizedBox(width: 15),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection('users').doc(data['seller_id']?.toString() ?? '').get(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data!.exists) {
                                var shopData = snapshot.data!.data() as Map<String, dynamic>;
                                String shopName = shopData['shop_name']?.toString() ?? shopData['name']?.toString() ?? 'Unknown Shop';
                                return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis), Row(children: const[Icon(Icons.verified, color: Colors.green, size: 14), SizedBox(width: 4), Text('Verified Shop', style: TextStyle(color: Colors.green, fontSize: 12))])]);
                              }
                              return const Text('Loading shop info...', style: TextStyle(color: Colors.grey, fontSize: 12));
                            }
                          ),
                        ),
                        OutlinedButton(onPressed: () { if (data['seller_id'] != null) { Navigator.push(context, MaterialPageRoute(builder: (context) => ShopPage(sellerId: data['seller_id']))); } }, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange), foregroundColor: Colors.deepOrange), child: const Text('View Shop'))
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  Container(
                    width: double.infinity, color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('PRODUCT DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
                        InkWell(
                          onTap: () => setState(() => _isDescExpanded = !_isDescExpanded),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                              Text(data['description']?.toString() ?? 'No description available.', style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5), maxLines: _isDescExpanded ? null : 4, overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis),
                              const SizedBox(height: 5),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children:[Text(_isDescExpanded ? 'Show Less' : 'Read More', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)), Icon(_isDescExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.teal)])
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  if (data['seller_id'] != null)
                    Container(
                      color: Colors.white, padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('MORE FROM THIS SHOP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), Text('See All >', style: TextStyle(color: Colors.deepOrange.shade400, fontSize: 12))]),
                          const SizedBox(height: 15),
                          SizedBox(
                            height: 180,
                            child: StreamBuilder(
                              stream: FirebaseFirestore.instance.collection('products').where('seller_id', isEqualTo: data['seller_id']).where('status', isEqualTo: 'approved').limit(10).snapshots(),
                              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                                 if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                                 var docs = snapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                                 if (docs.isEmpty) return const Text('No other products from this shop.', style: TextStyle(color: Colors.grey));
                                 return ListView.builder(scrollDirection: Axis.horizontal, itemCount: docs.length, itemBuilder: (context, index) => _buildMiniProductCard(docs[index]));
                              }
                            )
                          )
                        ]
                      )
                    ),
                  const SizedBox(height: 10),

                  // =====================================
                  // [UPDATED] Similar Products & Smart Recommendations
                  // =====================================
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('products')
                        .where('category', isEqualTo: data['category'])
                        .where('status', isEqualTo: 'approved')
                        .limit(10).snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var similarDocs = snapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                      
                      // যদি একই ক্যাটাগরির সিমিলার প্রোডাক্ট থাকে
                      if (similarDocs.isNotEmpty) {
                        return Container(
                          color: Colors.white, padding: const EdgeInsets.all(15),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children:[
                               const Text('SIMILAR PRODUCTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                               const SizedBox(height: 15),
                               GridView.builder(
                                 shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
                                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10), 
                                 itemCount: similarDocs.length, 
                                 itemBuilder: (context, index) => _buildMiniProductCard(similarDocs[index], isGrid: true)
                               )
                            ]
                          )
                        );
                      } 
                      // যদি সিমিলার প্রোডাক্ট না থাকে, তবে ইউজারের হিস্ট্রি চেক করে পছন্দের প্রোডাক্ট দেখাবে
                      else {
                        User? currentUser = FirebaseAuth.instance.currentUser;
                        if (currentUser == null) return const SizedBox.shrink(); 
                        
                        return StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('recently_viewed').orderBy('viewed_at', descending: true).limit(3).snapshots(),
                          builder: (context, recentSnap) {
                            if (!recentSnap.hasData || recentSnap.data!.docs.isEmpty) return const SizedBox.shrink();
                            
                            List<String> preferredCategories =[];
                            for (var doc in recentSnap.data!.docs) {
                              if ((doc.data() as Map).containsKey('category') && doc['category'] != null) {
                                preferredCategories.add(doc['category']);
                              }
                            }
                            if (preferredCategories.isEmpty) return const SizedBox.shrink();
                            
                            return StreamBuilder<QuerySnapshot>(
                              stream: FirebaseFirestore.instance.collection('products')
                                  .where('status', isEqualTo: 'approved')
                                  .where('category', whereIn: preferredCategories)
                                  .limit(10).snapshots(),
                              builder: (context, recSnapshot) {
                                if (!recSnapshot.hasData) return const SizedBox.shrink();
                                var recDocs = recSnapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                                if (recDocs.isEmpty) return const SizedBox.shrink();
                                
                                return Container(
                                  color: Colors.white, padding: const EdgeInsets.all(15),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children:[
                                       const Text('RECOMMENDED FOR YOU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.deepOrange)),
                                       const SizedBox(height: 15),
                                       GridView.builder(
                                         shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), 
                                         gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10), 
                                         itemCount: recDocs.length, 
                                         itemBuilder: (context, index) => _buildMiniProductCard(recDocs[index], isGrid: true)
                                       )
                                    ]
                                  )
                                );
                              }
                            );
                          }
                        );
                      }
                    }
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          
          Container(
            padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, boxShadow:[BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, -5))]),
            child: Row(
              children:[
                Expanded(
                  key: _addToCartBtnKey,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: currentDisplayedStock > 0 ? Colors.deepOrange : Colors.grey, padding: const EdgeInsets.symmetric(vertical: 15)), 
                    onPressed: currentDisplayedStock > 0 ? () => addToCart(context, mainImage, finalCurrentPrice, currentDisplayedStock, hasColors, hasSizes, isBuyNow: false) : null, 
                    child: const Text('ADD TO CART', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  )
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: currentDisplayedStock > 0 ? Colors.teal : Colors.grey, padding: const EdgeInsets.symmetric(vertical: 15)), 
                    onPressed: currentDisplayedStock > 0 ? () => addToCart(context, mainImage, finalCurrentPrice, currentDisplayedStock, hasColors, hasSizes, isBuyNow: true) : null, 
                    child: const Text('BUY NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  )
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// ২ নম্বর পেজ: Home Page (With Analytics Engine)
// ==========================================
class ShopeeHome extends StatefulWidget {
  const ShopeeHome({super.key});

  @override
  State<ShopeeHome> createState() => _ShopeeHomeState();
}

class _ShopeeHomeState extends State<ShopeeHome> {
  late PageController _bannerController; 
  int _currentBannerPage = 0; 
  Timer? _bannerTimer; 
  String searchQuery = '';
  String selectedCategoryFilter = ''; 
  final TextEditingController searchController = TextEditingController();

  final String algoliaAppId = 'WULDWCKKQ3'; 
  final String algoliaSearchKey = '59964acedc064ab0f9fcbafd2b567aec'; 

  List<Map<String, dynamic>> algoliaSearchResults =[];
  bool isSearchingAlgolia = false;

  // =====================================
  // [NEW] User Behavior Analytics Logger 🧠
  // =====================================
  Future<void> _logUserActivity(String action, String details) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || details.isEmpty) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('analytics').add({
        'action': action,
        'details': details,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint("Analytics Error: $e");
    }
  }

  Future<void> _performAlgoliaSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        algoliaSearchResults.clear();
        isSearchingAlgolia = false;
      });
      return;
    }

    setState(() => isSearchingAlgolia = true);
    
    // [NEW] ইউজারের সার্চ রেকর্ড সেভ করা হচ্ছে
    _logUserActivity('search', query);

    try {
      String url = 'https://$algoliaAppId-dsn.algolia.net/1/indexes/products/query';
      var response = await http.post(
        Uri.parse(url),
        headers: {'X-Algolia-Application-Id': algoliaAppId, 'X-Algolia-API-Key': algoliaSearchKey, 'Content-Type': 'application/json; charset=UTF-8'},
        body: json.encode({'params': 'query=$query'}),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        List<dynamic> hits = data['hits'];
        setState(() {
          algoliaSearchResults = hits.map((hit) => Map<String, dynamic>.from(hit)).toList();
          isSearchingAlgolia = false;
        });
      } else {
        setState(() => isSearchingAlgolia = false);
      }
    } catch (e) {
      setState(() => isSearchingAlgolia = false);
    }
  }

  final List<Map<String, dynamic>> staticCategories =[
    {'name': 'Fashion', 'icon': Icons.checkroom, 'color': Colors.pink}, 
    {'name': 'Electronics', 'icon': Icons.tv, 'color': Colors.blue},
    {'name': 'Mobiles', 'icon': Icons.smartphone, 'color': Colors.green}, 
    {'name': 'Home Decor', 'icon': Icons.chair, 'color': Colors.orange},
    {'name': 'Beauty', 'icon': Icons.face_retouching_natural, 'color': Colors.purple}, 
    {'name': 'Watches', 'icon': Icons.watch, 'color': Colors.teal},
    {'name': 'Baby & Toys', 'icon': Icons.child_friendly, 'color': Colors.amber}, 
    {'name': 'Groceries', 'icon': Icons.local_grocery_store, 'color': Colors.lightGreen},
    {'name': 'Automotive', 'icon': Icons.directions_car, 'color': Colors.red}, 
    {'name': 'Women\'s Bags', 'icon': Icons.shopping_bag, 'color': Colors.deepPurple},
    {'name': 'Men\'s Wallets', 'icon': Icons.account_balance_wallet, 'color': Colors.brown}, 
    {'name': 'Muslim Fashion', 'icon': Icons.mosque, 'color': Colors.indigo},
    {'name': 'Games & Hobbies', 'icon': Icons.sports_esports, 'color': Colors.cyan}, 
    {'name': 'Computers', 'icon': Icons.computer, 'color': Colors.blueGrey},
    {'name': 'Sports & Outdoor', 'icon': Icons.sports_soccer, 'color': Colors.deepOrange}, 
    {'name': 'Men Shoes', 'icon': Icons.directions_run, 'color': Colors.indigoAccent},
    {'name': 'Cameras', 'icon': Icons.camera_alt, 'color': Colors.blueAccent}, 
    {'name': 'Travel & Luggage', 'icon': Icons.luggage, 'color': Colors.tealAccent.shade700},
  ];

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(initialPage: 0);
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_bannerController.hasClients) {
        _bannerController.nextPage(duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel(); 
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    double screenWidth = MediaQuery.of(context).size.width;
    int gridColumns = screenWidth > 1000 ? 5 : (screenWidth > 700 ? 4 : (screenWidth > 500 ? 3 : 2));

    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, elevation: 0,
        title: const Text('D Shop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions:[
          IconButton(icon: const Icon(Icons.notifications_active, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerNotificationPage()))),
          IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())))
        ],
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
                  if (snapshot.hasData && snapshot.data!.exists) return Text((snapshot.data!.data() as Map<String, dynamic>)['name'] ?? 'Customer', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                  return const Text('Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                },
              ),
              accountEmail: Text(currentUser?.phoneNumber ?? currentUser?.email ?? 'No info'),
              currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Colors.deepOrange)),
            ),
            ListTile(leading: const Icon(Icons.home), title: const Text('Home'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.history), title: const Text('My Orders'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage()))),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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
          ],
        ),
      ),
      
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200), 
          child: Container(
            color: Colors.white, 
            child: Column(
              children:[
                Container(
                  color: Colors.deepOrange, padding: const EdgeInsets.fromLTRB(15, 0, 15, 15), 
                  child: Container(
                    height: 45, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), 
                    child: TextField(
                      controller: searchController,
                      onChanged: (value) {
                         setState(() => searchQuery = value.toLowerCase().trim());
                         //[NEW] ২ ক্যারেক্টারের বেশি হলে অ্যানালিটিক্সে সেভ করবে
                         if (searchQuery.length > 2) _logUserActivity('search', searchQuery);
                      },
                      decoration: InputDecoration(hintText: 'Search for products...', prefixIcon: const Icon(Icons.search, color: Colors.grey), suffixIcon: searchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, color: Colors.grey), onPressed: () { searchController.clear(); setState(() => searchQuery = ''); }) : const Icon(Icons.qr_code_scanner, color: Colors.grey), border: InputBorder.none, contentPadding: const EdgeInsets.only(top: 10))
                    )
                  )
                ),
                
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        if (searchQuery.isEmpty && selectedCategoryFilter.isEmpty) ...[
                          StreamBuilder<DocumentSnapshot>(
                            stream: FirebaseFirestore.instance.collection('app_config').doc('default_banner').snapshots(),
                            builder: (context, configSnap) {
                              String defaultBgUrl = '';
                              if (configSnap.hasData && configSnap.data!.exists) {
                                defaultBgUrl = (configSnap.data!.data() as Map<String, dynamic>)['image_url'] ?? '';
                              }

                              return StreamBuilder(
                                stream: FirebaseFirestore.instance.collection('banners').snapshots(), 
                                builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                                  if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                    var activeDocs = snapshot.data!.docs.where((doc) => (doc.data() as Map<String, dynamic>)['isActive'] ?? true).toList();
                                    if (activeDocs.isEmpty) return _buildDefaultBanner(); 

                                    return SizedBox(
                                      height: 160,
                                      child: Stack(
                                        children: [
                                          // 🟢 লেয়ার ১: এডমিনের সেট করা ব্যাকগ্রাউন্ড ইমেজ (সাদা স্ক্রিন ঢাকবে)
                                          Container(
                                            margin: const EdgeInsets.all(15),
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade200, // ছবি না থাকলে হালকা গ্রে দেখাবে
                                              borderRadius: BorderRadius.circular(10),
                                              image: defaultBgUrl.isNotEmpty ? DecorationImage(image: NetworkImage(defaultBgUrl), fit: BoxFit.cover) : null,
                                            ),
                                            child: defaultBgUrl.isEmpty ? const Center(child: Icon(Icons.image, color: Colors.grey, size: 40)) : null,
                                          ),

                                          // 🟢 লেয়ার ২: আসল ব্যানারগুলো (ডাউনলোড হতে হতে নিচের ছবিটা দেখা যাবে)
                                          PageView.builder(
                                            controller: _bannerController,
                                            itemBuilder: (context, index) {
                                              int realIndex = index % activeDocs.length; 
                                              return Container(
                                                margin: const EdgeInsets.all(15),
                                                child: ClipRRect(
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Image.network(
                                                    activeDocs[realIndex]['image_url'],
                                                    fit: BoxFit.cover,
                                                    width: double.infinity,
                                                    loadingBuilder: (context, child, loadingProgress) {
                                                      // যতক্ষণ লোড হবে, এটি স্বচ্ছ (SizedBox) থাকবে, তাই নিচের ব্যাকগ্রাউন্ড দেখা যাবে!
                                                      if (loadingProgress == null) return child;
                                                      return const SizedBox(); 
                                                    },
                                                  )
                                                ),
                                              );
                                            },
                                            onPageChanged: (index) => _currentBannerPage = index,
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                  return _buildDefaultBanner(); 
                                },
                              );
                            }
                          ),

                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('categories').snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              return SizedBox(
                                height: 125, 
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10),
                                  itemCount: (snapshot.hasData && snapshot.data!.docs.isNotEmpty) ? snapshot.data!.docs.length : staticCategories.length,
                                  itemBuilder: (context, index) {
                                    if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                      var cat = snapshot.data!.docs[index];
                                      return _buildDynamicCategory(cat['name'], cat['image_url']);
                                    }
                                    var cat = staticCategories[index];
                                    return _buildStaticCategory(cat['name'], cat['icon'], cat['color']);
                                  },
                                ),
                              );
                            }
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), 
                            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(5)), child: const Text('FLASH SALE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))), const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey)])
                          ),

                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').where('is_flash_sale', isEqualTo: true).snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                return SizedBox(height: 180, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: snapshot.data!.docs.length, itemBuilder: (context, index) => _buildProductCardFirebase(context, snapshot.data!.docs[index], isHorizontal: true)));
                              }
                              return const SizedBox.shrink(); 
                            }
                          ),
                        ],

                        StreamBuilder(
                          stream: currentUser != null ? FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('recently_viewed').orderBy('viewed_at', descending: true).limit(3).snapshots() : const Stream<QuerySnapshot>.empty(),
                          builder: (context, AsyncSnapshot<QuerySnapshot> recentSnapshot) {
                            bool hasHistory = recentSnapshot.hasData && recentSnapshot.data!.docs.isNotEmpty;
                            List<String> preferredCategories =[];
                            if (hasHistory) {
                              for (var doc in recentSnapshot.data!.docs) {
                                if ((doc.data() as Map<String, dynamic>).containsKey('category')) preferredCategories.add(doc['category']);
                              }
                            }

                            return StreamBuilder(
                              stream: FirebaseFirestore.instance.collection('products').orderBy('timestamp', descending: true).limit(30).snapshots(),
                              builder: (context, AsyncSnapshot<QuerySnapshot> prodSnapshot) {
                                if (prodSnapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()));
                                if (!prodSnapshot.hasData || prodSnapshot.data!.docs.isEmpty) return const SizedBox.shrink();

                                var docs = prodSnapshot.data!.docs.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'approved').toList();

                                if (searchQuery.isNotEmpty) {
                                  docs = docs.where((doc) {
                                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                    String name = data['product_name'].toString().toLowerCase();
                                    List<dynamic> tags = data.containsKey('search_tags') ? data['search_tags'] :[];
                                    if (name.contains(searchQuery)) return true;
                                    for (var tag in tags) { if (tag.toString().toLowerCase().contains(searchQuery)) return true; }
                                    return false; 
                                  }).toList();
                                }

                                if (selectedCategoryFilter.isNotEmpty) {
                                  docs = docs.where((doc) => (doc.data() as Map<String, dynamic>)['category'] == selectedCategoryFilter).toList();
                                }

                                bool isSearchingOrFiltering = searchQuery.isNotEmpty || selectedCategoryFilter.isNotEmpty;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children:[
                                    Padding(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text(searchQuery.isNotEmpty ? 'SEARCH RESULTS' : (selectedCategoryFilter.isNotEmpty ? '$selectedCategoryFilter PRODUCTS' : 'NEW PRODUCTS'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), if(!isSearchingOrFiltering) const Text('See all', style: TextStyle(color: Colors.deepOrange, fontSize: 14))])),
                                    if (isSearchingOrFiltering || !hasHistory)
                                      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: docs.length, itemBuilder: (context, index) => _buildProductCardFirebase(context, docs[index]))
                                    else
                                      SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: docs.length > 10 ? 10 : docs.length, itemBuilder: (context, index) => _buildProductCardFirebase(context, docs[index], isHorizontal: true))),

                                    if (hasHistory && !isSearchingOrFiltering && preferredCategories.isNotEmpty) ...[
                                      const Padding(padding: EdgeInsets.fromLTRB(15, 25, 15, 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Text('RECOMMENDED FOR YOU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Icon(Icons.auto_awesome, color: Colors.deepOrange, size: 20)])),
                                      StreamBuilder(
                                        stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').where('category', whereIn: preferredCategories).snapshots(),
                                        builder: (context, AsyncSnapshot<QuerySnapshot> recSnapshot) {
                                          if (!recSnapshot.hasData || recSnapshot.data!.docs.isEmpty) return const SizedBox.shrink();
                                          return GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15), gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: recSnapshot.data!.docs.length, itemBuilder: (context, index) => _buildProductCardFirebase(context, recSnapshot.data!.docs[index]));
                                        }
                                      ),
                                    ]
                                  ],
                                );
                              }
                            );
                          }
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStaticCategory(String label, IconData icon, Color iconColor) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { 
        setState(() => selectedCategoryFilter = isSelected ? '' : label); 
        if (!isSelected) _logUserActivity('view_category', label); // [NEW LOGIC]
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[Container(width: 70, height: 70, decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? Colors.deepOrange : Colors.transparent, width: 2.5)), child: Center(child: Icon(icon, color: iconColor, size: 35))), const SizedBox(height: 8), SizedBox(width: 75, child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis))])
      ),
    );
  }

  Widget _buildDynamicCategory(String label, String imageUrl) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { 
        setState(() => selectedCategoryFilter = isSelected ? '' : label); 
        if (!isSelected) _logUserActivity('view_category', label); //[NEW LOGIC]
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15), border: Border.all(color: isSelected ? Colors.deepOrange : Colors.transparent, width: 2.5), boxShadow:[BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))]), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(imageUrl, fit: BoxFit.cover))), const SizedBox(height: 8), SizedBox(width: 75, child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis))])
      ),
    );
  }

  Widget _buildProductCardFirebase(BuildContext context, QueryDocumentSnapshot product, {bool isHorizontal = false}) {
    Map<String, dynamic> data = product.data() as Map<String, dynamic>;
    String firstImage = (data['image_urls'] != null && (data['image_urls'] as List).isNotEmpty) ? data['image_urls'][0].toString() : '';
    bool isFlashSale = data['is_flash_sale'] ?? false;
    String displayPrice = isFlashSale && data['discount_price']?.toString().isNotEmpty == true ? data['discount_price'].toString() : data['price'].toString();
    int currentPrice = int.tryParse(displayPrice) ?? 0;
    int originalPrice = int.tryParse(data['original_price']?.toString() ?? '0') ?? 0;
    int discountPercent = originalPrice > currentPrice ? (((originalPrice - currentPrice) / originalPrice) * 100).round() : 0;

    return InkWell(
      onTap: () {
         _logUserActivity('view_product', data['product_name'] ?? product.id); //[NEW LOGIC]
         Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: product)));
      },
      child: Container(width: isHorizontal ? 140 : null, margin: isHorizontal ? const EdgeInsets.only(right: 10) : EdgeInsets.zero, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Expanded(child: Stack(children:[Container(width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))), if (discountPercent > 0) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10))), child: Text('-$discountPercent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))))])), Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(data['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 5), Row(crossAxisAlignment: CrossAxisAlignment.end, children:[Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 5), if (discountPercent > 0) Text('৳$originalPrice', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10))])]))])),
    );
  }

  Widget _buildDefaultBanner() {
    return Container(margin: const EdgeInsets.all(15), height: 120, width: double.infinity, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors:[Colors.orange.shade200, Colors.deepOrange.shade100])), child: Row(children:[const Padding(padding: EdgeInsets.all(15.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children:[Text('WELCOME TO D SHOP!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)), Text('Explore Best Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))])), const Spacer(), Icon(Icons.shopping_bag, size: 80, color: Colors.deepOrange.withOpacity(0.3)), const SizedBox(width: 20)]));
  }
}

// ==========================================
// ১ নম্বর পেজ: User Profile (Superfast with Local Cache & Seller Switch)
// ==========================================
class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  User? currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();

  String _userName = 'Loading...';
  String _profileImageUrl = '';
  String _userRole = 'customer'; // ইউজারের রোল ট্রেস করার জন্য

  @override
  void initState() {
    super.initState();
    _loadProfileData(); 
  }

  Future<void> _loadProfileData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // লোকাল মেমরি থেকে ডাটা লোড
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Customer';
        _profileImageUrl = prefs.getString('profile_image') ?? '';
        _userRole = prefs.getString('user_role') ?? 'customer';
      });
    }

    // ব্যাকগ্রাউন্ডে ফায়ারবেস থেকে আপডেট চেক
    if (currentUser != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String newName = data['name'] ?? 'Customer';
        String newImage = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';
        String newRole = data.containsKey('role') ? data['role'] : 'customer';

        if (_userName != newName || _profileImageUrl != newImage || _userRole != newRole) {
          prefs.setString('user_name', newName);
          prefs.setString('profile_image', newImage);
          prefs.setString('user_role', newRole); // রোল সেভ করা হলো
          if (mounted) {
            setState(() {
              _userName = newName;
              _profileImageUrl = newImage;
              _userRole = newRole;
            });
          }
        }
      }
    }
  }

  // ছবি আপলোডের ফাংশন
  Future<void> _uploadProfilePicture() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (image == null || currentUser == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      String fileName = 'profile_${currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child('profile_pictures').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'profile_image_url': downloadUrl});

      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('profile_image', downloadUrl);

      if (!mounted) return;
      Navigator.pop(context); 
      
      setState(() { _profileImageUrl = downloadUrl; });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile picture updated successfully! 🎉')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showSupportOptions(BuildContext context) {
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
              const Text('Customer Support', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Text('We are here to help! Choose an option below:', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              ListTile(leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.call, color: Colors.white)), title: const Text('Call Us Now', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('01700-000000'), onTap: () async { final Uri url = Uri.parse('tel:01700000000'); if (await canLaunchUrl(url)) { await launchUrl(url); } }),
              const Divider(),
              ListTile(leading: const CircleAvatar(backgroundColor: Colors.deepOrange, child: Icon(Icons.email, color: Colors.white)), title: const Text('Send an Email', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('support@doharshop.com'), onTap: () async { final Uri url = Uri.parse('mailto:support@doharshop.com?subject=Customer Support Request'); if (await canLaunchUrl(url)) { await launchUrl(url); } }),
              const SizedBox(height: 10),
            ],
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange, centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()))),
      ),
      body: Column(
        children:[
          Container(
            padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
            child: Row(
              children:[
                Stack(
                  alignment: Alignment.bottomRight,
                  children:[
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.orange.shade100,
                      backgroundImage: _profileImageUrl.isNotEmpty ? NetworkImage(_profileImageUrl) : null,
                      child: _profileImageUrl.isEmpty ? const Icon(Icons.person, size: 40, color: Colors.deepOrange) : null,
                    ),
                    InkWell(
                      onTap: _uploadProfilePicture,
                      child: Container(padding: const EdgeInsets.all(4), decoration: const BoxDecoration(color: Colors.teal, shape: BoxShape.circle), child: const Icon(Icons.camera_alt, color: Colors.white, size: 14)),
                    ),
                  ],
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children:[
                      Text(_userName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                      Text(currentUser?.email ?? 'No Email', style: const TextStyle(color: Colors.grey)), 
                      const SizedBox(height: 5), 
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(10)), child: const Text('MEMBER', style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold)))
                    ]
                  )
                )
              ]
            ),
          ),
          
          // =====================================
          // সেলার মুডে ফিরে যাওয়ার অপশন
          // =====================================
          if (_userRole == 'seller')
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: InkWell(
                onTap: () {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
                },
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.teal)),
                  child: Row(
                    children: const[
                      Icon(Icons.storefront, color: Colors.teal, size: 28),
                      SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:[
                            Text('Return to Seller Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.teal)),
                            Text('আপনার দোকানে ফিরে যান', style: TextStyle(fontSize: 12, color: Colors.black54)),
                          ],
                        )
                      ),
                      Icon(Icons.arrow_forward_ios, color: Colors.teal, size: 18)
                    ],
                  ),
                ),
              ),
            ),
          // =====================================

          Expanded(
            child: GridView.count(
              crossAxisCount: 2, padding: const EdgeInsets.all(20), crossAxisSpacing: 15, mainAxisSpacing: 15, childAspectRatio: 1.5, 
              children:[
                _buildDashboardCard(Icons.history, 'Order History', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage()))),
                _buildDashboardCard(Icons.favorite_border, 'Wishlist', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const WishlistPage()))),
                _buildDashboardCard(Icons.location_on_outlined, 'Shipping Address', () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddressListPage()))),
                _buildDashboardCard(Icons.support_agent, 'Customer Support', () => _showSupportOptions(context)),
              ]
            )
          ),
          Padding(
            padding: const EdgeInsets.all(20.0), 
            child: SizedBox(
              width: double.infinity, height: 50, 
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)), 
                icon: const Icon(Icons.logout, color: Colors.red), 
                label: const Text('Log Out', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)), 
                onPressed: () {
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                  Future.microtask(() async {
                    await NotificationService.syncFcmTopics('guest');
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.clear();
                    await FirebaseAuth.instance.signOut();
                  });
                }
              )
            )
          )
        ],
      ),
    );
  }
  
  Widget _buildDashboardCard(IconData icon, String title, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow:[BoxShadow(color: Colors.grey.shade200, blurRadius: 5, spreadRadius: 2)]), 
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(icon, size: 40, color: Colors.deepOrange), const SizedBox(height: 10), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))])
      ),
    );
  }
}

// ==========================================
// ক্যাটাগরি পেজ (100% Dynamic with Smart Preference)
// ==========================================
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  String? _selectedCategoryName;

  @override
  void initState() {
    super.initState();
    _loadPreferredCategory(); // [NEW] পেজ লোড হতেই ইউজারের পছন্দ চেক করবে
  }

  // [NEW LOGIC] ডাটাবেস থেকে ইউজারের লাস্ট ভিউ করা প্রোডাক্টের ক্যাটাগরি আনা
  Future<void> _loadPreferredCategory() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var snap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('recently_viewed').orderBy('viewed_at', descending: true).limit(1).get();
        if (snap.docs.isNotEmpty && mounted) {
          setState(() {
            _selectedCategoryName = snap.docs.first['category'];
          });
        }
      } catch (e) {
        // Error ইগনোর করবে
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    int gridColumns = screenWidth > 900 ? 4 : (screenWidth > 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()))
        ),
        title: const Text('Categories', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true, actions:[IconButton(icon: const Icon(Icons.search, color: Colors.black), onPressed: () {})],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('categories').orderBy('created_at', descending: false).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No categories available.'));

          var categories = snapshot.data!.docs;
          
          // [FIXED] যদি ইউজারের কোনো প্রিফারেন্স না থাকে, তবেই শুধু প্রথম ক্যাটাগরিটা সিলেক্ট করবে
          if (_selectedCategoryName == null && categories.isNotEmpty) {
             WidgetsBinding.instance.addPostFrameCallback((_) {
               if(mounted) {
                 setState(() {
                   _selectedCategoryName ??= (categories.first.data() as Map<String, dynamic>)['name'];
                 });
               }
             });
          }

          return Row(
            children:[
              // বাম পাশের ক্যাটাগরি লিস্ট
              Container(
                width: 100, color: Colors.grey.shade50,
                child: ListView.builder(
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    Map<String, dynamic> catData = categories[index].data() as Map<String, dynamic>;
                    String catName = catData['name'];
                    String imgUrl = catData['image_url'];
                    bool isSelected = _selectedCategoryName == catName;

                    return InkWell(
                      onTap: () { setState(() { _selectedCategoryName = catName; }); },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 5),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          border: Border(left: BorderSide(color: isSelected ? Colors.deepOrange : Colors.transparent, width: 4))
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:[
                            CircleAvatar(
                              radius: 20, backgroundColor: Colors.transparent,
                              backgroundImage: NetworkImage(imgUrl),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              catName, textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              
              // ডান পাশের প্রোডাক্ট গ্রিড
              Expanded(
                child: Container(
                  color: Colors.white, padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Text('$_selectedCategoryName Products', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 15),
                      Expanded(
                        child: _selectedCategoryName == null 
                         ? const Center(child: CircularProgressIndicator()) 
                         : StreamBuilder(
                          stream: FirebaseFirestore.instance.collection('products')
                              .where('status', isEqualTo: 'approved')
                              .where('category', isEqualTo: _selectedCategoryName)
                              .snapshots(),
                          builder: (context, AsyncSnapshot<QuerySnapshot> prodSnapshot) {
                            if (prodSnapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                            if (!prodSnapshot.hasData || prodSnapshot.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.production_quantity_limits, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), const Text('No products found here yet!', style: TextStyle(color: Colors.grey))]));

                            return GridView.builder(
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10),
                              itemCount: prodSnapshot.data!.docs.length,
                              itemBuilder: (context, index) { return _buildRealProductCard(context, prodSnapshot.data!.docs[index]); },
                            );
                          }
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }

  Widget _buildRealProductCard(BuildContext context, QueryDocumentSnapshot product) {
    Map<String, dynamic> data = product.data() as Map<String, dynamic>;
    
    String firstImage = '';
    if (data['image_urls'] != null && (data['image_urls'] as List).isNotEmpty) {
      firstImage = data['image_urls'][0]?.toString() ?? '';
    }
    
    bool isFlashSale = data.containsKey('is_flash_sale') ? data['is_flash_sale'] : false;
    String displayPrice = isFlashSale && data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty ? data['discount_price'].toString() : data['price'].toString();

    int currentPrice = int.tryParse(displayPrice) ?? 0;
    int originalPrice = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int discountPercent = 0;
    if (originalPrice > currentPrice) discountPercent = (((originalPrice - currentPrice) / originalPrice) * 100).round();

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: product))),
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Expanded(child: Stack(children:[Container(width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))), if (discountPercent > 0) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10))), child: Text('-$discountPercent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))))])), 
          Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(data['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 5), Row(crossAxisAlignment: CrossAxisAlignment.end, children:[Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 5), if (discountPercent > 0) Text('৳$originalPrice', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10))])]))
        ]),
      ),
    );
  }
}

// ==========================================
// কাস্টমার লোকেশন সেটআপ পেজ (Smart Universal Address Format)
// ==========================================
class AddressSetupPage extends StatefulWidget {
  const AddressSetupPage({super.key});

  @override
  State<AddressSetupPage> createState() => _AddressSetupPageState();
}

class _AddressSetupPageState extends State<AddressSetupPage> {
  LatLng _currentPosition = const LatLng(23.6062, 90.1345); // ডিফল্ট লোকেশন
  GoogleMapController? _mapController;
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  
  // [NEW] ইউনিভার্সাল স্মার্ট অ্যাড্রেস বক্স
  final TextEditingController _areaController = TextEditingController(); 
  final TextEditingController _houseController = TextEditingController(); 
  final TextEditingController _landmarkController = TextEditingController(); 

  @override
  void initState() {
    super.initState();
    _getUserCurrentLocation(); 
  }

  Future<void> _getUserCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    setState(() {
      _currentPosition = LatLng(position.latitude, position.longitude);
    });
    if (_mapController != null) {
      _mapController!.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
    }
  }

  void _onCameraMove(CameraPosition position) {
    _currentPosition = position.target;
  }

  void saveAddress() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || 
        _areaController.text.trim().isEmpty || _houseController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে নাম, ফোন, এলাকা এবং বাড়ির তথ্য দিন!')));
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

      // [NEW] সুন্দর করে সাজানো টেক্সট ঠিকানা যা রাইডার দেখতে পাবে
      String fullAddress = '${_houseController.text.trim()}, ${_areaController.text.trim()}';
      if (_landmarkController.text.trim().isNotEmpty) {
        fullAddress += ' (Landmark: ${_landmarkController.text.trim()})';
      }

      var addressRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('addresses');
      var existingAddresses = await addressRef.limit(1).get();
      bool isFirstAddress = existingAddresses.docs.isEmpty;

      await addressRef.add({
        'shipping_name': _nameController.text.trim(),
        'shipping_phone': _phoneController.text.trim(),
        'shipping_address_text': fullAddress, 
        'latitude': _currentPosition.latitude,
        'longitude': _currentPosition.longitude,
        'is_default': isFirstAddress,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); 
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('নতুন ঠিকানা সফলভাবে সেভ হয়েছে! 📍')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: const Text('Set Delivery Location', style: TextStyle(color: Colors.white, fontSize: 18)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children:[
          // উপরের অর্ধেক: ম্যাপ 
          Expanded(
            flex: 2,
            child: Stack(
              alignment: Alignment.center,
              children:[
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 15),
                  onMapCreated: (GoogleMapController controller) => _mapController = controller,
                  onCameraMove: _onCameraMove,
                  myLocationEnabled: false, 
                  myLocationButtonEnabled: false, 
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 35.0), 
                  child: Icon(Icons.location_on, size: 50, color: Colors.deepOrange),
                ),
                Positioned(
                  top: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(20)),
                    child: const Text('ম্যাপ টেনে আপনার বাড়ির ওপর পিন রাখুন', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ),
                Positioned(
                  bottom: 15, right: 15,
                  child: FloatingActionButton(
                    mini: true,
                    backgroundColor: Colors.white,
                    onPressed: _getUserCurrentLocation,
                    child: const Icon(Icons.my_location, color: Colors.blue),
                  ),
                )
              ],
            ),
          ),

          // নিচের অর্ধেক: স্মার্ট ফর্ম
          Expanded(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, boxShadow:[BoxShadow(color: Colors.grey.shade300, blurRadius: 10, offset: const Offset(0, -5))], borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    Row(
                      children:[
                        Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'আপনার নাম', border: OutlineInputBorder(), isDense: true))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'ফোন নম্বর', border: OutlineInputBorder(), isDense: true))),
                      ],
                    ),
                    const SizedBox(height: 15),
                    
                    // ১. এলাকা / রাস্তা / গ্রাম
                    TextField(
                      controller: _areaController, 
                      decoration: const InputDecoration(
                        labelText: 'এলাকা / গ্রাম / রাস্তা (Area / Village / Road)', 
                        hintText: 'যেমন: ঝনকী, বা বনানী রোড ১১',
                        border: OutlineInputBorder(), isDense: true
                      )
                    ),
                    const SizedBox(height: 15),

                    // ২. বাড়ি / ফ্লাট
                    TextField(
                      controller: _houseController, 
                      decoration: const InputDecoration(
                        labelText: 'বাড়ি / ফ্লাট / হোল্ডিং (House / Flat)', 
                        hintText: 'যেমন: মাতব্বর বাড়ি, বা ফ্লাট ৪বি',
                        border: OutlineInputBorder(), isDense: true
                      )
                    ),
                    const SizedBox(height: 15),

                    // ৩. পরিচিত স্থান (ল্যান্ডমার্ক)
                    TextField(
                      controller: _landmarkController, 
                      decoration: const InputDecoration(
                        labelText: 'পরিচিত স্থান (Landmark - ঐচ্ছিক)', 
                        hintText: 'যেমন: বড় মসজিদের পাশে',
                        border: OutlineInputBorder(), isDense: true
                      )
                    ),
                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        icon: const Icon(Icons.save, color: Colors.white), label: const Text('SAVE ADDRESS', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        onPressed: saveAddress,
                      ),
                    )
                  ],
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// ইউজারের সকল ঠিকানার লিস্ট পেজ (Address Management)
// ==========================================
class AddressListPage extends StatefulWidget {
  const AddressListPage({super.key});

  @override
  State<AddressListPage> createState() => _AddressListPageState();
}

class _AddressListPageState extends State<AddressListPage> {
  User? user = FirebaseAuth.instance.currentUser;

  // ডিফল্ট ঠিকানা সেট করার ফাংশন
  void setDefaultAddress(String addressId) async {
    if (user == null) return;
    showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

    // ইউজারের সব ঠিকানা নিয়ে আসা
    var snapshot = await FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('addresses').get();
    
    // Batch Write এর মাধ্যমে যেটিতে ক্লিক করেছে সেটিকে True এবং বাকিগুলোকে False করে দেওয়া
    var batch = FirebaseFirestore.instance.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'is_default': doc.id == addressId});
    }
    await batch.commit();

    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ডিফল্ট ঠিকানা আপডেট হয়েছে! ✅')));
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) return const Scaffold(body: Center(child: Text('Please login')));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Addresses', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.deepOrange,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('addresses').orderBy('created_at', descending: true).snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('আপনার কোনো ঠিকানা সেভ করা নেই।', style: TextStyle(color: Colors.grey, fontSize: 16)));
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              bool isDefault = doc['is_default'] ?? false;

              return Card(
                margin: const EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                  side: BorderSide(color: isDefault ? Colors.teal : Colors.transparent, width: 2) // ডিফল্ট হলে সুন্দর বর্ডার দেখাবে
                ),
                child: Padding(
                  padding: const EdgeInsets.all(15.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Row(
                            children:[
                              const Icon(Icons.person, color: Colors.grey, size: 18),
                              const SizedBox(width: 5),
                              Text(doc['shipping_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            ],
                          ),
                          if (isDefault) 
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(5)), child: const Text('Default', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 12))),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Row(children:[const Icon(Icons.phone, color: Colors.grey, size: 16), const SizedBox(width: 5), Text(doc['shipping_phone'], style: const TextStyle(color: Colors.black87))]),
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Icon(Icons.location_on, color: Colors.red, size: 18), const SizedBox(width: 5),
                          Expanded(child: Text(doc['shipping_address_text'], style: const TextStyle(color: Colors.black54, height: 1.4))),
                        ],
                      ),
                      const Divider(height: 25),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          // ডিফল্ট সেট করার বাটন
                          if (!isDefault)
                            TextButton.icon(
                              onPressed: () => setDefaultAddress(doc.id),
                              icon: const Icon(Icons.check_circle_outline, color: Colors.teal),
                              label: const Text('Set as Default', style: TextStyle(color: Colors.teal)),
                            )
                          else 
                            const SizedBox(), // ডিফল্ট হলে বাটন দেখাবে না
                          
                          // ডিলিট বাটন
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () {
                              FirebaseFirestore.instance.collection('users').doc(user!.uid).collection('addresses').doc(doc.id).delete();
                            },
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
      // নতুন ঠিকানা যুক্ত করার Floating Button
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Colors.deepOrange,
        icon: const Icon(Icons.add_location_alt, color: Colors.white),
        label: const Text('Add New Address', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => const AddressSetupPage()));
        },
      ),
    );
  }
}

// ==========================================
// কাস্টমারের অর্ডার হিস্ট্রি পেজ (With Review, Tracking & Reward System)
// ==========================================
class OrderHistoryPage extends StatefulWidget {
  const OrderHistoryPage({super.key});

  @override
  State<OrderHistoryPage> createState() => _OrderHistoryPageState();
}

class _OrderHistoryPageState extends State<OrderHistoryPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> generateAndPrintInvoice(Map<String, dynamic> data, String orderId) async {
    final pdf = pw.Document();
    String dateString = 'Unknown Date';
    if (data['order_date'] != null && data['order_date'] is Timestamp) {
      DateTime date = (data['order_date'] as Timestamp).toDate();
      dateString = '${date.day}/${date.month}/${date.year}';
    }
    List<dynamic> items = data['items'] ??[];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children:[
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children:[pw.Text('D Shop', style: pw.TextStyle(fontSize: 30, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)), pw.Text('INVOICE', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))]),
              pw.SizedBox(height: 30),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children:[pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children:[pw.Text('Order ID: #${orderId.substring(0, 8).toUpperCase()}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 5), pw.Text('Date: $dateString'), pw.SizedBox(height: 5), pw.Text('Payment: ${data['payment_method'] ?? 'COD'}')]), pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children:[pw.Text('Billed To:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)), pw.SizedBox(height: 5), pw.Text(data['shipping_name'] ?? 'Customer'), pw.Text(data['shipping_phone'] ?? '')])]),
              pw.SizedBox(height: 30),
              pw.Table.fromTextArray(
                headers:['Item Description', 'Qty', 'Unit Price', 'Total'],
                data: items.map((item) {
                  int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                  double price = double.tryParse(item['price'].toString()) ?? 0.0;
                  return [item['product_name'].toString(), qty.toString(), 'Tk ${price.toStringAsFixed(0)}', 'Tk ${(qty * price).toStringAsFixed(0)}'];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white), headerDecoration: const pw.BoxDecoration(color: PdfColors.teal), cellAlignment: pw.Alignment.centerLeft, cellPadding: const pw.EdgeInsets.all(8),
              ),
              pw.SizedBox(height: 20),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.end, children:[pw.Text('Grand Total: Tk ${data['total_amount']}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange))]),
              pw.SizedBox(height: 50), pw.Divider(), pw.Center(child: pw.Text('Thank you for shopping with D Shop!', style: pw.TextStyle(fontSize: 12, fontStyle: pw.FontStyle.italic))),
            ],
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Invoice_${orderId.substring(0, 8)}.pdf');
  }

  // [NEW] ফুল-স্ক্রিন ছবি দেখানোর ফাংশন
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

  // =====================================
  // [NEW] কাস্টমার রিভিউ ও রিওয়ার্ড সিস্টেম
  // =====================================
  void _showReviewDialog(String orderId, String userId) {
    int selectedRating = 5;
    TextEditingController commentCtrl = TextEditingController();
    XFile? reviewImage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Rate Your Experience', style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children:[
                  const Text('পণ্যটি হাতে পেয়ে আপনি কেমন অনুভব করছেন? ছবিসহ রিভিউ দিলে পাবেন 50 D-Coins ফ্রি! 🎁', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 15),
                  
                  // স্টার রেটিং
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      return IconButton(
                        icon: Icon(index < selectedRating ? Icons.star : Icons.star_border, color: Colors.amber, size: 30),
                        onPressed: () => setDialogState(() => selectedRating = index + 1),
                      );
                    }),
                  ),
                  const SizedBox(height: 10),
                  
                  // রিভিউ টেক্সট
                  TextField(
                    controller: commentCtrl, maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Write your feedback here...', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  
                  // ছবি আপলোড
                  InkWell(
                    onTap: () async {
                      final XFile? img = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
                      if (img != null) setDialogState(() => reviewImage = img);
                    },
                    child: Container(
                      height: 80, width: double.infinity,
                      decoration: BoxDecoration(color: Colors.grey.shade100, border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid), borderRadius: BorderRadius.circular(10)),
                      child: reviewImage != null 
                          ? (kIsWeb ? Image.network(reviewImage!.path, fit: BoxFit.cover) : Image.file(File(reviewImage!.path), fit: BoxFit.cover))
                          : Column(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.add_a_photo, color: Colors.grey), Text('Add Photo', style: TextStyle(color: Colors.grey))]),
                    ),
                  )
                ],
              ),
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Skip')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: () async {
                  Navigator.pop(context); // Close dialog
                  
                  showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

                  String? imageUrl;
                  if (reviewImage != null) {
                    String fileName = 'review_${orderId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
                    Reference ref = FirebaseStorage.instance.ref().child('reviews').child(fileName);
                    if (kIsWeb) {
                      await ref.putData(await reviewImage!.readAsBytes(), SettableMetadata(contentType: 'image/jpeg'));
                    } else {
                      await ref.putFile(File(reviewImage!.path));
                    }
                    imageUrl = await ref.getDownloadURL();
                  }

                  // ডাটাবেসে রিভিউ সেভ করা
                  await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
                    'is_reviewed': true,
                    'rating': selectedRating,
                    'review_text': commentCtrl.text.trim(),
                    'review_image_url': imageUrl,
                  });

                  // কাস্টমারকে D-Coins দেওয়া (SetOptions merge ব্যবহার করা হলো যাতে ক্র্যাশ না করে)
                  int rewardCoins = reviewImage != null ? 50 : 20; 
                  await FirebaseFirestore.instance.collection('users').doc(userId).set({
                    'd_coins': FieldValue.increment(rewardCoins)
                  }, SetOptions(merge: true));

                  // অ্যাডমিনকে নোটিফিকেশন পাঠানো (ডিফল্ট সাউন্ড বাজবে)
                  await FirebaseFirestore.instance.collection('notifications').add({
                    'title': 'New Review Submitted! ⭐',
                    'message': 'অর্ডার #${orderId.substring(0, 6)} এর জন্য কাস্টমার রেটিং দিয়েছেন: $selectedRating Star.',
                    'topic': 'admins',
                    'type': 'default', // সাধারণ নোটিফিকেশন
                    'sent_at': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    Navigator.pop(context); // Close Loading
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Review Submitted! You earned $rewardCoins D-Coins 🪙'), backgroundColor: Colors.green));
                  }
                },
                child: const Text('Submit Review', style: TextStyle(color: Colors.white))
              )
            ],
          );
        }
      )
    );
  }

  // =====================================
  // [NEW] টাইমলাইন তৈরি করার হেল্পার ফাংশন
  // =====================================
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

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please login')));

    return DefaultTabController(
      length: 4, 
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('My Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.deepOrange,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
          bottom: const TabBar(
            isScrollable: false, 
            labelColor: Colors.white, unselectedLabelColor: Colors.white70, indicatorColor: Colors.white,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs:[Tab(text: 'All'), Tab(text: 'Pending'), Tab(text: 'Shipped'), Tab(text: 'Delivered')],
          ),
        ),
        body: StreamBuilder(
          stream: FirebaseFirestore.instance.collection('orders').where('user_id', isEqualTo: user.uid).snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
            if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300), const SizedBox(height: 10), const Text('No orders found!', style: TextStyle(color: Colors.grey, fontSize: 16))]));
            }

            var allOrders = snapshot.data!.docs.toList();
            allOrders.sort((a, b) {
              var tA = (a.data() as Map<String, dynamic>)['order_date'];
              var tB = (b.data() as Map<String, dynamic>)['order_date'];
              if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
              return 0;
            });

            return TabBarView(
              children:[
                _buildOrderList(context, allOrders, user.uid), 
                _buildOrderList(context, allOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList(), user.uid), 
                _buildOrderList(context, allOrders.where((doc) =>['Processing', 'Ready to Ship', 'Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList(), user.uid), 
                _buildOrderList(context, allOrders.where((doc) =>['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList(), user.uid), 
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<QueryDocumentSnapshot> orders, String userId) {
    if (orders.isEmpty) return const Center(child: Text('No orders in this status.', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        var order = orders[index];
        Map<String, dynamic> data = order.data() as Map<String, dynamic>;
        List<dynamic> items = data['items'] ??[];
        
        String dateString = 'Unknown Date';
        if (data['order_date'] != null && data['order_date'] is Timestamp) {
          DateTime date = (data['order_date'] as Timestamp).toDate();
          dateString = '${date.day}/${date.month}/${date.year}';
        }

        String status = data['status'] ?? 'Pending';
        bool isReviewed = data['is_reviewed'] ?? false;
        
        Color statusColor = Colors.orange; 
        if (['Processing', 'Ready to Ship'].contains(status)) statusColor = Colors.blue;
        if (['Dispatched', 'In-Transit'].contains(status)) statusColor = Colors.purple;
        if (status == 'Delivered') statusColor = Colors.green;
        if (['Delivery Failed', 'Cancelled'].contains(status)) statusColor = Colors.red;

        return Card(
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    Text('Order ID: ${order.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
                const SizedBox(height: 5),
                Text('Placed on: $dateString', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                
                // =====================================
                //[NEW] Delivery Secret PIN (For Dispatched)
                // =====================================
                if (status == 'Dispatched' || status == 'In-Transit')
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.teal.shade50, border: Border.all(color: Colors.teal), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children:[
                        const Text('Delivery Secret PIN:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                        Text(data['delivery_otp'] ?? '0000', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.teal)),
                      ],
                    ),
                  ),

                const Divider(height: 15),
                
                // =====================================
                // [NEW] Detailed Order Tracking Timeline
                // =====================================
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      const Text('Order Tracking Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                      const SizedBox(height: 10),
                      _buildTimelineRow('Order Placed', data['order_date'], true),
                      _buildTimelineRow('Confirmed & Processing', data['processing_at'], status != 'Pending'),
                      _buildTimelineRow('Packed & Ready', data['ready_to_ship_at'], ['Ready to Ship', 'Dispatched', 'In-Transit', 'Delivered'].contains(status)),
                      _buildTimelineRow('Out for Delivery', data['dispatched_at'],['Dispatched', 'In-Transit', 'Delivered'].contains(status)),
                      if (status != 'Delivery Failed')
                        _buildTimelineRow('Delivered Successfully', data['delivered_at'], status == 'Delivered', isLast: true),
                      if (status == 'Delivery Failed')
                        _buildTimelineRow('Delivery Failed (${data['failed_reason'] ?? 'Unknown'})', data['failed_at'], true, isLast: true, isError: true),
                    ],
                  ),
                ),
                const SizedBox(height: 15),

                // =====================================
                // [NEW] Show Proof of Delivery Image
                // =====================================
                if (data['proof_image_url'] != null || data['failed_proof_url'] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 15),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.teal.shade200), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children:[
                        InkWell(
                          onTap: () => _showFullScreenImage(context, data['proof_image_url'] ?? data['failed_proof_url']),
                          child: Stack(
                            alignment: Alignment.center,
                            children:[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(data['proof_image_url'] ?? data['failed_proof_url'], width: 60, height: 60, fit: BoxFit.cover),
                              ),
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.zoom_out_map, color: Colors.white, size: 14),
                              )
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data['proof_image_url'] != null ? 'Proof of Delivery' : 'Proof of Failed Delivery', style: TextStyle(fontWeight: FontWeight.bold, color: data['proof_image_url'] != null ? Colors.teal : Colors.red)),
                              const Text('রাইডারের তোলা ডেলিভারি ছবি।', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          ),
                        )
                      ],
                    ),
                  ),

                ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
                  itemBuilder: (context, i) {
                    var item = items[i];
                    return Padding(padding: const EdgeInsets.only(bottom: 5.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Expanded(child: Text('${item['quantity']}x ${item['product_name']}', maxLines: 1, overflow: TextOverflow.ellipsis)), Text('৳${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold))]));
                  }
                ),
                const Divider(height: 15),
                
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    Row(
                      children:[
                        if (status == 'In-Transit')
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                            icon: const Icon(Icons.map, size: 16, color: Colors.white), 
                            label: const Text('Track Live', style: TextStyle(color: Colors.white, fontSize: 12)),
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => LiveTrackingPage(orderId: order.id))),
                          ),
                        
                        if (status == 'Delivered' && !isReviewed)
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
                            icon: const Icon(Icons.star, size: 16, color: Colors.white), 
                            label: const Text('Review', style: TextStyle(color: Colors.white, fontSize: 12)),
                            onPressed: () => _showReviewDialog(order.id, userId),
                          ),

                        if (status == 'Delivered' && isReviewed)
                           const Text('Reviewed ⭐', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),

                        const SizedBox(width: 8),

                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, side: const BorderSide(color: Colors.teal)),
                          icon: const Icon(Icons.receipt_long, size: 16), label: const Text('Invoice'),
                          onPressed: () => generateAndPrintInvoice(data, order.id),
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ==========================================
// কাস্টমার উইশলিস্ট পেজ (Favorite Products)
// ==========================================
class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please login')));

    double screenWidth = MediaQuery.of(context).size.width;
    int gridColumns = screenWidth > 1200 ? 6 : (screenWidth > 800 ? 4 : 2);

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('My Wishlist', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.deepOrange,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: StreamBuilder(
        // ফায়ারবেস থেকে ইউজারের সেভ করা উইশলিস্ট আনা হচ্ছে
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wishlist').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children:[
                  Icon(Icons.favorite_border, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  const Text('Your wishlist is empty!', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ]
              )
            );
          }

          var docs = snapshot.data!.docs;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: GridView.builder(
                padding: const EdgeInsets.all(15),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: gridColumns,
                  childAspectRatio: 0.70,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  var product = docs[index];
                  Map<String, dynamic> data = product.data() as Map<String, dynamic>;
                  List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
                  String firstImage = images.isNotEmpty ? images[0] : '';
                  
                  String displayPrice = data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty 
                      ? data['discount_price'].toString() : data['price'].toString();

                  return InkWell(
                    // উইশলিস্ট থেকে ক্লিক করলে আবার প্রোডাক্ট ডিটেইলস পেজে নিয়ে যাবে
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: product))),
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, 
                        children:[
                          Expanded(
                            child: Stack(
                              children:[
                                Container(
                                  width: double.infinity, 
                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), 
                                  child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))
                                ),
                                // ডিলিট বাটন
                                Positioned(
                                  top: 5, right: 5,
                                  child: InkWell(
                                    onTap: () {
                                      FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wishlist').doc(product.id).delete();
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Wishlist')));
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                      child: const Icon(Icons.delete, color: Colors.red, size: 18),
                                    )
                                  )
                                )
                              ]
                            )
                          ), 
                          Padding(
                            padding: const EdgeInsets.all(10.0), 
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
                              Text(data['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis), 
                              const SizedBox(height: 5), 
                              Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15))
                            ])
                          )
                        ]
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

// ==========================================
// ইউনিভার্সাল নোটিফিকেশন পেজ (Smart UI, Grouped Dates, Auto-Cleanup)
// ==========================================
class CustomerNotificationPage extends StatefulWidget {
  const CustomerNotificationPage({super.key});

  @override
  State<CustomerNotificationPage> createState() => _CustomerNotificationPageState();
}

class _CustomerNotificationPageState extends State<CustomerNotificationPage> {
  User? currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _cleanupOldNotifications(); // পেজ ওপেন হলেই ৩০ দিনের পুরোনো নোটিফিকেশন মুছে ফেলবে
  }

  // 🔴 ৩০ দিনের পুরোনো পার্সোনাল নোটিফিকেশন ডিলিট করার স্মার্ট ফাংশন
  Future<void> _cleanupOldNotifications() async {
    if (currentUser == null) return;
    try {
      DateTime thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      
      var oldNotifs = await FirebaseFirestore.instance
          .collection('notifications')
          .where('target_user_id', isEqualTo: currentUser!.uid)
          .where('sent_at', isLessThan: thirtyDaysAgo)
          .get();

      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var doc in oldNotifs.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (e) {
      debugPrint("Cleanup Error: $e");
    }
  }

  // 🔴 টাইটেল পড়ে কালার এবং আইকন ডিসাইড করার ফাংশন
  Map<String, dynamic> _getNotificationStyle(String title) {
    String t = title.toLowerCase();
    if (t.contains('cancel') || t.contains('fail')) {
      return {'color': Colors.red, 'icon': Icons.cancel};
    } else if (t.contains('confirm') || t.contains('success') || t.contains('deliver')) {
      return {'color': Colors.green, 'icon': Icons.check_circle};
    } else if (t.contains('rider') || t.contains('pick') || t.contains('coming')) {
      return {'color': Colors.blue, 'icon': Icons.motorcycle};
    } else if (t.contains('review') || t.contains('star')) {
      return {'color': Colors.amber.shade700, 'icon': Icons.star};
    }
    // ডিফল্ট স্টাইল (অরেঞ্জ)
    return {'color': Colors.deepOrange, 'icon': Icons.notifications_active};
  }

  // 🔴 তারিখের হেডার (Today, Yesterday, 26 Mar) বানানোর ফাংশন
  String _getDateHeader(DateTime date) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime yesterday = today.subtract(const Duration(days: 1));
    DateTime notifDate = DateTime(date.year, date.month, date.day);

    if (notifDate == today) return 'Today';
    if (notifDate == yesterday) return 'Yesterday';

    List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${date.day} ${months[date.month - 1]}, ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.deepOrange),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('notifications').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyNotification();
          }

          var allNotifications = snapshot.data!.docs.where((doc) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String? targetUser = data['target_user_id'];
            String? targetRole = data['target_role'];
            String? type = data['type'];

            bool isForMe = (targetUser == currentUser?.uid);
            bool isBroadcast = (targetRole == 'all_users' || type == 'all_users');
            return isForMe || isBroadcast;
          }).toList();

          allNotifications.sort((a, b) {
            Timestamp? tA = (a.data() as Map<String, dynamic>)['sent_at'] as Timestamp?;
            Timestamp? tB = (b.data() as Map<String, dynamic>)['sent_at'] as Timestamp?;
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          if (allNotifications.isEmpty) {
            return _buildEmptyNotification();
          }

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: allNotifications.length,
            itemBuilder: (context, index) {
              var doc = allNotifications[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              DateTime? notifDate;
              if (data['sent_at'] != null) {
                notifDate = (data['sent_at'] as Timestamp).toDate();
              }

              // 🔴 AM/PM সহ সুন্দর টাইম ফরম্যাট
              String timeString = "Just now";
              if (notifDate != null) {
                int hour = notifDate.hour;
                String period = hour >= 12 ? "PM" : "AM";
                int displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
                timeString = "$displayHour:${notifDate.minute.toString().padLeft(2, '0')} $period";
              }

              // 🔴 স্মার্ট ডেট গ্রুপিং লজিক
              bool showDateHeader = false;
              if (index == 0) {
                showDateHeader = true; // প্রথম আইটেমে সব সময় ডেট দেখাবে
              } else if (notifDate != null) {
                Map<String, dynamic> prevData = allNotifications[index - 1].data() as Map<String, dynamic>;
                if (prevData['sent_at'] != null) {
                  DateTime prevDate = (prevData['sent_at'] as Timestamp).toDate();
                  if (prevDate.year != notifDate.year || prevDate.month != notifDate.month || prevDate.day != notifDate.day) {
                    showDateHeader = true; // আগেরটার সাথে দিন না মিললে নতুন হেডার দেখাবে
                  }
                }
              }

              String title = data['title'] ?? 'Notice';
              Map<String, dynamic> style = _getNotificationStyle(title);
              Color themeColor = style['color'];

              return Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 🔴 মাঝখানে ডেট হেডার (Today / Yesterday)
                  if (showDateHeader && notifDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 20, bottom: 10),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(15)),
                        child: Text(_getDateHeader(notifDate), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
                      ),
                    ),

                  // 🔴 কাস্টম ডিজাইন করা কার্ড
                  Container(
                    margin: const EdgeInsets.only(bottom: 15, left: 2, right: 2),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withOpacity(0.15), // কালার অনুযায়ী গ্লো
                          blurRadius: 10,
                          spreadRadius: 1,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border(left: BorderSide(color: themeColor, width: 5)),
                        ),
                        padding: const EdgeInsets.all(15),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: themeColor.withOpacity(0.1), shape: BoxShape.circle),
                              child: Icon(style['icon'], color: themeColor, size: 24),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87)),
                                  const SizedBox(height: 5),
                                  Text(data['message'] ?? '', style: const TextStyle(color: Colors.black54, fontSize: 13, height: 1.4)),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyNotification() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade300),
          const SizedBox(height: 15),
          const Text('No new notifications', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ],
      ),
    );
  }
}

// ==========================================
// নতুন পেজ: Live GPS Tracking Page (For Customer)
// ==========================================
class LiveTrackingPage extends StatefulWidget {
  final String orderId;
  const LiveTrackingPage({super.key, required this.orderId});

  @override
  State<LiveTrackingPage> createState() => _LiveTrackingPageState();
}

class _LiveTrackingPageState extends State<LiveTrackingPage> {
  GoogleMapController? _mapController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Delivery Tracking', style: TextStyle(color: Colors.white, fontSize: 16)),
        backgroundColor: Colors.deepOrange,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').doc(widget.orderId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || !snapshot.data!.exists) return const Center(child: Text('অর্ডার ডাটা পাওয়া যায়নি!'));

          var data = snapshot.data!.data() as Map<String, dynamic>;
          
          double cLat = data.containsKey('customer_lat') ? (data['customer_lat'] as num).toDouble() : 0.0;
          double cLng = data.containsKey('customer_lng') ? (data['customer_lng'] as num).toDouble() : 0.0;
          
          double rLat = data.containsKey('rider_live_lat') ? (data['rider_live_lat'] as num).toDouble() : 0.0;
          double rLng = data.containsKey('rider_live_lng') ? (data['rider_live_lng'] as num).toDouble() : 0.0;

          // যদি রাইডারের লোকেশন না পাওয়া যায়
          if (rLat == 0.0 || rLng == 0.0) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const[
                  Icon(Icons.location_off, size: 80, color: Colors.grey),
                  SizedBox(height: 15),
                  Text('রাইডার এখনো জিপিএস অন করেননি। একটু অপেক্ষা করুন...', style: TextStyle(color: Colors.grey)),
                ],
              )
            );
          }

          // মার্কার তৈরি করা (কাস্টমার = লাল, রাইডার = নীল/সবুজ)
          Set<Marker> markers = {
            if (cLat != 0.0 && cLng != 0.0)
              Marker(
                markerId: const MarkerId('customer_location'),
                position: LatLng(cLat, cLng),
                icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                infoWindow: const InfoWindow(title: 'My Delivery Address'),
              ),
            Marker(
              markerId: const MarkerId('rider_location'),
              position: LatLng(rLat, rLng),
              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue), // রাইডার ব্লু কালার
              infoWindow: const InfoWindow(title: 'Rider is here! 🛵'),
            )
          };

          // ক্যামেরা রাইডারের লোকেশনে ফোকাস করে রাখা
          if (_mapController != null) {
            _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(rLat, rLng)));
          }

          return Stack(
            children:[
              GoogleMap(
                initialCameraPosition: CameraPosition(target: LatLng(rLat, rLng), zoom: 16),
                markers: markers,
                onMapCreated: (controller) => _mapController = controller,
                myLocationEnabled: false,
                zoomControlsEnabled: false,
              ),
              // নিচে একটি স্ট্যাটাস বক্স
              Positioned(
                bottom: 20, left: 20, right: 20,
                child: Container(
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), boxShadow: const[BoxShadow(color: Colors.black26, blurRadius: 10)]),
                  child: Row(
                    children:[
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.blue.shade50, shape: BoxShape.circle), child: const Icon(Icons.motorcycle, color: Colors.blue)),
                      const SizedBox(width: 15),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const[
                            Text('Rider is on the way!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text('আপনার পার্সেল নিয়ে রাইডার আপনার দিকে আসছেন।', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              )
            ],
          );
        },
      ),
    );
  }
}


// ==========================================
// ডেডিকেটেড Shop Page (Fixed Null Errors for Cover & Logo)
// ==========================================
class ShopPage extends StatefulWidget {
  final String sellerId;
  const ShopPage({super.key, required this.sellerId});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _uploadShopBanner() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (image == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      String fileName = 'shop_banner_${widget.sellerId}_${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child('shop_banners').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();
      
      await FirebaseFirestore.instance.collection('users').doc(widget.sellerId).update({'shop_banner_url': downloadUrl});

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop cover updated successfully! 🎉')));
      setState(() {}); 
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isOwner = FirebaseAuth.instance.currentUser?.uid == widget.sellerId;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(widget.sellerId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          
          String shopName = 'Unknown Shop';
          String shopLogo = '';
          String shopBanner = '';
          
          if (snapshot.hasData && snapshot.data!.exists) {
            var shopData = snapshot.data!.data() as Map<String, dynamic>;
            // [FIXED] Null Safe Retrieval
            shopName = shopData['shop_name']?.toString() ?? shopData['name']?.toString() ?? 'Unknown Shop';
            shopLogo = shopData['profile_image_url']?.toString() ?? '';
            shopBanner = shopData['shop_banner_url']?.toString() ?? '';
          }

          return CustomScrollView(
            slivers:[
              SliverAppBar(
                expandedHeight: 230.0, 
                pinned: true,          
                backgroundColor: Colors.deepOrange,
                iconTheme: const IconThemeData(color: Colors.white),
                leading: IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => Navigator.pop(context)),
                title: const Text('Shop Profile', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                actions:[
                  IconButton(icon: const Icon(Icons.search, color: Colors.white), onPressed: () {}),
                  IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () {}),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children:[
                      shopBanner.isNotEmpty
                          ? Image.network(shopBanner, fit: BoxFit.cover)
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors:[Colors.deepOrange, Colors.orange.shade400],
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter
                                )
                              )
                            ),
                      
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            colors:[Colors.black.withOpacity(0.6), Colors.transparent, Colors.black.withOpacity(0.8)],
                            stops: const[0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                      
                      Positioned(
                        bottom: 20, left: 20, right: 20,
                        child: Row(
                          children:[
                            Container(
                              height: 65, width: 65,
                              decoration: BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                                image: shopLogo.isNotEmpty ? DecorationImage(image: NetworkImage(shopLogo), fit: BoxFit.cover) : null
                              ),
                              child: shopLogo.isEmpty ? const Icon(Icons.storefront, size: 30, color: Colors.deepOrange) : null,
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children:[
                                  Text(shopName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 5),
                                  Row(
                                    children: const[
                                      Icon(Icons.star, color: Colors.amber, size: 14),
                                      Text(' 4.9/5.0  |  ', style: TextStyle(color: Colors.white, fontSize: 12)),
                                      Icon(Icons.verified, color: Colors.greenAccent, size: 12),
                                      Text(' Verified', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            isOwner 
                            ? OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
                                icon: const Icon(Icons.camera_alt, size: 16),
                                label: const Text('Edit Cover'),
                                onPressed: _uploadShopBanner, 
                              )
                            : OutlinedButton(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 15)),
                                onPressed: (){}, 
                                child: const Text('+ Follow')
                              )
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: const Text('ALL PRODUCTS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 14)),
                ),
              ),

              StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('products')
                    .where('seller_id', isEqualTo: widget.sellerId)
                    .where('status', isEqualTo: 'approved')
                    .snapshots(),
                builder: (context, prodSnapshot) {
                  if (prodSnapshot.connectionState == ConnectionState.waiting) {
                    return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                  }
                  if (!prodSnapshot.hasData || prodSnapshot.data!.docs.isEmpty) {
                    return SliverFillRemaining(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:[
                            Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.shade300),
                            const SizedBox(height: 10),
                            const Text('No products available in this shop yet.', style: TextStyle(color: Colors.grey)),
                          ]
                        )
                      )
                    );
                  }

                  var products = prodSnapshot.data!.docs;
                  products.sort((a, b) {
                    var dataA = a.data() as Map<String, dynamic>;
                    var dataB = b.data() as Map<String, dynamic>;
                    Timestamp? tA = dataA['timestamp'] as Timestamp?;
                    Timestamp? tB = dataB['timestamp'] as Timestamp?;
                    if (tA == null || tB == null) return 0;
                    return tB.compareTo(tA);
                  });

                  double screenWidth = MediaQuery.of(context).size.width;
                  int gridColumns = screenWidth > 900 ? 5 : (screenWidth > 600 ? 4 : 2);

                  return SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          var product = products[index];
                          Map<String, dynamic> data = product.data() as Map<String, dynamic>;
                          
                          // [FIXED] Null string prevention
                          String firstImage = '';
                          if (data['image_urls'] != null && (data['image_urls'] as List).isNotEmpty) {
                            firstImage = data['image_urls'][0].toString();
                          }
                          
                          String displayPrice = data['discount_price']?.toString() ?? data['price']?.toString() ?? '0';
                          int curP = int.tryParse(displayPrice) ?? 0;
                          int origP = int.tryParse(data['original_price']?.toString() ?? '0') ?? 0;
                          int discount = origP > curP ? (((origP - curP) / origP) * 100).round() : 0;

                          return InkWell(
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: product))),
                            child: Container(
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start, 
                                children:[
                                  Expanded(
                                    child: Stack(
                                      children:[
                                        Container(width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))), 
                                        if (discount > 0) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10))), child: Text('-$discount%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))))
                                      ]
                                    )
                                  ), 
                                  Padding(
                                    padding: const EdgeInsets.all(10.0), 
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start, 
                                      children:[
                                        Text(data['product_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis), 
                                        const SizedBox(height: 5), 
                                        Row(crossAxisAlignment: CrossAxisAlignment.end, children:[Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 5), if (discount > 0) Text('৳$origP', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10))])
                                      ]
                                    )
                                  )
                                ]
                              ),
                            ),
                          );
                        },
                        childCount: products.length,
                      )
                    ),
                  );
                }
              ),
            ],
          );
        }
      ),
    );
  }
}