import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'firebase_options.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
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
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';


Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("Background Message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    // [FIXED] সরাসরি MainScreen এর বদলে AuthWrapper এ যাবে
    home: AuthWrapper(), 
  ));
}

// ==========================================
// নতুন: Auth Checker / Splash Screen (Fixed Loading Issue & Super Admin)
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
    _checkUserRoleAndNavigate();
  }

  // এই ফাংশনটি চেক করবে ইউজার কে এবং তাকে তার পেজে পাঠিয়ে দিবে
  Future<void> _checkUserRoleAndNavigate() async {
    // অ্যাপ চালুর পর আধা সেকেন্ড অপেক্ষা করবে যাতে স্ক্রিন রেডি হয় এবং ফায়ারবেস সেশন রিস্টোর করতে পারে।
    await Future.delayed(const Duration(milliseconds: 800));

    User? user = FirebaseAuth.instance.currentUser;

    // যদি কেউ লগিন না থাকে, তবে সাধারণ কাস্টমার পেজ (Guest Mode) দেখাবে
    if (user == null) {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
      return;
    }

    try {
      // ইউজারের রোল ফায়ারবেস থেকে আনা হচ্ছে
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      
      if (!mounted) return;

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String role = data.containsKey('role') ? data['role'] : 'customer';

        // [FIXED] রোল অনুযায়ী সঠিক পেজে রিডাইরেক্ট (admin অথবা super_admin হলে অ্যাডমিন প্যানেলে যাবে)
        if (role == 'admin' || role == 'super_admin') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminMainScreen()));
        } else if (role == 'seller') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
        } else if (role == 'rider') {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
        } else {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
        }
      } else {
        // ফায়ারবেসে ডাটা না থাকলে ডিফল্ট কাস্টমার পেজ
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) {
      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // চেকিং চলার সময় স্ক্রিনে সুন্দর একটি স্প্ল্যাশ স্ক্রিন দেখাবে
    return const Scaffold(
      backgroundColor: Colors.deepOrange,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children:[
            Icon(Icons.shopping_cart_checkout, size: 80, color: Colors.white),
            SizedBox(height: 20),
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 10),
            Text('Loading D Shop...', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
          ],
        ),
      ),
    );
  }
}

// ==========================================
// মেইন স্ক্রিন (Customer Bottom Navigation Bar + Notification Setup)
// ==========================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages =[
    const ShopeeHome(), 
    const CategoryPage(),
    const CartPage(), 
    const UserDashboard(), 
  ];

  @override
  void initState() {
    super.initState();
    _setupPushNotifications();
  }

  // কাস্টমার অ্যাপে নোটিফিকেশন রিসিভ করার সেটআপ (Updated for Background Push)
  void _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // ১. Broadcast মেসেজ (সবার জন্য অফার) পাওয়ার জন্য 'all_users' টপিকে সাবস্ক্রাইব করা
    await messaging.subscribeToTopic('all_users');

    // ২. ইউজারের নির্দিষ্ট FCM Token ফায়ারবেসে সেভ করা (যাতে শুধু তাকে মেসেজ দেওয়া যায়)
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      String? token = await messaging.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
          'fcm_token': token,
        });
      }
    }

    // অ্যাপ চালু থাকা অবস্থায় নোটিফিকেশন এলে স্ন্যাকবার দেখাবে
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children:[
                Text(message.notification!.title ?? 'New Notification', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(message.notification!.body ?? ''),
              ],
            ),
            backgroundColor: Colors.deepOrange,
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
          )
        );
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
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('আপনার কার্ট খালি!', style: TextStyle(fontSize: 18, color: Colors.grey)));

          Map<String, List<QueryDocumentSnapshot>> groupedItems = {};
          double grandTotalTaka = 0;
          int totalSelectedCount = 0;
          double totalSaved = 0;

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

          return Column(
            children:[
              Expanded(
                child: ListView(
                  children:[
                    ...groupedItems.entries.map((entry) {
                      String sellerId = entry.key;
                      List<QueryDocumentSnapshot> items = entry.value;
                      bool isShopSelected = shopItemsAllSelected(items);

                      // এই দোকানের মোট টাকার হিসাব (ফ্রি শিপিং চেক করার জন্য)
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
                            // শপের হেডার
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
                                              for (var item in items) selectedItems.add(item.id);
                                            } else {
                                              selectedShops.remove(sellerId);
                                              for (var item in items) selectedItems.remove(item.id);
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
                            
                            // অ্যাডমিন কন্ট্রোলড ফ্রি শিপিং ব্যানার
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

                            // আইটেম লিস্ট
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
                                              // পার্সোনাল ডিলিট বাটন
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
                            }).toList(),
                            
                          ],
                        ),
                      );
                    }).toList(),
                    const SizedBox(height: 20),
                  ],
                ),
              ),

              // --- Bottom Navigation Order Bar ---
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
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  for (var doc in snapshot.data!.docs) selectedItems.add(doc.id);
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
                         // এখানে Checkout পেজে পাঠানোর লজিক, সাথে ফ্রি শিপিং ডাটা পাস করা হচ্ছে
                         Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(grandTotal: grandTotalTaka.toInt(), selectedItemIds: selectedItems.toList(), freeShippingThreshold: freeShippingThreshold)));
                      } : null,
                      child: Container(
                        height: 55, width: 120,
                        alignment: Alignment.center,
                        color: totalSelectedCount > 0 ? shopeeOrange : Colors.grey,
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
// ৫ নম্বর পেজ: Checkout Page (Fixed Brackets, Loading & Delivery Change)
// ==========================================
class CheckoutPage extends StatefulWidget {
  final int grandTotal; // শুধু প্রোডাক্টের দাম
  final List<String> selectedItemIds;
  final int freeShippingThreshold;
  
  const CheckoutPage({super.key, required this.grandTotal, required this.selectedItemIds, required this.freeShippingThreshold});
  
  @override 
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final Color shopeeOrange = const Color(0xFFEE4D2D);
  final Color shopeeGreen = const Color(0xFF00BFA5);
  
  String selectedPayment = 'Cash on Delivery';

  bool isLoadingData = true;
  Map<String, dynamic>? userAddress;
  List<Map<String, dynamic>> checkoutItems =[];
  Map<String, List<Map<String, dynamic>>> groupedItems = {};
  
  // স্টেট ম্যানেজমেন্টের জন্য ভেরিয়েবল
  Map<String, double> shopDeliveryFees = {}; // কোন শপের কত ডেলিভারি চার্জ
  Map<String, String> shopDistanceInfo = {}; // দূরত্ব ও সময়ের টেক্সট
  Map<String, String> shopDeliveryMethod = {}; // কোন শপের জন্য কোন মেথড সিলেক্ট করা
  
  double productTotal = 0;
  double totalSaved = 0;
  double finalGrandTotal = 0; // প্রোডাক্ট + সব শপের ডেলিভারি চার্জ

  @override
  void initState() {
    super.initState();
    _initializeCheckoutData();
  }

  // পেজ লোড হওয়ার আগেই সব ডাটা এবং দূরত্ব হিসাব করে নেওয়ার ফাংশন
  Future<void> _initializeCheckoutData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // ১. ইউজারের ঠিকানা আনা
    var addrSnap = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('addresses').where('is_default', isEqualTo: true).limit(1).get();
    if (addrSnap.docs.isNotEmpty) {
      userAddress = addrSnap.docs.first.data();
    }

    // ২. কার্টের আইটেমগুলো আনা
    var cartSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').get();
    for (var doc in cartSnapshot.docs) { 
      if (widget.selectedItemIds.contains(doc.id)) {
        Map<String, dynamic> itemData = doc.data() as Map<String, dynamic>;
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

    // ৩. শপ অনুযায়ী গ্রুপ করা এবং হিসাব করা
    for (var item in checkoutItems) {
      String sellerName = item['seller_name'] ?? 'Unknown Shop';
      if (!groupedItems.containsKey(sellerName)) groupedItems[sellerName] = [];
      groupedItems[sellerName]!.add(item);
      
      double price = double.tryParse(item['price'].toString()) ?? 0;
      int qty = int.tryParse(item['quantity'].toString()) ?? 1;
      productTotal += (price * qty);

      double origP = double.tryParse(item['original_price']?.toString() ?? price.toString()) ?? 0;
      if (origP > price) {
        totalSaved += ((origP - price) * qty);
      }
    }

    // ৪. গুগল ম্যাপ API থেকে দূরত্ব ও চার্জ আনা
    for (var entry in groupedItems.entries) {
      String shopName = entry.key;
      var firstItem = entry.value.first;
      double sLat = firstItem['seller_lat'] ?? 23.6062;
      double sLng = firstItem['seller_lng'] ?? 90.1345;

      // ডিফল্ট মেথড সেট করা
      shopDeliveryMethod[shopName] = 'Standard Delivery';

      // API কল
      var chargeData = await _calculateChargeFromAPI(sLat, sLng);
      
      // ফ্রি শিপিং চেক
      double thisShopTotal = entry.value.fold(0.0, (sum, i) => sum + ((double.tryParse(i['price'].toString()) ?? 0) * (int.tryParse(i['quantity'].toString()) ?? 1)));
      
      if (widget.freeShippingThreshold > 0 && thisShopTotal >= widget.freeShippingThreshold) {
        shopDeliveryFees[shopName] = 0.0;
        shopDistanceInfo[shopName] = "ফ্রি শিপিং উপভোগ করুন! (${chargeData['dist']})";
      } else {
        shopDeliveryFees[shopName] = chargeData['fee'];
        shopDistanceInfo[shopName] = "${chargeData['dist']} (${chargeData['time']})";
      }
    }

    _updateGrandTotal();
    
    setState(() {
      isLoadingData = false;
    });
  }

  // API কল করে ডাটা আনার ফাংশন (Web Error Handle করা হয়েছে)
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
          if (km <= conf['base_distance']) baseFee = conf['base_charge'].toDouble();
          else if (km <= conf['mid_distance']) baseFee = conf['mid_charge'].toDouble();
          else baseFee = conf['mid_charge'] + ((km - conf['mid_distance']) * conf['extra_per_km']);
        }
        return {'fee': baseFee, 'dist': element['distance']['text'], 'time': element['duration']['text']};
      }
    } catch (e) {
      return {'fee': baseFee, 'dist': 'দূরত্ব মাপা যায়নি', 'time': 'ওয়েব প্রিভিউ'};
    }
    return {'fee': baseFee, 'dist': 'অজানা দূরত্ব', 'time': ''};
  }

  // সর্বমোট টাকা হিসাব করা
  void _updateGrandTotal() {
    double totalFees = shopDeliveryFees.values.fold(0.0, (sum, fee) => sum + fee);
    finalGrandTotal = productTotal + totalFees;
  }

  // ডেলিভারি মেথড চেইঞ্জ করার বটম শিট
  void _showDeliveryMethodSelector(String shopName, double currentFee) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              const Text('Select Delivery Option', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              
              // Standard Option
              ListTile(
                onTap: () {
                  setState(() {
                    shopDeliveryMethod[shopName] = 'Standard Delivery';
                    if(shopDistanceInfo[shopName]!.contains('ফ্রি')) {
                       shopDeliveryFees[shopName] = 0;
                    } else {
                       shopDeliveryFees[shopName] = currentFee >= 100 ? currentFee - 50 : currentFee; 
                    }
                    _updateGrandTotal();
                  });
                  Navigator.pop(context);
                },
                leading: Icon(Icons.local_shipping, color: shopeeGreen),
                title: const Text('Standard Delivery', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Receive in 2-3 days'),
                trailing: Text(shopDistanceInfo[shopName]!.contains('ফ্রি') ? 'Free' : '৳${currentFee >= 100 ? (currentFee-50).toStringAsFixed(0) : currentFee.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                tileColor: shopDeliveryMethod[shopName] == 'Standard Delivery' ? Colors.grey.shade100 : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              const Divider(),
              
              // Express Option
              ListTile(
                onTap: () {
                  setState(() {
                    shopDeliveryMethod[shopName] = 'Express Delivery';
                    shopDeliveryFees[shopName] = (shopDeliveryFees[shopName] == 0 ? 60 : currentFee) + 50.0; 
                    _updateGrandTotal();
                  });
                  Navigator.pop(context);
                },
                leading: const Icon(Icons.flash_on, color: Colors.orange),
                title: const Text('Express Delivery', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Receive today or tomorrow'),
                trailing: Text('৳${((shopDeliveryFees[shopName] == 0 ? 60 : currentFee) + 50).toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                tileColor: shopDeliveryMethod[shopName] == 'Express Delivery' ? Colors.grey.shade100 : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ],
          ),
        );
      }
    );
  }

  // =====================================
  // আসল অর্ডার প্লেস করার ম্যাজিক ফাংশন
  // =====================================
  void _placeRealOrder() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || userAddress == null || checkoutItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে ডেলিভারি ঠিকানা যুক্ত করুন!'), backgroundColor: Colors.red));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      List<Map<String, dynamic>> itemsToOrder =[];
      for (var item in checkoutItems) {
        itemsToOrder.add({
          'product_name': item['product_name'],
          'price': item['price'],
          'quantity': item['quantity'],
          'seller_id': item['seller_id'] ?? 'unknown',
          'image_url': item['image_url'] ?? '',
        });
      }

      await FirebaseFirestore.instance.collection('orders').add({
        'user_id': user.uid,
        'items': itemsToOrder,
        'total_amount': finalGrandTotal.toInt(),
        'payment_method': selectedPayment,
        'status': 'Pending',
        'order_date': FieldValue.serverTimestamp(),
        'shipping_name': userAddress!['shipping_name'],
        'shipping_phone': userAddress!['shipping_phone'],
        'shipping_address_text': userAddress!['shipping_address_text'],
        'customer_lat': userAddress!['latitude'],
        'customer_lng': userAddress!['longitude'],
      });

      // [NEW] অর্ডার প্লেস হওয়ার পর অ্যাডমিনকে নোটিফিকেশন পাঠানো
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'New Order Received! 🛒',
        'message': '${userAddress!['shipping_name']} has placed a new order of ৳${finalGrandTotal.toInt()}.',
        'target_role': 'admin', // শুধু অ্যাডমিন পাবে
        'sent_at': FieldValue.serverTimestamp(),
      });

      // =========================================================
      // [NEW] ডাটাবেস থেকে স্পেসিফিক ভেরিয়েন্টের স্টক মাইনাস করা 
      // =========================================================
      for (var item in checkoutItems) {
        String? productId = item['product_id']; // ProductDetails এ সেভ করা id
        if (productId != null && productId.isNotEmpty) {
          int orderQty = int.tryParse(item['quantity'].toString()) ?? 1;
          String sColor = item['selected_color'] ?? '';
          String sSize = item['selected_size'] ?? '';

          DocumentReference pRef = FirebaseFirestore.instance.collection('products').doc(productId);

          // Transaction ব্যবহার করছি যাতে একসাথে একাধিক কাস্টমার কিনলে স্টক এলোমেলো না হয়
          await FirebaseFirestore.instance.runTransaction((transaction) async {
            DocumentSnapshot pSnap = await transaction.get(pRef);
            if (pSnap.exists) {
              Map<String, dynamic> pData = pSnap.data() as Map<String, dynamic>;
              int currentTotalStock = int.tryParse(pData['stock'].toString()) ?? 0;
              List<dynamic> variants = pData['variants'] ??[];

              // ভেরিয়েন্ট লিস্ট থেকে ম্যাচ করে স্টক মাইনাস করা
              for (int i = 0; i < variants.length; i++) {
                if (variants[i]['color'] == sColor && variants[i]['size'] == sSize) {
                  int vStock = int.tryParse(variants[i]['stock'].toString()) ?? 0;
                  variants[i]['stock'] = (vStock - orderQty) >= 0 ? (vStock - orderQty) : 0;
                  break; // পেয়ে গেলে আর লুপ ঘোরার দরকার নেই
                }
              }

              // ডাটাবেসে নতুন স্টক আপডেট করা
              transaction.update(pRef, {
                'stock': (currentTotalStock - orderQty) >= 0 ? (currentTotalStock - orderQty) : 0,
                'sales_count': FieldValue.increment(orderQty), // সেলস কাউন্টও বাড়িয়ে দিলাম
                'variants': variants
              });
            }
          });
        }
      }
      // =========================================================

      for (String docId in widget.selectedItemIds) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(docId).delete();
      }

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ

      // আকর্ষণীয় Order Success Popup!
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
              const Text('আপনার অর্ডারটি সফলভাবে প্লেস হয়েছে। আমরা খুব দ্রুত আপনার সাথে যোগাযোগ করব।', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.teal), padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const OrderHistoryPage())); 
                      },
                      child: const Text('View Order', style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false);
                      },
                      child: const Text('OK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
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
            Expanded(
              child: ListView(
                children:[
                  // Address Block
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

                  // Vendor Block
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
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children:[
                                                  Text('৳${item['price']} ', style: TextStyle(color: shopeeOrange, fontSize: 14)),
                                                  Text('x${item['quantity']}', style: const TextStyle(fontSize: 12, color: Colors.black54))
                                              ],
                                            )
                                          ],
                                        ),
                                      )
                                    ],
                                  ),
                                );
                            }).toList(),
                            
                            // Shipping Option Row (Clickable)
                            InkWell(
                              onTap: () => _showDeliveryMethodSelector(shopName, fee),
                              child: Container(
                                margin: const EdgeInsets.fromLTRB(15, 10, 15, 15), padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: const Color(0xFFF1FDFB), border: Border.all(color: shopeeGreen), borderRadius: BorderRadius.circular(4)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children:[
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children:[
                                        Text("রাস্তার দূরত্ব: $info", style: const TextStyle(fontSize: 11, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                                        const Icon(Icons.edit, size: 14, color: Colors.grey) // Edit Icon
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                      children:[
                                        Row(children:[
                                          Icon(method == 'Standard Delivery' ? Icons.local_shipping : Icons.flash_on, color: method == 'Standard Delivery' ? shopeeGreen : Colors.orange, size: 18), 
                                          const SizedBox(width: 8), 
                                          Text(method, style: TextStyle(color: method == 'Standard Delivery' ? shopeeGreen : Colors.orange, fontWeight: FontWeight.bold, fontSize: 13))
                                        ]),
                                        Text(fee == 0 ? 'Free' : '৳${fee.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))
                                      ]
                                    ),
                                  ]
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                  }).toList(),
                  
                  // Payment Method
                  Container(
                    margin: const EdgeInsets.only(top: 10), color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Padding(padding: EdgeInsets.only(left: 15, bottom: 5), child: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold))),
                        _buildPaymentOption('Cash on Delivery', Icons.local_shipping, Colors.teal),
                        const Divider(height: 1), _buildPaymentOption('bKash', Icons.account_balance_wallet, Colors.pink),
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
                      if(totalSaved > 0) Text('Saved ৳${totalSaved.toStringAsFixed(0)}', style: const TextStyle(color: Color(0xFFEE4D2D), fontSize: 12)),
                    ],
                  ),
                  const SizedBox(width: 15),
                  InkWell(
                    onTap: _placeRealOrder, // <--- এখানে আসল ফাংশন কল করা হলো
                    child: Container(height: 60, width: 130, alignment: Alignment.center, color: shopeeOrange, child: const Text('Place Order', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
                  )
                ],
              ),
            )
          ],
        ), // <--- এখানে Column ক্লোজ হলো
    ); // <--- এখানে Scaffold ক্লোজ হলো
  }

  Widget _buildPaymentOption(String title, IconData icon, Color iconColor) {
    return RadioListTile<String>(title: Row(children:[Icon(icon, color: iconColor), const SizedBox(width: 15), Text(title, style: const TextStyle(fontSize: 14))]), value: title, groupValue: selectedPayment, activeColor: const Color(0xFFEE4D2D), onChanged: (value) => setState(() => selectedPayment = value!));
  }
}

// ==========================================
// ৩ নম্বর পেজ: Product Details (Inline Variant Error & Auto Scroll)
// ==========================================
class ProductDetailsPage extends StatefulWidget {
  final QueryDocumentSnapshot product; 
  const ProductDetailsPage({super.key, required this.product});

  @override
  State<ProductDetailsPage> createState() => _ProductDetailsPageState();
}

class _ProductDetailsPageState extends State<ProductDetailsPage> {
  final GlobalKey _cartKey = GlobalKey();
  final GlobalKey _imageKey = GlobalKey();
  final GlobalKey _variantKey = GlobalKey(); 
  
  int _selectedImageIndex = 0; 
  bool _isDescExpanded = false; 
  bool _hasVariantError = false; 
  
  // নতুন ভেরিয়েবলসমূহ
  String? selectedColorName;
  String? selectedSizeName;
  String adminPhoneNumber = "01700000000"; 

  @override
  void initState() {
    super.initState();
    _saveToRecentlyViewed(); 
    _fetchAdminPhoneNumber(); 
  }

  Future<void> _fetchAdminPhoneNumber() async {
    try {
      var doc = await FirebaseFirestore.instance.collection('app_config').doc('store_details').get();
      if (doc.exists && doc.data() != null) {
        setState(() {
          adminPhoneNumber = doc['support_phone'] ?? "01700000000";
        });
      }
    } catch (e) {}
  }

  void runAddToCartAnimation(String imageUrl) {
    if (imageUrl.isEmpty) return;
    RenderBox? imageBox = _imageKey.currentContext?.findRenderObject() as RenderBox?;
    RenderBox? cartBox = _cartKey.currentContext?.findRenderObject() as RenderBox?;
    if (imageBox == null || cartBox == null) return;
    
    Offset imagePos = imageBox.localToGlobal(Offset.zero);
    Offset cartPos = cartBox.localToGlobal(Offset.zero);

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (context) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeInOutCubic,
          builder: (context, value, child) {
            double left = imagePos.dx + (cartPos.dx - imagePos.dx) * value;
            double top = imagePos.dy + (cartPos.dy - imagePos.dy) * value;
            double size = 200 * (1.0 - value);
            if (size < 20) size = 20;
            return Positioned(
              left: left, top: top, 
              child: Opacity(
                opacity: 1.0 - (value * 0.3), 
                child: ClipRRect(borderRadius: BorderRadius.circular(100), child: Image.network(imageUrl, width: size, height: size, fit: BoxFit.cover))
              )
            );
          },
        );
      },
    );
    Overlay.of(context).insert(entry);
    Future.delayed(const Duration(milliseconds: 700), () => entry?.remove());
  }

  void addToCart(BuildContext context, String imageUrl, int finalPrice, int currentStock, bool requireVariants, {bool isBuyNow = false}) async {
    User? user = FirebaseAuth.instance.currentUser;
    
    // =====================================
    // [RESTORED] লগিন না থাকলে সুন্দর পপ-আপ আসবে
    // =====================================
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
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.grey), padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () => Navigator.pop(context), 
                      child: const Text('Skip', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold))
                    )
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 12)),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage()));
                      }, 
                      child: const Text('Login Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                    )
                  ),
                ]
              )
            ],
          ),
        )
      );
      return; 
    }

    // =====================================
    // [NEW] ভেরিয়েন্ট চেক, অটো-স্ক্রল ও ব্লিঙ্ক এনিমেশন
    // =====================================
    if (requireVariants && (selectedColorName == null || selectedSizeName == null)) { 
      if (_variantKey.currentContext != null) {
        Scrollable.ensureVisible(_variantKey.currentContext!, alignment: 0.5, duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
      }
      setState(() => _hasVariantError = true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _hasVariantError = false);
      });
      return; 
    }

    // স্টক চেক
    if (currentStock < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দুঃখিত, এই ভেরিয়েন্টটি স্টকে নেই!'), backgroundColor: Colors.red));
      return;
    }

    if (!isBuyNow) runAddToCartAnimation(imageUrl);

    // কার্টে অ্যাড করার লজিক
    var cartRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart');
    var existingItem = await cartRef
        .where('product_id', isEqualTo: widget.product.id) // product_id সেভ হচ্ছে
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
        currentQty = (existingItem.docs.first.data() as Map<String, dynamic>)['quantity'] + 1;
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

      Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(
        grandTotal: finalPrice * currentQty, 
        selectedItemIds:[cartDocId], 
        freeShippingThreshold: freeShippingThreshold
      ))); 
    } 
    else { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item added to Cart! 🚀'), duration: Duration(seconds: 1))); 
    }
  }

  void _saveToRecentlyViewed() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var recentRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('recently_viewed');
    await recentRef.doc(widget.product.id).set({
      'product_id': widget.product.id,
      'category': widget.product['category'],
      'viewed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // =====================================
  // ছোট প্রোডাক্ট কার্ড বানানোর হেল্পার ফাংশন
  // =====================================
  Widget _buildMiniProductCard(QueryDocumentSnapshot doc, {bool isGrid = false}) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    String firstImage = images.isNotEmpty ? images[0] : '';
    
    String displayPrice = data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty ? data['discount_price'].toString() : data['price'].toString();
    int curP = int.tryParse(displayPrice) ?? 0;
    int origP = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int discount = origP > curP ? (((origP - curP) / origP) * 100).round() : 0;

    return InkWell(
      onTap: () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: doc)));
      },
      child: Container(
        width: isGrid ? null : 140,
        margin: isGrid ? null : const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Expanded(
              child: Stack(
                children:[
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                    child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(8)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey),
                  ),
                  if (discount > 0)
                    Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(8), bottomLeft: Radius.circular(8))), child: Text('-$discount%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  Text(data['product_name'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = widget.product.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    List<dynamic> variants = data.containsKey('variants') ? data['variants'] : [];
    String unit = data['variant_unit'] ?? '';
    
    int basePrice = int.tryParse(data['price'].toString()) ?? 0;
    int originalPrice = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int totalStock = int.tryParse(data['stock'].toString()) ?? 0;

    // ইউনিক কালার এবং সাইজ ফিল্টার করা
    Set<String> uniqueColors = {};
    Set<String> uniqueSizes = {};
    for (var v in variants) {
      if (v['color'] != 'Default') uniqueColors.add(v['color']);
      if (v['size'] != 'Default') uniqueSizes.add(v['size']);
    }
    bool requireVariants = uniqueColors.isNotEmpty || uniqueSizes.isNotEmpty;

    // ডাইনামিক প্রাইজ, স্টক এবং ইমেজ ক্যালকুলেশন
    int finalCurrentPrice = basePrice;
    int currentDisplayedStock = totalStock;
    String? activeColorImage;

    if (requireVariants) {
      try {
         // সিলেক্টেড ভেরিয়েন্ট খোঁজা
         var match = variants.firstWhere((v) => 
            (selectedColorName == null || v['color'] == selectedColorName) &&
            (selectedSizeName == null || v['size'] == selectedSizeName)
         , orElse: () => {});

         if (match.isNotEmpty) {
           if (selectedColorName != null && selectedSizeName != null) {
              finalCurrentPrice = basePrice + (match['price'] as int);
              currentDisplayedStock = match['stock'] as int;
           } else if (selectedColorName != null || selectedSizeName != null) {
              // যদি শুধু একটি সিলেক্ট করে, তবে ওই অনুযায়ী স্টক দেখাবে
              int tempStock = 0;
              for(var vx in variants) {
                if ((selectedColorName != null && vx['color'] == selectedColorName) || 
                    (selectedSizeName != null && vx['size'] == selectedSizeName)) {
                   tempStock += (vx['stock'] as int);
                }
              }
              currentDisplayedStock = tempStock;
           }
         }

         // কালার অনুযায়ী ছবি পরিবর্তন
         if (selectedColorName != null) {
            var colorMatch = variants.firstWhere((v) => v['color'] == selectedColorName && v['color_image_url'] != null, orElse: () => {});
            if(colorMatch.isNotEmpty) activeColorImage = colorMatch['color_image_url'];
         }
      } catch(e){}
    }

    String mainImage = activeColorImage ?? (images.isNotEmpty && images.length > _selectedImageIndex ? images[_selectedImageIndex] : '');
    int finalOriginalPrice = originalPrice > basePrice ? (originalPrice + (finalCurrentPrice - basePrice)) : 0;
    int discountPercent = finalOriginalPrice > finalCurrentPrice ? (((finalOriginalPrice - finalCurrentPrice) / finalOriginalPrice) * 100).round() : 0;
    String productCode = data['sku'] ?? 'N/A';

    return Scaffold(
      backgroundColor: Colors.grey.shade100, 
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20), onPressed: () => Navigator.pop(context)),
        actions:[
          IconButton(icon: const Icon(Icons.favorite_border, color: Colors.black), onPressed: () {}),
          IconButton(icon: const Icon(Icons.share, color: Colors.black), onPressed: () {}), 
          IconButton(key: _cartKey, icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())))
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
                        Center(child: Container(key: _imageKey, height: 300, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: mainImage.isNotEmpty ? Image.network(mainImage, fit: BoxFit.contain) : const Icon(Icons.image, size: 100, color: Colors.grey))),
                        const SizedBox(height: 15),
                        if (images.length > 1) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: images.length, itemBuilder: (context, index) { bool isSelected = _selectedImageIndex == index; return InkWell(onTap: () => setState(() { _selectedImageIndex = index; activeColorImage = null; }), child: Container(margin: const EdgeInsets.only(right: 10), height: 60, width: 60, decoration: BoxDecoration(border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 1.5), borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(images[index]), fit: BoxFit.cover)))); })),
                        const SizedBox(height: 20),
                        
                        Text(data['product_name'] ?? 'Product Name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
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
                  
                  // =====================================
                  // ভেরিয়েন্ট সিলেকশন (Matrix Data)
                  // =====================================
                  if (requireVariants)
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
                            Padding(padding: const EdgeInsets.only(bottom: 15), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.warning, color: Colors.red, size: 18), SizedBox(width: 5), Text('দয়া করে সাইজ ও কালার সিলেক্ট করুন', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),])),

                          if(uniqueColors.isNotEmpty) ...[
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
                          if(uniqueSizes.isNotEmpty) ...[
                            Text('Select Size / Option ($unit)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 10), 
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
                  const SizedBox(height: 10),

                  // =====================================
                  // RESTORED: শপ ডিটেলস (সেলার ইনফো এবং ভিউ শপ বাটন)
                  // =====================================
                  Container(
                    color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Row(
                      children:[
                        CircleAvatar(
                          radius: 25, backgroundColor: Colors.teal.shade50, 
                          child: const Icon(Icons.storefront, color: Colors.teal, size: 28)
                        ), 
                        const SizedBox(width: 15),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection('users').doc(data['seller_id']).get(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data!.exists) {
                                var shopData = snapshot.data!.data() as Map<String, dynamic>;
                                String shopName = shopData.containsKey('shop_name') && shopData['shop_name'].toString().isNotEmpty ? shopData['shop_name'] : shopData['name'] ?? 'Unknown Shop';
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start, 
                                  children:[
                                    Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis), 
                                    Row(children: const[Icon(Icons.verified, color: Colors.green, size: 14), SizedBox(width: 4), Text('Verified Shop', style: TextStyle(color: Colors.green, fontSize: 12))])
                                  ]
                                );
                              }
                              return const Text('Loading shop info...', style: TextStyle(color: Colors.grey, fontSize: 12));
                            }
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () {
                            if (data['seller_id'] != null) {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => ShopPage(sellerId: data['seller_id'])));
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop details not found!')));
                            }
                          }, 
                          style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange), foregroundColor: Colors.deepOrange), 
                          child: const Text('View Shop')
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // Product Description & Details
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
                              Text(data.containsKey('description') && data['description'].toString().isNotEmpty ? data['description'] : 'No description available.', style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5), maxLines: _isDescExpanded ? null : 4, overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis),
                              const SizedBox(height: 5),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children:[Text(_isDescExpanded ? 'Show Less' : 'Read More', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)), Icon(_isDescExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.teal)])
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // =====================================
                  // RESTORED: More from this Shop
                  // =====================================
                  if (data['seller_id'] != null)
                    Container(
                      color: Colors.white, padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children:[
                              const Text('MORE FROM THIS SHOP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                              Text('See All >', style: TextStyle(color: Colors.deepOrange.shade400, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 15),
                          SizedBox(
                            height: 180,
                            child: StreamBuilder(
                              stream: FirebaseFirestore.instance.collection('products')
                                  .where('seller_id', isEqualTo: data['seller_id'])
                                  .where('status', isEqualTo: 'approved')
                                  .limit(10) // সর্বোচ্চ ১০টি আনবে
                                  .snapshots(),
                              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                                 if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                                 // এই সেম প্রোডাক্টটি লিস্ট থেকে বাদ দেওয়া
                                 var docs = snapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                                 if (docs.isEmpty) return const Text('No other products from this shop.', style: TextStyle(color: Colors.grey));
                                 
                                 return ListView.builder(
                                   scrollDirection: Axis.horizontal,
                                   itemCount: docs.length,
                                   itemBuilder: (context, index) => _buildMiniProductCard(docs[index])
                                 );
                              }
                            )
                          )
                        ]
                      )
                    ),
                  const SizedBox(height: 10),

                  // =====================================
                  // RESTORED: Similar Products
                  // =====================================
                  Container(
                    color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                         const Text('SIMILAR PRODUCTS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                         const SizedBox(height: 15),
                         StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('products')
                                .where('category', isEqualTo: data['category'])
                                .where('status', isEqualTo: 'approved')
                                .limit(10)
                                .snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                               if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                               var docs = snapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                               if (docs.isEmpty) return const Text('No similar products found.', style: TextStyle(color: Colors.grey));
                               
                               return GridView.builder(
                                 shrinkWrap: true,
                                 physics: const NeverScrollableScrollPhysics(), // স্ক্রল অফ করা, যাতে মেইন পেজ স্ক্রল হয়
                                 gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                   crossAxisCount: 2, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10
                                 ),
                                 itemCount: docs.length,
                                 itemBuilder: (context, index) => _buildMiniProductCard(docs[index], isGrid: true)
                               );
                            }
                          )
                      ]
                    )
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ),
          
          // Add to Cart / Buy Now Bar
          Container(
            padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, boxShadow:[BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, -5))]),
            child: Row(
              children:[
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: currentDisplayedStock > 0 ? Colors.deepOrange : Colors.grey, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: currentDisplayedStock > 0 ? () => addToCart(context, mainImage, finalCurrentPrice, currentDisplayedStock, requireVariants, isBuyNow: false) : null, child: const Text('ADD TO CART', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 15),
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: currentDisplayedStock > 0 ? Colors.teal : Colors.grey, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: currentDisplayedStock > 0 ? () => addToCart(context, mainImage, finalCurrentPrice, currentDisplayedStock, requireVariants, isBuyNow: true) : null, child: const Text('BUY NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// ২ নম্বর পেজ: Home Page (Ultra Smart Recommendation Engine)
// ==========================================
class ShopeeHome extends StatefulWidget {
  const ShopeeHome({super.key});

  @override
  State<ShopeeHome> createState() => _ShopeeHomeState();
}

class _ShopeeHomeState extends State<ShopeeHome> {
  late PageController _bannerController; // স্লাইডার কন্ট্রোল করার জন্য
  int _currentBannerPage = 0; // বর্তমান স্লাইড নম্বর ট্র্যাক করার জন্য
  Timer? _bannerTimer; // টাইমার রাখার জন্য (Timer ইম্পোর্ট করতে হতে পারে)
  String searchQuery = '';
  String selectedCategoryFilter = ''; 
  final TextEditingController searchController = TextEditingController();

  // =====================================
  // Algolia Setup (REST API - No package required!)
  // =====================================
  final String algoliaAppId = 'WULDWCKKQ3'; // <--- এখানে আপনার Algolia Application ID বসান
  final String algoliaSearchKey = '59964acedc064ab0f9fcbafd2b567aec'; // <--- এখানে Search-Only API Key বসান

  List<Map<String, dynamic>> algoliaSearchResults =[];
  bool isSearchingAlgolia = false;

  // Algolia তে সার্চ করার ফাংশন (Direct API Call)
  Future<void> _performAlgoliaSearch(String query) async {
    if (query.isEmpty) {
      setState(() {
        algoliaSearchResults.clear();
        isSearchingAlgolia = false;
      });
      return;
    }

    setState(() => isSearchingAlgolia = true);

    try {
      // 'products' হলো আপনার Algolia Index এর নাম
      String url = 'https://$algoliaAppId-dsn.algolia.net/1/indexes/products/query';

      var response = await http.post(
        Uri.parse(url),
        headers: {
          'X-Algolia-Application-Id': algoliaAppId,
          'X-Algolia-API-Key': algoliaSearchKey,
          'Content-Type': 'application/json; charset=UTF-8',
        },
        body: json.encode({
          'params': 'query=$query'
        }),
      );

      if (response.statusCode == 200) {
        var data = json.decode(response.body);
        List<dynamic> hits = data['hits'];

        List<Map<String, dynamic>> results = hits.map((hit) {
          Map<String, dynamic> item = Map<String, dynamic>.from(hit);
          return item; // Algolia রেজাল্টে objectID অটোমেটিক থাকে
        }).toList();

        setState(() {
          algoliaSearchResults = results;
          isSearchingAlgolia = false;
        });
      } else {
        setState(() => isSearchingAlgolia = false);
        print("Algolia API Error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => isSearchingAlgolia = false);
      print("Algolia Search Error: $e");
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

    // ৫ সেকেন্ড পর পর অটো স্লাইড
    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (_bannerController.hasClients) {
        // যদি শেষ পেজে থাকে তবে এনিমেশন ছাড়া ১ নম্বর পেজে যাবে, তারপর আবার স্লাইড হবে
        // অথবা সহজ সমাধান হিসেবে nextPage ব্যবহার করা
        _bannerController.nextPage(
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel(); // অ্যাপ মেমরি ক্লিন রাখার জন্য
    _bannerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    
    double screenWidth = MediaQuery.of(context).size.width;
    int gridColumns = 2; 
    if (screenWidth > 1000) { gridColumns = 5; } 
    else if (screenWidth > 700) { gridColumns = 4; } 
    else if (screenWidth > 500) { gridColumns = 3; }

    return Scaffold(
      backgroundColor: Colors.grey[100], 
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, elevation: 0,
        title: const Text('D Shop', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        actions:[
          // নতুন নোটিফিকেশন আইকন
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.white), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerNotificationPage()))
          ),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage()))
          )
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
                  if (snapshot.hasData && snapshot.data!.exists) return Text(snapshot.data!['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                  return const Text('Customer', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18));
                },
              ),
              accountEmail: Text(currentUser?.email ?? 'No Email'),
              currentAccountPicture: const CircleAvatar(backgroundColor: Colors.white, child: Icon(Icons.person, size: 40, color: Colors.deepOrange)),
            ),
            ListTile(leading: const Icon(Icons.home), title: const Text('Home'), onTap: () => Navigator.pop(context)),
            ListTile(leading: const Icon(Icons.history), title: const Text('My Orders'), onTap: () {}),
            ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () async { await FirebaseAuth.instance.signOut(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));}),
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
                      onChanged: (value) => setState(() => searchQuery = value.toLowerCase().trim()),
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
                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('banners').snapshots(), 
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                // ১. একটিভ ব্যানারগুলো ফিল্টার করা হচ্ছে
                                var activeDocs = snapshot.data!.docs.where((doc) {
                                  Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                  return data.containsKey('isActive') ? data['isActive'] == true : true;
                                }).toList();

                                // যদি কোনো একটিভ ব্যানার না থাকে তবে ডিফল্ট ব্যানার দেখাবে
                                if (activeDocs.isEmpty) return _buildDefaultBanner(); 

                                return SizedBox(
                                  height: 160,
                                  child: PageView.builder(
                                    controller: _bannerController,
                                    // ২. অসীম লুপের জন্য রিয়েল ইনডেক্স লজিক
                                    itemBuilder: (context, index) {
                                      int realIndex = index % activeDocs.length; 

                                      return Container(
                                        margin: const EdgeInsets.all(15),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(10),
                                          image: DecorationImage(
                                            image: NetworkImage(activeDocs[realIndex]['image_url']),
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      );
                                    },
                                    // ৩. ইউজার হাত দিয়ে স্লাইড করলে বর্তমান পেজ আপডেট রাখা
                                    onPageChanged: (index) {
                                      _currentBannerPage = index;
                                    },
                                  ),
                                );
                              }
                              // ডাটা লোড হওয়ার সময় বা ডাটা না থাকলে ডিফল্ট ব্যানার
                              return _buildDefaultBanner(); 
                            },
                          ),

                          // ক্যাটাগরি সেকশন
                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('categories').snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              return SizedBox(
                                height: 125, // <--- হাইট ১০৫ থেকে ১২৫ করা হয়েছে
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

                          // ফ্ল্যাশ সেল সেকশন
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), 
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                              children:[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), 
                                  decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(5)), 
                                  child: const Text('FLASH SALE', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange))
                                ), 
                                const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey)
                              ]
                            )
                          ),

                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').where('is_flash_sale', isEqualTo: true).snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                return SizedBox(
                                  height: 180, 
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), 
                                    itemCount: snapshot.data!.docs.length, 
                                    itemBuilder: (context, index) => _buildProductCardFirebase(context, snapshot.data!.docs[index], isHorizontal: true)
                                  )
                                );
                              }
                              return const SizedBox.shrink(); 
                            }
                          ),
                        ],

                        // ====================================================
                        // SMART ENGINE: NEW PRODUCTS + RECOMMENDATIONS (Your Idea)
                        // ====================================================
                        StreamBuilder(
                          // ইউজারের হিস্ট্রি চেক করছি প্রথমে
                          stream: currentUser != null
                              ? FirebaseFirestore.instance.collection('users').doc(currentUser.uid).collection('recently_viewed').orderBy('viewed_at', descending: true).limit(3).snapshots()
                              : const Stream<QuerySnapshot>.empty(),
                          builder: (context, AsyncSnapshot<QuerySnapshot> recentSnapshot) {
                            
                            bool hasHistory = recentSnapshot.hasData && recentSnapshot.data!.docs.isNotEmpty;
                            List<String> preferredCategories =[];

                            if (hasHistory) {
                              for (var doc in recentSnapshot.data!.docs) {
                                if (doc.data().toString().contains('category') && doc['category'] != null) {
                                  preferredCategories.add(doc['category']);
                                }
                              }
                            }

                            // মূল প্রোডাক্ট স্ট্রিম (সব প্রোডাক্ট)
                            return StreamBuilder(
                              stream: FirebaseFirestore.instance.collection('products').orderBy('timestamp', descending: true).limit(30).snapshots(),
                              builder: (context, AsyncSnapshot<QuerySnapshot> prodSnapshot) {
                                if (prodSnapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()));
                                if (!prodSnapshot.hasData || prodSnapshot.data!.docs.isEmpty) return const SizedBox.shrink();

                                var docs = prodSnapshot.data!.docs;
                                
                                // ফিল্টার লজিক (Search বা Category Select করলে)
                                docs = docs.where((doc) {
                                  Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                  return data.containsKey('status') && data['status'] == 'approved';
                                }).toList();

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
                                  docs = docs.where((doc) {
                                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                                    String category = data.containsKey('category') ? data['category'].toString() : '';
                                    return category == selectedCategoryFilter;
                                  }).toList();
                                }

                                bool isSearchingOrFiltering = searchQuery.isNotEmpty || selectedCategoryFilter.isNotEmpty;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children:[
                                    // হেডার
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10), 
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                                        children:[
                                          Text(searchQuery.isNotEmpty ? 'SEARCH RESULTS' : (selectedCategoryFilter.isNotEmpty ? '$selectedCategoryFilter PRODUCTS' : 'NEW PRODUCTS'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                                          if(!isSearchingOrFiltering) const Text('See all', style: TextStyle(color: Colors.deepOrange, fontSize: 14))
                                        ]
                                      )
                                    ),

                                    // যদি সার্চ করে বা ফিল্টার করে বা ইউজারের হিস্ট্রি না থাকে -> বড় গ্রিড দেখাবে
                                    if (isSearchingOrFiltering || !hasHistory)
                                      GridView.builder(
                                        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15),
                                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10),
                                        itemCount: docs.length,
                                        itemBuilder: (context, index) => _buildProductCardFirebase(context, docs[index]),
                                      )
                                    // যদি ইউজারের হিস্ট্রি থাকে -> নিউ প্রোডাক্ট এক লাইনে স্লাইডার হয়ে যাবে
                                    else
                                      SizedBox(
                                        height: 200, 
                                        child: ListView.builder(
                                          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), 
                                          itemCount: docs.length > 10 ? 10 : docs.length, // সর্বোচ্চ ১০টি নতুন প্রোডাক্ট দেখাবে
                                          itemBuilder: (context, index) => _buildProductCardFirebase(context, docs[index], isHorizontal: true)
                                        )
                                      ),

                                    // RECOMMENDED FOR YOU (শুধুমাত্র যদি হিস্ট্রি থাকে এবং সার্চ না করে)
                                    if (hasHistory && !isSearchingOrFiltering && preferredCategories.isNotEmpty) ...[
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(15, 25, 15, 10),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children:[
                                            Text('RECOMMENDED FOR YOU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            Icon(Icons.auto_awesome, color: Colors.deepOrange, size: 20)
                                          ]
                                        )
                                      ),
                                      StreamBuilder(
                                        stream: FirebaseFirestore.instance.collection('products')
                                            .where('status', isEqualTo: 'approved')
                                            .where('category', whereIn: preferredCategories)
                                            .snapshots(),
                                        builder: (context, AsyncSnapshot<QuerySnapshot> recSnapshot) {
                                          if (!recSnapshot.hasData || recSnapshot.data!.docs.isEmpty) return const SizedBox.shrink();

                                          return GridView.builder(
                                            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(horizontal: 15),
                                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10),
                                            itemCount: recSnapshot.data!.docs.length,
                                            itemBuilder: (context, index) => _buildProductCardFirebase(context, recSnapshot.data!.docs[index]),
                                          );
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

  // আপডেট করা স্ট্যাটিক ক্যাটাগরি (বক্স ডিজাইন)
  Widget _buildStaticCategory(String label, IconData icon, Color iconColor) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { setState(() { selectedCategoryFilter = isSelected ? '' : label; }); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[
          Container(
            width: 70, height: 70, // <--- সাইজ বড় করা হয়েছে
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(15), // <--- গোল এর বদলে রাউন্ডেড বক্স
              border: Border.all(
                color: isSelected ? Colors.deepOrange : Colors.transparent, 
                width: 2.5
              )
            ),
            child: Center(child: Icon(icon, color: iconColor, size: 35)), // <--- আইকন বড় করা হয়েছে
          ), 
          const SizedBox(height: 8), 
          SizedBox(
            width: 75, 
            child: Text(
              label, 
              textAlign: TextAlign.center, 
              style: TextStyle(
                fontSize: 10, // ফন্ট সাইজ একটু বড় করা হয়েছে
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, 
                color: isSelected ? Colors.deepOrange : Colors.black
              ), 
              maxLines: 2, 
              overflow: TextOverflow.ellipsis
            )
          )
        ])
      ),
    );
  }

  // আপডেট করা ডাইনামিক ক্যাটাগরি (বক্স ডিজাইন)
  Widget _buildDynamicCategory(String label, String imageUrl) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { setState(() { selectedCategoryFilter = isSelected ? '' : label; }); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[
          Container(
            width: 70, height: 70, // <--- সাইজ বড় করা হয়েছে
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(15), // <--- গোল এর বদলে রাউন্ডেড বক্স
              border: Border.all(
                color: isSelected ? Colors.deepOrange : Colors.transparent, 
                width: 2.5
              ),
              // শ্যাডো দিলে দেখতে আরও প্রিমিয়াম লাগবে
              boxShadow:[
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 5, offset: const Offset(0, 3))
              ]
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12), // <--- ছবির চারপাশ রাউন্ড করার জন্য
              child: Image.network(imageUrl, fit: BoxFit.cover)
            ),
          ), 
          const SizedBox(height: 8), 
          SizedBox(
            width: 75, 
            child: Text(
              label, 
              textAlign: TextAlign.center, 
              style: TextStyle(
                fontSize: 10, 
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, 
                color: isSelected ? Colors.deepOrange : Colors.black
              ), 
              maxLines: 2, 
              overflow: TextOverflow.ellipsis
            )
          )
        ])
      ),
    );
  }

  Widget _buildProductCardFirebase(BuildContext context, QueryDocumentSnapshot product, {bool isHorizontal = false}) {
    Map<String, dynamic> data = product.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    String firstImage = images.isNotEmpty ? images[0] : '';
    
    bool isFlashSale = data.containsKey('is_flash_sale') ? data['is_flash_sale'] : false;
    String displayPrice = isFlashSale && data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty ? data['discount_price'].toString() : data['price'].toString();

    int currentPrice = int.tryParse(displayPrice) ?? 0;
    int originalPrice = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int discountPercent = 0;
    if (originalPrice > currentPrice) discountPercent = (((originalPrice - currentPrice) / originalPrice) * 100).round();

    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: product))),
      child: Container(
        width: isHorizontal ? 140 : null, margin: isHorizontal ? const EdgeInsets.only(right: 10) : EdgeInsets.zero,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Expanded(
            child: Stack(children:[
              Container(width: double.infinity, decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), child: firstImage.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(firstImage, fit: BoxFit.cover)) : const Center(child: Icon(Icons.image, size: 50, color: Colors.grey))), 
              if (discountPercent > 0) Positioned(top: 0, right: 0, child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: const BoxDecoration(color: Colors.red, borderRadius: BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10))), child: Text('-$discountPercent%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))))
            ])
          ), 
          Padding(padding: const EdgeInsets.all(10.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(data['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis), const SizedBox(height: 5), Row(crossAxisAlignment: CrossAxisAlignment.end, children:[Text('৳$displayPrice', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 14)), const SizedBox(width: 5), if (discountPercent > 0) Text('৳$originalPrice', style: const TextStyle(color: Colors.grey, decoration: TextDecoration.lineThrough, fontSize: 10))])]))
        ]),
      ),
    );
  }

  // এই অংশটি ক্লাসের ভেতরে একদম নিচে বসান
  Widget _buildDefaultBanner() {
    return Container(
      margin: const EdgeInsets.all(15),
      height: 120,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: LinearGradient(
          colors: [Colors.orange.shade200, Colors.deepOrange.shade100],
        ),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'WELCOME TO D SHOP!',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16),
                ),
                Text(
                  'Explore Best Products',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
          ),
          const Spacer(),
          Icon(Icons.shopping_bag, size: 80, color: Colors.deepOrange.withOpacity(0.3)),
          const SizedBox(width: 20),
        ],
      ),
    );
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
                onPressed: () async {
                  SharedPreferences prefs = await SharedPreferences.getInstance();
                  await prefs.clear();
                  await FirebaseAuth.instance.signOut(); 
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
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
// লগিন পেজ (Login Page with Super Admin Support)
// ==========================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // লগিন ফাংশন (Smart Role-based Login)
  void login() async {
    if (emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter email and password!')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      // ফায়ারবেস লগিন
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(), 
        password: passwordController.text.trim()
      );
      
      // ইউজারের রোল (Role) খোঁজা
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
      
      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login Successful!')));
      
      // রোল অনুযায়ী পেজে পাঠানো
      String role = 'customer';
      if (userDoc.exists && (userDoc.data() as Map<String, dynamic>).containsKey('role')) {
        role = userDoc['role'];
      }

      // [FIXED] admin অথবা super_admin হলে অ্যাডমিন প্যানেলে যাবে
      if (role == 'admin' || role == 'super_admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminMainScreen()));
      } else if (role == 'seller') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
      } else if (role == 'rider') { 
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.orange[50], 
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0), 
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center, 
            children:[
              const Icon(Icons.shopping_cart_checkout, size: 80, color: Colors.deepOrange), 
              const SizedBox(height: 20), 
              const Text('Welcome Back', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)), 
              const SizedBox(height: 40), 
              
              TextField(
                controller: emailController, 
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white)
              ), 
              const SizedBox(height: 15), 
              
              TextField(
                controller: passwordController, 
                obscureText: true, 
                decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white)
              ), 
              const SizedBox(height: 30), 
              
              SizedBox(
                width: double.infinity, height: 50, 
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                  onPressed: login, 
                  child: const Text('LOGIN', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
                )
              ), 
              const SizedBox(height: 20), 
              
              TextButton(
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupPage())), 
                child: const Text("Don't have an account? Sign Up", style: TextStyle(color: Colors.deepOrange, fontSize: 16))
              )
            ]
          )
        )
      )
    );
  }
}

// ==========================================
// অ্যাডভান্সড সাইন-আপ পেজ (Shop Name + Role Based + Map)
// ==========================================
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController nameController = TextEditingController(); 
  final TextEditingController emailController = TextEditingController(); 
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController shopNameController = TextEditingController(); // নতুন: শপের নাম
  
  String selectedRole = 'customer'; 
  LatLng? vendorLocation; 

  void createAccount() async {
    if (nameController.text.isEmpty || emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সবগুলো ঘর পূরণ করুন!')));
      return;
    }

    // সেলার হলে শপের নাম দেওয়া বাধ্যতামূলক
    if (selectedRole == 'seller' && shopNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সেলার হিসেবে আপনার শপের নাম দেওয়া বাধ্যতামূলক!')));
      return;
    }

    if (selectedRole != 'customer' && vendorLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সেলার বা রাইডার হিসেবে যুক্ত হতে ম্যাপে লোকেশন সেট করা বাধ্যতামূলক! 📍')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(), 
        password: passwordController.text.trim()
      );
      
      Map<String, dynamic> userData = {
        'name': nameController.text.trim(), 
        'email': emailController.text.trim(), 
        'role': selectedRole, 
        'created_at': FieldValue.serverTimestamp()
      };

      if (selectedRole != 'customer') {
        userData['latitude'] = vendorLocation!.latitude;
        userData['longitude'] = vendorLocation!.longitude;
        userData['status'] = 'pending'; 
      }

      // যদি সেলার হয়, তবে শপের নাম ডাটাবেসে সেভ হবে
      if (selectedRole == 'seller') {
        userData['shop_name'] = shopNameController.text.trim();
      }

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set(userData);
      
      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Created Successfully! 🎉')));
      
      if (selectedRole == 'seller') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
      } else if (selectedRole == 'rider') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) { 
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'))); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Create Account', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0), 
        child: Column(
          children:[
            Container(
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.all(5),
              child: Row(
                children:[
                  _buildRoleOption('Customer', 'customer', Icons.person),
                  _buildRoleOption('Seller', 'seller', Icons.storefront),
                  _buildRoleOption('Rider', 'rider', Icons.motorcycle),
                ],
              ),
            ),
            const SizedBox(height: 25),

            TextField(controller: nameController, decoration: InputDecoration(labelText: 'Full Name', prefixIcon: const Icon(Icons.badge), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), 
            const SizedBox(height: 15), 

            // সেলার সিলেক্ট করলে শপের নামের বক্স আসবে
            if (selectedRole == 'seller') ...[
              TextField(
                controller: shopNameController, 
                decoration: InputDecoration(labelText: 'Shop Name', prefixIcon: const Icon(Icons.store), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))
              ),
              const SizedBox(height: 15),
            ],

            TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email Address', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), 
            const SizedBox(height: 15), 
            TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password (min 6 chars)', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), 
            const SizedBox(height: 20), 

            if (selectedRole != 'customer') ...[
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.orange.shade50, border: Border.all(color: Colors.deepOrange.shade200), borderRadius: BorderRadius.circular(10)),
                child: Row(
                  children:[
                    const Icon(Icons.location_on, color: Colors.deepOrange),
                    const SizedBox(width: 10),
                    Expanded(child: Text(vendorLocation == null ? 'Location is required for $selectedRole' : 'Location Saved Successfully ✅', style: TextStyle(color: vendorLocation == null ? Colors.black87 : Colors.green, fontWeight: FontWeight.bold))),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: vendorLocation == null ? Colors.deepOrange : Colors.green),
                      onPressed: () async {
                        LatLng? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const LocationPickerScreen()));
                        if (result != null) setState(() { vendorLocation = result; });
                      }, 
                      child: Text(vendorLocation == null ? 'Set on Map' : 'Change', style: const TextStyle(color: Colors.white))
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: createAccount, child: const Text('CREATE ACCOUNT', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
          ]
        )
      )
    );
  }

  Widget _buildRoleOption(String title, String role, IconData icon) {
    bool isSelected = selectedRole == role;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() { 
            selectedRole = role; 
            vendorLocation = null; 
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? Colors.deepOrange : Colors.transparent, borderRadius: BorderRadius.circular(8), boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 5)] :[]),
          child: Column(children:[Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20), const SizedBox(height: 5), Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))]),
        ),
      ),
    );
  }
}

// ==========================================
// ম্যাপ থেকে লোকেশন পিক করার স্ক্রিন (সেলার/রাইডারের জন্য)
// ==========================================
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng _currentPosition = const LatLng(23.6062, 90.1345); // দোহার
  GoogleMapController? _mapController;

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
    setState(() { _currentPosition = LatLng(position.latitude, position.longitude); });
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin Your Location'), backgroundColor: Colors.deepOrange),
      body: Stack(
        alignment: Alignment.center,
        children:[
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 15),
            onMapCreated: (GoogleMapController controller) => _mapController = controller,
            onCameraMove: (position) => _currentPosition = position.target,
            myLocationEnabled: false,
            zoomControlsEnabled: false,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 35.0), 
            child: Icon(Icons.location_on, size: 50, color: Colors.deepOrange),
          ),
          Positioned(
            bottom: 20, left: 20, right: 20,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 15)),
              onPressed: () {
                // পিন করা লোকেশনটি নিয়ে আগের পেজে ফেরত যাবে
                Navigator.pop(context, _currentPosition);
              },
              child: const Text('CONFIRM LOCATION', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// সেলার মেইন স্ক্রিন (Bottom Nav) - (Missing Class Fixed)
// ==========================================
class SellerMainScreen extends StatefulWidget { const SellerMainScreen({super.key}); @override State<SellerMainScreen> createState() => _SellerMainScreenState(); }
class _SellerMainScreenState extends State<SellerMainScreen> {
  int _selectedIndex = 0;
  final List<Widget> _pages =[const SellerDashboard(), const ProductManagement(), const SellerOrderManagement(), const PaymentsReports(), const SellerProfile()];
  @override Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed, currentIndex: _selectedIndex, selectedItemColor: Colors.deepOrange, unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const[BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'Stats'), BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'Products'), BottomNavigationBarItem(icon: Icon(Icons.shopping_bag_outlined), label: 'Orders'), BottomNavigationBarItem(icon: Icon(Icons.analytics_outlined), label: 'Reports'), BottomNavigationBarItem(icon: Icon(Icons.store_mall_directory_outlined), label: 'Profile')],
      ),
    );
  }
}

// ==========================================
// সেলার ড্যাশবোর্ড: রিয়েল ডাটা + Smart Product Insights
// ==========================================
class SellerDashboard extends StatefulWidget {
  const SellerDashboard({super.key});

  @override
  State<SellerDashboard> createState() => _SellerDashboardState();
}

class _SellerDashboardState extends State<SellerDashboard> {
  String _selectedFilter = 'Low Stock'; // ডিফল্ট ফিল্টার

  @override 
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, 
        title: const Text('D Shop Seller', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        actions:[IconButton(icon: const Icon(Icons.notifications_none, color: Colors.white), onPressed: () {})]
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            // =====================================
            // Header: Seller Profile
            // =====================================
            FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(currentUser.uid).get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                var data = snapshot.data!.data() as Map<String, dynamic>;
                String shopName = data.containsKey('shop_name') && data['shop_name'].toString().isNotEmpty ? data['shop_name'] : data['name'] ?? 'Seller';
                String profileImg = data['profile_image_url'] ?? '';

                return Row(
                  children:[
                    CircleAvatar(
                      radius: 30, 
                      backgroundColor: Colors.orange.shade100, 
                      backgroundImage: profileImg.isNotEmpty ? NetworkImage(profileImg) : null,
                      child: profileImg.isEmpty ? const Icon(Icons.store, color: Colors.deepOrange, size: 30) : null
                    ), 
                    const SizedBox(width: 15), 
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children:[
                        Text(shopName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
                        Text('Seller ID: #${currentUser.uid.substring(0, 6).toUpperCase()}', style: const TextStyle(color: Colors.grey))
                      ]
                    )
                  ]
                );
              }
            ),
            const SizedBox(height: 25),

            // =====================================
            // Stats & Quick Actions
            // =====================================
            const Text('Overall Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(children:[
              _buildStatCard("Today's Sales", "৳০", Colors.teal[50]!, Colors.teal), 
              const SizedBox(width: 15), 
              _buildStatCard("Active Orders", "০", Colors.orange[50]!, Colors.orange)
            ]),
            const SizedBox(height: 25),
            
            const Text('QUICK ACTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), 
            const SizedBox(height: 10),
            Row(
              children:[
                _buildQuickAction(Icons.add_circle_outline, "Add Product", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage()))), 
                const SizedBox(width: 15), 
                _buildQuickAction(Icons.shopping_cart, "Go to Shopping", Colors.deepOrange, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen())))
              ]
            ),
            
            const SizedBox(height: 30),
            const Divider(height: 1, thickness: 1),
            const SizedBox(height: 20),

            // =====================================
            // NEW: Product Insights / Overview
            // =====================================
            const Text('Product Insights', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            // Filter Buttons (Tabs)
            Row(
              children:[
                _buildFilterChip('Low Stock', Icons.warning_amber_rounded, Colors.red),
                const SizedBox(width: 10),
                _buildFilterChip('Top Sales', Icons.trending_up, Colors.blue),
                const SizedBox(width: 10),
                _buildFilterChip('Newest', Icons.new_releases, Colors.green),
              ],
            ),
            const SizedBox(height: 15),

            // Product List based on filter
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('products').where('seller_id', isEqualTo: currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No products uploaded yet.')));

                var allProducts = snapshot.data!.docs;
                List<QueryDocumentSnapshot> displayList =[];

                // ফিল্টারিং লজিক (Local Sorting to avoid Firebase Index Error)
                if (_selectedFilter == 'Low Stock') {
                  displayList = allProducts.where((doc) {
                    int stock = int.tryParse((doc.data() as Map<String, dynamic>)['stock'].toString()) ?? 0;
                    return stock <= 5; // ৫ বা তার কম হলে লো-স্টক হিসেবে ধরবে
                  }).toList();
                } 
                else if (_selectedFilter == 'Top Sales') {
                  displayList = allProducts.toList();
                  displayList.sort((a, b) {
                    int salesA = (a.data() as Map<String, dynamic>)['sales_count'] ?? 0;
                    int salesB = (b.data() as Map<String, dynamic>)['sales_count'] ?? 0;
                    return salesB.compareTo(salesA); // Descending (High to Low)
                  });
                } 
                else if (_selectedFilter == 'Newest') {
                  displayList = allProducts.toList();
                  displayList.sort((a, b) {
                    Timestamp? tA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    Timestamp? tB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    if (tA == null || tB == null) return 0;
                    return tB.compareTo(tA); // Newest first
                  });
                }

                if (displayList.isEmpty) {
                  return Container(
                    width: double.infinity, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text(_selectedFilter == 'Low Stock' ? 'Great! All products have sufficient stock. 🎉' : 'No data available for this filter.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  );
                }

                // লিস্ট ভিউ
                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), // মেইন স্ক্রলবার কাজ করার জন্য
                  itemCount: displayList.length > 5 ? 5 : displayList.length, // সর্বোচ্চ ৫টি দেখাবে
                  itemBuilder: (context, index) {
                    var doc = displayList[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    String firstImage = data.containsKey('image_urls') && (data['image_urls'] as List).isNotEmpty ? data['image_urls'][0] : '';
                    int stock = int.tryParse(data['stock'].toString()) ?? 0;
                    int sales = data['sales_count'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        leading: Container(
                          width: 50, height: 50, 
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), 
                          child: firstImage.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)
                        ),
                        title: Text(data['product_name'] ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('৳${data['price']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children:[
                            if (_selectedFilter == 'Low Stock') ...[
                              const Text('Stock Left', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text('$stock', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                            ] else if (_selectedFilter == 'Top Sales') ...[
                              const Text('Total Sold', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text('$sales', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                            ] else ...[
                              const Text('Stock', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Text('$stock', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ]
                          ],
                        ),
                      ),
                    );
                  }
                );
              }
            ),
          ],
        ),
      ),
    );
  }

  // হেল্পার উইজেট: Filter Chips
  Widget _buildFilterChip(String label, IconData icon, Color color) {
    bool isSelected = _selectedFilter == label;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          border: Border.all(color: isSelected ? color : Colors.grey.shade300),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children:[
            Icon(icon, size: 14, color: isSelected ? Colors.white : color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
          ],
        ),
      ),
    );
  }

  // হেল্পার উইজেট: Stat Cards & Actions (আগেরগুলোই আছে)
  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {
    return Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)), child: Column(children:[Text(title, style: const TextStyle(fontSize: 14)), const SizedBox(height: 5), Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor))]))); 
  }
  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))), child: Column(children:[Icon(icon, color: color, size: 30), const SizedBox(height: 5), Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color))]))));
  }
}

// ==========================================
// সেলার প্রোডাক্ট ম্যানেজমেন্ট: (Edit, Disable & Delete)
// ==========================================
class ProductManagement extends StatelessWidget {
  const ProductManagement({super.key});
  
  @override 
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(backgroundColor: Colors.amber[200], elevation: 0, title: const Text('PRODUCT MANAGEMENT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: Column(
        children:[
          Padding(padding: const EdgeInsets.all(15.0), child: TextField(decoration: InputDecoration(hintText: 'Search for products...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none)))),
          
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('products')
                  .where('seller_id', isEqualTo: currentUser?.uid)
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('You have not uploaded any products yet.'));

                var docs = snapshot.data!.docs;
                docs.sort((a, b) {
                  var dataA = a.data() as Map<String, dynamic>;
                  var dataB = b.data() as Map<String, dynamic>;
                  Timestamp? tA = dataA['timestamp'] as Timestamp?;
                  Timestamp? tB = dataB['timestamp'] as Timestamp?;
                  if (tA == null || tB == null) return 0;
                  return tB.compareTo(tA);
                });

                return ListView.builder(
                  itemCount: docs.length, 
                  padding: const EdgeInsets.symmetric(horizontal: 15), 
                  itemBuilder: (context, index) {
                    var doc = docs[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    String firstImage = data.containsKey('image_urls') && (data['image_urls'] as List).isNotEmpty ? data['image_urls'][0] : '';
                    String status = data['status'] ?? 'pending';
                    
                    // প্রোডাক্ট একটিভ আছে কি না (Hide/Unhide)
                    bool isActive = data.containsKey('is_active') ? data['is_active'] : true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children:[
                            Container(
                              width: 70, height: 70, 
                              decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), 
                              child: firstImage.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children:[
                                  Text(data['product_name'] ?? 'Product Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis), 
                                  const SizedBox(height: 5),
                                  Text('Price: ৳${data['price']} | Stock: ${data['stock']}'),
                                  const SizedBox(height: 5),
                                  Row(
                                    children:[
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: status == 'approved' ? Colors.green.shade50 : (status == 'rejected' ? Colors.red.shade50 : Colors.orange.shade50), borderRadius: BorderRadius.circular(5)),
                                        child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange))),
                                      ),
                                      const SizedBox(width: 10),
                                      if (!isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5)),
                                          child: const Text('HIDDEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                                        ),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            
                            // থ্রি-ডট মেনু (Edit, Hide, Delete)
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => EditProductPage(productId: doc.id, productData: data)));
                                } else if (value == 'toggle_visibility') {
                                  doc.reference.update({'is_active': !isActive});
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isActive ? 'Product hidden from shop!' : 'Product is now visible!')));
                                } else if (value == 'delete') {
                                  doc.reference.delete();
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Deleted!')));
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(value: 'edit', child: Row(children:[Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 10), Text('Edit Product')])),
                                PopupMenuItem(value: 'toggle_visibility', child: Row(children:[Icon(isActive ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20), SizedBox(width: 10), Text(isActive ? 'Hide Product' : 'Show Product')])),
                                const PopupMenuItem(value: 'delete', child: Row(children:[Icon(Icons.delete, color: Colors.red, size: 20), SizedBox(width: 10), Text('Delete')])),
                              ],
                            )
                          ],
                        ),
                      )
                    );
                  }
                );
              }
            )
          ),
        ]
      ),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: Colors.blue, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage())), label: const Text('Add New Product'), icon: const Icon(Icons.add)),
    );
  }
}

// ==========================================
// নতুন পেজ: Edit Product Page (Full Features & Smart Approval)
// ==========================================
class EditProductPage extends StatefulWidget {
  final String productId;
  final Map<String, dynamic> productData;

  const EditProductPage({super.key, required this.productId, required this.productData});

  @override
  State<EditProductPage> createState() => _EditProductPageState();
}

class _EditProductPageState extends State<EditProductPage> {
  late TextEditingController nameController;
  late TextEditingController priceController;
  late TextEditingController originalPriceController;
  late TextEditingController stockController;
  late TextEditingController descController;
  late TextEditingController unitController;
  
  String? selectedCategory;
  List<dynamic> existingImageUrls =[];
  List<Map<String, dynamic>> variantMatrix =[];
  
  // ম্যাজিক বাটন: এটি অন থাকলে শুধু স্টক এডিট করা যাবে এবং এপ্রুভাল লাগবে না
  bool isStockUpdateOnly = false; 

  @override
  void initState() {
    super.initState();
    var data = widget.productData;
    
    nameController = TextEditingController(text: data['product_name'] ?? '');
    priceController = TextEditingController(text: data['price'].toString());
    originalPriceController = TextEditingController(text: data['original_price']?.toString() ?? '');
    stockController = TextEditingController(text: data['stock'].toString());
    descController = TextEditingController(text: data['description'] ?? '');
    unitController = TextEditingController(text: data['variant_unit'] ?? 'Unit');
    selectedCategory = data['category'];
    
    if (data['image_urls'] != null) {
      existingImageUrls = List<dynamic>.from(data['image_urls']);
    }
    
    if (data['variants'] != null) {
      // ডাটাবেস থেকে সেভ করা ম্যাট্রিক্স লোড করা হচ্ছে
      variantMatrix = List<Map<String, dynamic>>.from(data['variants'].map((x) => Map<String, dynamic>.from(x)));
    }
  }

  void _calculateTotalStock() {
    int total = 0;
    for (var item in variantMatrix) {
      total += (item['stock'] ?? 0) as int;
    }
    setState(() {
      stockController.text = total.toString();
    });
  }

  void _updateProduct() async {
    if (nameController.text.isEmpty || priceController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and Price are required!')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      Map<String, dynamic> updateData = {};

      if (isStockUpdateOnly) {
        // যদি শুধু স্টক আপডেট করে (No approval needed)
        updateData = {
          'stock': stockController.text.trim(),
          'variants': variantMatrix,
          'updated_at': FieldValue.serverTimestamp(),
        };
      } else {
        // যদি অন্য কিছু আপডেট করে (Requires Admin Approval)
        updateData = {
          'product_name': nameController.text.trim(),
          'price': priceController.text.trim(),
          'original_price': originalPriceController.text.trim(),
          'stock': stockController.text.trim(),
          'description': descController.text.trim(),
          'category': selectedCategory,
          'variant_unit': unitController.text.trim(),
          'variants': variantMatrix,
          'status': 'pending', // স্ট্যাটাস পেন্ডিং হয়ে যাবে
          'updated_at': FieldValue.serverTimestamp(),
        };
      }

      await FirebaseFirestore.instance.collection('products').doc(widget.productId).update(updateData);

      // যদি পেন্ডিং হয়, তবে অ্যাডমিনকে নোটিফিকেশন পাঠাবে
      if (!isStockUpdateOnly) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'Product Edited & Pending 📦',
          'message': 'A seller updated "${nameController.text.trim()}". Please review.',
          'target_role': 'admin',
          'sent_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      Navigator.pop(context); // Close loading
      Navigator.pop(context); // Go back
      
      if (isStockUpdateOnly) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock updated instantly! ⚡', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product updated! Waiting for admin approval. ⏳')));
      }
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Edit Product'), backgroundColor: Colors.amber[400], foregroundColor: Colors.black),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            // স্মার্ট স্টক আপডেট টগল
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(color: isStockUpdateOnly ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: isStockUpdateOnly ? Colors.green : Colors.red.shade200)),
              child: SwitchListTile(
                title: Text('Stock Update Only (Instant Live)', style: TextStyle(fontWeight: FontWeight.bold, color: isStockUpdateOnly ? Colors.green : Colors.red)),
                subtitle: Text(isStockUpdateOnly ? 'Your product will remain live. You can only edit stock quantities.' : 'If you edit names, prices, or descriptions, the product will be PENDING for admin approval.', style: const TextStyle(fontSize: 11)),
                value: isStockUpdateOnly,
                activeColor: Colors.green,
                onChanged: (val) => setState(() => isStockUpdateOnly = val),
              ),
            ),
            const SizedBox(height: 25),
            
            // ছবি দেখানো (এডিট মোডে আপাতত শুধু দেখানো হচ্ছে)
            const Text('Product Images', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SizedBox(
              height: 70,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: existingImageUrls.length,
                itemBuilder: (context, index) {
                  return Container(
                    width: 70, margin: const EdgeInsets.only(right: 10),
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300), image: DecorationImage(image: NetworkImage(existingImageUrls[index]), fit: BoxFit.cover)),
                  );
                }
              ),
            ),
            const SizedBox(height: 20),

            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
              value: selectedCategory,
              items:['Fashion', 'Electronics', 'Mobiles', 'Home Decor', 'Beauty', 'Watches', 'Baby & Toys', 'Groceries', 'Automotive', 'Women\'s Bags', 'Men\'s Wallets', 'Muslim Fashion', 'Games & Hobbies', 'Computers', 'Sports & Outdoor', 'Men Shoes', 'Cameras', 'Travel & Luggage'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
              onChanged: isStockUpdateOnly ? null : (val) => setState(() => selectedCategory = val),
            ),
            const SizedBox(height: 15),

            TextField(
              controller: nameController, 
              enabled: !isStockUpdateOnly, // অন থাকলে এডিট করা যাবে না
              decoration: InputDecoration(labelText: 'Product Name', filled: isStockUpdateOnly, fillColor: Colors.grey.shade100, border: const OutlineInputBorder())
            ),
            const SizedBox(height: 15),
            
            Row(
              children:[
                Expanded(child: TextField(controller: priceController, enabled: !isStockUpdateOnly, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Base Price (৳)', filled: isStockUpdateOnly, fillColor: Colors.grey.shade100, border: const OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: originalPriceController, enabled: !isStockUpdateOnly, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Original Price (৳)', filled: isStockUpdateOnly, fillColor: Colors.grey.shade100, border: const OutlineInputBorder()))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: stockController, readOnly: true, decoration: InputDecoration(labelText: 'Total Stock', filled: true, fillColor: Colors.amber.shade50, border: const OutlineInputBorder()))),
              ],
            ),
            const SizedBox(height: 20),
            
            // ভেরিয়েন্ট এডিটর
            const Text('Edit Variants & Stock', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10)),
              child: ListView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                itemCount: variantMatrix.length,
                itemBuilder: (context, index) {
                  var item = variantMatrix[index];
                  bool isFirst = index == 0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children:[
                        Expanded(flex: 2, child: Text('${item['color']} - ${item['size']} ${unitController.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                        const SizedBox(width: 5),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: item['stock'].toString(),
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Stock', isDense: true, border: OutlineInputBorder()),
                            onChanged: (val) {
                              variantMatrix[index]['stock'] = int.tryParse(val) ?? 0;
                              _calculateTotalStock();
                            },
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          flex: 1,
                          child: TextFormField(
                            initialValue: item['price'].toString(),
                            keyboardType: TextInputType.number,
                            enabled: !isStockUpdateOnly && !isFirst, // স্টক মোডে এবং প্রথমটাতে দাম বদলানো যাবে না
                            decoration: InputDecoration(labelText: '+ Price', isDense: true, filled: isStockUpdateOnly || isFirst, border: const OutlineInputBorder()),
                            onChanged: (val) => variantMatrix[index]['price'] = int.tryParse(val) ?? 0,
                          ),
                        ),
                      ],
                    ),
                  );
                }
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: descController, 
              enabled: !isStockUpdateOnly,
              maxLines: 4, 
              decoration: InputDecoration(labelText: 'Description', filled: isStockUpdateOnly, fillColor: Colors.grey.shade100, border: const OutlineInputBorder())
            ),
            const SizedBox(height: 40),
            
            SizedBox(
              width: double.infinity, height: 50,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: isStockUpdateOnly ? Colors.green : Colors.blue),
                onPressed: _updateProduct, 
                icon: Icon(isStockUpdateOnly ? Icons.flash_on : Icons.send, color: Colors.white),
                label: Text(isStockUpdateOnly ? 'INSTANT UPDATE STOCK' : 'UPDATE & REQUEST APPROVAL', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
              ),
            )
          ],
        ),
      ),
    );
  }
}

// ==========================================
// সেলার অর্ডার ম্যানেজমেন্ট (Smart Fulfillment Logic Fixed)
// ==========================================
class SellerOrderManagement extends StatelessWidget {
  const SellerOrderManagement({super.key});

  Future<void> _sendCustomerNotification(String userId, String orderId, String statusMsg) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'target_user_id': userId,
      'title': 'Order Update 📦',
      'message': 'Your order #${orderId.substring(0, 8).toUpperCase()} is $statusMsg.',
      'sent_at': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.amber[200], 
          title: const Text('ORDER MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), 
          bottom: const TabBar(
            isScrollable: false, // [FIXED] স্ক্রল অফ করা হয়েছে
            labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs:[Tab(text: 'Pending'), Tab(text: 'To Pack'), Tab(text: 'Shipped'), Tab(text: 'Done')]
          )
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('You have no orders yet.'));

            // লোকাল সর্টিং
            var allDocs = snapshot.data!.docs.toList();
            allDocs.sort((a, b) {
              var tA = (a.data() as Map<String, dynamic>)['order_date'];
              var tB = (b.data() as Map<String, dynamic>)['order_date'];
              if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
              return 0;
            });

            var sellerOrders = allDocs.where((doc) {
              var data = doc.data() as Map<String, dynamic>;
              List<dynamic> items = data['items'] ??[];
              return items.any((item) => item['seller_id'] == currentUser?.uid);
            }).toList();

            if (sellerOrders.isEmpty) return const Center(child: Text('You have no orders yet.', style: TextStyle(color: Colors.grey)));

            var pendingOrders = sellerOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList();
            var processingOrders = sellerOrders.where((doc) => ['Processing', 'Ready to Ship'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
            var shippedOrders = sellerOrders.where((doc) =>['Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
            var completedOrders = sellerOrders.where((doc) => ['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

            return TabBarView(
              children:[
                _buildOrderList(context, pendingOrders, currentUser!.uid),
                _buildOrderList(context, processingOrders, currentUser.uid),
                _buildOrderList(context, shippedOrders, currentUser.uid),
                _buildOrderList(context, completedOrders, currentUser.uid),
              ],
            );
          }
        ),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<QueryDocumentSnapshot> orders, String sellerId) {
    if (orders.isEmpty) return const Center(child: Text('No orders in this section.', style: TextStyle(color: Colors.grey)));

    return ListView.builder(
      padding: const EdgeInsets.all(15), 
      itemCount: orders.length, 
      itemBuilder: (context, index) {
        var doc = orders[index];
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        
        List<dynamic> allItems = data['items'] ??[];
        List<dynamic> myItems = allItems.where((i) => i['seller_id'] == sellerId).toList();
        
        double myTotalValue = 0;
        String itemNames = '';
        for (var item in myItems) {
          myTotalValue += (double.tryParse(item['price'].toString()) ?? 0) * (int.tryParse(item['quantity'].toString()) ?? 1);
          itemNames += '${item['quantity']}x ${item['product_name']}\n';
        }

        String status = data['status'] ?? 'Pending';
        String customerId = data['user_id'] ?? '';
        
        Color statusColor = Colors.orange;
        if (['Processing', 'Ready to Ship'].contains(status)) statusColor = Colors.blue;
        else if (['Dispatched', 'In-Transit'].contains(status)) statusColor = Colors.purple;
        else if (status == 'Delivered') statusColor = Colors.green;
        else if (['Delivery Failed', 'Cancelled'].contains(status)) statusColor = Colors.red;

        return Container(
          margin: const EdgeInsets.only(bottom: 15), 
          padding: const EdgeInsets.all(15), 
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children:[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children:[
                  Text('Order ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)), 
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)))
                ]
              ), 
              const SizedBox(height: 5),
              Text('Customer: ${data['shipping_name'] ?? 'Unknown'}', style: const TextStyle(color: Colors.grey, fontSize: 13)), 
              const Divider(height: 20), 
              
              Text(itemNames.trim(), style: const TextStyle(fontSize: 13, color: Colors.black87), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children:[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      const Text('Your Earnings', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('৳${myTotalValue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                    ],
                  ), 
                  _buildSellerActionButton(context, doc.id, customerId, status)
                ]
              ),

              const SizedBox(height: 15),
              _buildTrackingTimeline(status),
            ]
          )
        );
      }
    );
  }

  //[FIXED] সেলারের নতুন লজিক
  Widget _buildSellerActionButton(BuildContext context, String orderId, String customerId, String status) {
    if (status == 'Pending') {
      // পেন্ডিং অবস্থায় সেলার কিছুই করতে পারবে না, অ্যাডমিনের এপ্রুভালের জন্য অপেক্ষা করবে
      return const Text('Awaiting Admin', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12));
    } 
    else if (status == 'Processing') {
      // অ্যাডমিন কনফার্ম করলে সেলার প্যাক করে রেডি করবে
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
        onPressed: () async {
          await FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Ready to Ship', 'ready_to_ship_at': FieldValue.serverTimestamp()});
          
          // কাস্টমারকে নোটিফিকেশন
          await _sendCustomerNotification(customerId, orderId, 'packed and waiting for rider pickup');
          
          // অ্যাডমিনকে নোটিফিকেশন
          await FirebaseFirestore.instance.collection('notifications').add({
            'title': 'Order Ready to Ship 🚚',
            'message': 'সেলার অর্ডার #${orderId.substring(0, 8).toUpperCase()} প্যাক করেছেন। দয়া করে রাইডার অ্যাসাইন করুন।',
            'target_role': 'admin',
            'sent_at': FieldValue.serverTimestamp(),
          });

        }, 
        icon: const Icon(Icons.check_circle, color: Colors.white, size: 16), label: const Text('Pack Order', style: TextStyle(color: Colors.white))
      );
    }
    else if (status == 'Ready to Ship') return const Text('Waiting for Rider', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 12));
    else if (status == 'Dispatched' || status == 'In-Transit') return const Text('Handed Over 🚚', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold));
    else if (status == 'Delivered') return const Text('Payment Done ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold));
    else if (status == 'Delivery Failed') return const Text('Failed / Returned ❌', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold));
    return const SizedBox();
  }

  Widget _buildTrackingTimeline(String currentStatus) {
    int step = 0;
    if (currentStatus == 'Pending') step = 0;
    else if (currentStatus == 'Processing') step = 1;
    else if (currentStatus == 'Ready to Ship') step = 2;
    else if (currentStatus == 'Dispatched' || currentStatus == 'In-Transit') step = 3;
    else if (currentStatus == 'Delivered' || currentStatus == 'Delivery Failed') step = 4;

    return Row(
      children:[
        _buildTimelineStep('Pack', step >= 1, isFirst: true),
        _buildTimelineLine(step >= 2),
        _buildTimelineStep('RTS', step >= 2),
        _buildTimelineLine(step >= 3),
        _buildTimelineStep('Shipped', step >= 3),
        _buildTimelineLine(step >= 4),
        _buildTimelineStep('Done', step >= 4, isLast: true),
      ],
    );
  }

  Widget _buildTimelineStep(String label, bool isCompleted, {bool isFirst = false, bool isLast = false}) {
    return Column(
      children:[
        Container(width: 20, height: 20, decoration: BoxDecoration(color: isCompleted ? Colors.teal : Colors.grey.shade300, shape: BoxShape.circle), child: isCompleted ? const Icon(Icons.check, size: 12, color: Colors.white) : null),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 9, color: isCompleted ? Colors.teal : Colors.grey, fontWeight: FontWeight.bold))
      ],
    );
  }

  Widget _buildTimelineLine(bool isCompleted) {
    return Expanded(child: Container(margin: const EdgeInsets.only(bottom: 15), height: 3, color: isCompleted ? Colors.teal : Colors.grey.shade200));
  }
}

// ==========================================
// সেলার পেমেন্ট ও রিপোর্টস (Real-time Earnings & Withdrawal)
// ==========================================
class PaymentsReports extends StatefulWidget {
  const PaymentsReports({super.key});

  @override
  State<PaymentsReports> createState() => _PaymentsReportsState();
}

class _PaymentsReportsState extends State<PaymentsReports> {
  double platformCommissionRate = 0.10; // ডিফল্ট ১০% কমিশন

  @override
  void initState() {
    super.initState();
    _fetchCommissionRate();
  }

  // অ্যাডমিন প্যানেল থেকে সেট করা রিয়েল কমিশন রেট আনা
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

  // টাকা তোলার রিকোয়েস্ট পাঠানোর পপ-আপ
  void _requestWithdrawal(double availableBalance) {
    if (availableBalance <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('পর্যাপ্ত ব্যালেন্স নেই!')));
      return;
    }

    TextEditingController amountCtrl = TextEditingController(text: availableBalance.toStringAsFixed(0));
    String selectedMethod = 'bKash';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Withdraw Funds'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text('Available: ৳${availableBalance.toStringAsFixed(0)}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                TextField(
                  controller: amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount to withdraw (৳)', border: OutlineInputBorder(), isDense: true),
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedMethod,
                  decoration: const InputDecoration(labelText: 'Transfer to', border: OutlineInputBorder(), isDense: true),
                  items: ['bKash', 'Nagad', 'Bank Account'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                  onChanged: (val) => setDialogState(() => selectedMethod = val!),
                )
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Withdrawal request of ৳${amountCtrl.text} via $selectedMethod sent to Admin!')));
                },
                child: const Text('Confirm', style: TextStyle(color: Colors.white)),
              )
            ],
          );
        }
      )
    );
  }

  // ====================================================
  // [NEW]: পিডিএফ রিপোর্ট তৈরি ও ডাউনলোড করার ফাংশন (যেটা মিসিং ছিল)
  // ====================================================
  Future<void> generateSellerMonthlyReportPDF(List<Map<String, dynamic>> history, double totalEarned) async {
    final pdf = pw.Document();
    
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children:[
              pw.Text('D Shop - Seller Statement', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold, color: PdfColors.deepOrange)),
              pw.SizedBox(height: 10),
              pw.Text('Generated on: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}'),
              pw.SizedBox(height: 30),
              
              pw.Text('Earnings Breakdown', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              
              pw.Table.fromTextArray(
                headers:['Date', 'Product Name', 'Status', 'Net Earning'],
                data: history.map((item) {
                  DateTime dt = (item['date'] as Timestamp).toDate();
                  return[
                    '${dt.day}/${dt.month}/${dt.year}',
                    item['product_name'],
                    item['status'],
                    'Tk ${item['earnings'].toStringAsFixed(0)}'
                  ];
                }).toList(),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
                cellAlignment: pw.Alignment.centerLeft,
              ),
              pw.SizedBox(height: 20),
              
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.end,
                children:[
                  pw.Text('Total Settled Earnings: Tk ${totalEarned.toStringAsFixed(0)}', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold))
                ]
              )
            ]
          );
        }
      )
    );

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save(), name: 'Seller_Statement.pdf');
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: Colors.amber[200], 
        title: const Text('PAYMENTS & REPORTS', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold))
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No sales data yet.'));

          double availableBalance = 0;
          double pendingBalance = 0;
          List<Map<String, dynamic>> earningHistory =[];

          // সেলারের আর্নিং হিসাব করা
          for (var doc in snapshot.data!.docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            List<dynamic> items = data['items'] ??[];
            String status = data['status'] ?? 'Pending';

            for (var item in items) {
              if (item['seller_id'] == currentUser?.uid) {
                double price = double.tryParse(item['price'].toString()) ?? 0;
                int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                
                // সেলারের নিট লাভ (অ্যাডমিন কমিশন বাদে)
                double netEarnings = (price * qty) * (1 - platformCommissionRate);

                if (status == 'Delivered') {
                  availableBalance += netEarnings;
                  earningHistory.add({
                    'product_name': item['product_name'],
                    'earnings': netEarnings,
                    'date': data['order_date'] ?? FieldValue.serverTimestamp(),
                    'status': 'Completed'
                  });
                } 
                else if (status != 'Cancelled') {
                  pendingBalance += netEarnings;
                  earningHistory.add({
                    'product_name': item['product_name'],
                    'earnings': netEarnings,
                    'date': data['order_date'] ?? FieldValue.serverTimestamp(),
                    'status': 'Pending'
                  });
                }
              }
            }
          }

          // লেটেস্ট হিস্ট্রি আগে দেখানোর জন্য সর্ট করা
          earningHistory.sort((a, b) {
            Timestamp? tA = a['date'] as Timestamp?;
            Timestamp? tB = b['date'] as Timestamp?;
            if (tA == null || tB == null) return 0;
            return tB.compareTo(tA);
          });

          return SingleChildScrollView(
            padding: const EdgeInsets.all(15), 
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                // =====================================
                // Balance Cards
                // =====================================
                Row(
                  children:[
                    _buildBalanceCard("Available Balance", "৳${availableBalance.toStringAsFixed(0)}", Colors.teal), 
                    const SizedBox(width: 15), 
                    _buildBalanceCard("Pending Payout", "৳${pendingBalance.toStringAsFixed(0)}", Colors.orange)
                  ]
                ), 
                const SizedBox(height: 15),

                // উইথড্র বাটন
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    onPressed: () => _requestWithdrawal(availableBalance), 
                    icon: const Icon(Icons.account_balance_wallet, color: Colors.white), 
                    label: const Text('WITHDRAW FUNDS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                  ),
                ),
                const SizedBox(height: 15), 
                
                // =====================================
                // Payment Methods
                // =====================================
                const Text('Payment Methods', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                const SizedBox(height: 10), 
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children:[
                      ListTile(leading: const Icon(Icons.account_balance, color: Colors.blue), title: const Text('Link a Bank Account'), trailing: const Icon(Icons.arrow_forward_ios, size: 15), onTap: (){}), 
                      const Divider(height: 1),
                      ListTile(leading: const Icon(Icons.account_balance_wallet, color: Colors.pink), title: const Text('Add bKash Number'), subtitle: const Text('017XXXXXXXX', style: TextStyle(color: Colors.grey)), trailing: const Icon(Icons.edit, size: 15, color: Colors.teal), onTap: (){}), 
                    ],
                  ),
                ),
                const SizedBox(height: 25), 

                // --- পিডিএফ ডাউনলোড বাটন ---
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.teal),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      // পিডিএফ ফাংশন কল
                      generateSellerMonthlyReportPDF(earningHistory, availableBalance);
                    },
                    icon: const Icon(Icons.picture_as_pdf, color: Colors.teal),
                    label: const Text(
                      'DOWNLOAD MONTHLY STATEMENT',
                      style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // =====================================
                // Earning History (Sales Report)
                // =====================================
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    const Text('Recent Earnings', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${(platformCommissionRate * 100).toStringAsFixed(0)}% Platform Fee Deducted', 
                      style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
                  ],
                ),
                const SizedBox(height: 10),

                if (earningHistory.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No earning history yet.', style: TextStyle(color: Colors.grey))))
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: earningHistory.length,
                    itemBuilder: (context, index) {
                      var item = earningHistory[index];
                      bool isCompleted = item['status'] == 'Completed';

                      String dateStr = 'Recently';
                      if (item['date'] is Timestamp) {
                        DateTime dt = (item['date'] as Timestamp).toDate();
                        dateStr = '${dt.day}/${dt.month}/${dt.year}';
                      }

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCompleted ? Colors.green.shade50 : Colors.orange.shade50,
                            child: Icon(isCompleted ? Icons.done_all : Icons.hourglass_empty, color: isCompleted ? Colors.green : Colors.orange, size: 20),
                          ),
                          title: Text(item['product_name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children:[
                              Text('+ ৳${item['earnings'].toStringAsFixed(0)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isCompleted ? Colors.teal : Colors.grey)),
                              Text(item['status'], style: TextStyle(fontSize: 10, color: isCompleted ? Colors.green : Colors.orange)),
                            ],
                          ),
                        ),
                      );
                    }
                  )
              ]
            ),
          );
        }
      ),
    );
  }

  // ব্যালেন্স কার্ডের হেল্পার উইজেট
  Widget _buildBalanceCard(String title, String amount, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(15), 
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.bold)), 
            const SizedBox(height: 5),
            Text(amount, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color))
          ]
        )
      )
    ); 
  }
}

// ==========================================
// সেলার প্রোফাইল (Profile Picture Upload, Shop Settings & Payment Info)
// ==========================================
class SellerProfile extends StatefulWidget {
  const SellerProfile({super.key});

  @override
  State<SellerProfile> createState() => _SellerProfileState();
}

class _SellerProfileState extends State<SellerProfile> {
  final ImagePicker _picker = ImagePicker();

  Future<void> _uploadSellerProfilePicture() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 70, maxWidth: 1080);
    if (image == null || currentUser == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      String fileName = 'seller_profile_${currentUser.uid}_${DateTime.now().millisecondsSinceEpoch}';
      Reference ref = FirebaseStorage.instance.ref().child('profile_pictures').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();
      
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'profile_image_url': downloadUrl});

      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('profile_image', downloadUrl);

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দোকানের লোগো সফলভাবে আপডেট হয়েছে! 🎉')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override 
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(backgroundColor: Colors.orange[100], elevation: 0),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var data = snapshot.data!.data() as Map<String, dynamic>;
          String shopName = data.containsKey('shop_name') && data['shop_name'].toString().isNotEmpty ? data['shop_name'] : data['name'] ?? 'Seller Profile';
          String profileImg = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';

          return Column(
            children:[
              Container(
                width: double.infinity, padding: const EdgeInsets.all(20), 
                decoration: BoxDecoration(color: Colors.orange[100], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))), 
                child: Column(
                  children:[
                    Stack(
                      alignment: Alignment.bottomRight,
                      children:[
                        CircleAvatar(
                          radius: 50, backgroundColor: Colors.white, 
                          backgroundImage: profileImg.isNotEmpty ? NetworkImage(profileImg) : null,
                          child: profileImg.isEmpty ? const Icon(Icons.store, size: 50, color: Colors.orange) : null
                        ),
                        InkWell(
                          onTap: _uploadSellerProfilePicture,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(color: Colors.deepOrange, shape: BoxShape.circle, boxShadow:[BoxShadow(color: Colors.black26, blurRadius: 3)]),
                            child: const Icon(Icons.camera_alt, color: Colors.white, size: 18)
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10), 
                    Text(data['name'] ?? 'User Name', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), 
                    Text(shopName, style: TextStyle(color: Colors.grey.shade700)), 
                  ]
                )
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20), 
                  children:[
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      tileColor: Colors.white,
                      leading: const Icon(Icons.visibility, color: Colors.teal), 
                      title: const Text('View My Public Shop', style: TextStyle(fontWeight: FontWeight.bold)), 
                      trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                      onTap: () {
                        if (currentUser != null) {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => ShopPage(sellerId: currentUser.uid)));
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    ListTile(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      tileColor: Colors.white,
                      leading: const Icon(Icons.shopping_bag, color: Colors.deepOrange), 
                      title: const Text('Switch to Customer Mode', style: TextStyle(fontWeight: FontWeight.bold)), 
                      subtitle: const Text('দোকান থেকে বের হয়ে কেনাকাটা করুন', style: TextStyle(fontSize: 10)),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 15),
                      onTap: () {
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
                      },
                    ),
                    const SizedBox(height: 25),
                    
                    // ==========================================
                    // ক্লিকেবল Shop Settings & Payment Info
                    // ==========================================
                    _buildProfileItem(Icons.settings, "Shop Settings", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SellerShopSettingsPage()));
                    }), 
                    _buildProfileItem(Icons.account_balance, "Bank / Payment Info", () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => const SellerPaymentInfoPage()));
                    }), 
                    
                    const SizedBox(height: 30), 
                    
                    TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      onPressed: () async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await FirebaseAuth.instance.signOut(); 
                        if(context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
                      }, 
                      label: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18))
                    )
                  ]
                )
              ),
            ]
          );
        }
      ),
    );
  }
  Widget _buildProfileItem(IconData icon, String title, VoidCallback onTap) {
    return Card(
      elevation: 0, color: Colors.white, margin: const EdgeInsets.only(bottom: 5),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey.shade700), 
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), 
        trailing: const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey),
        onTap: onTap,
      ),
    );
  }
}

// ==========================================
// নতুন পেজ ১: Seller Shop Settings (দোকানের ঠিকানা ও কন্টাক্ট)
// ==========================================
class SellerShopSettingsPage extends StatefulWidget {
  const SellerShopSettingsPage({super.key});

  @override
  State<SellerShopSettingsPage> createState() => _SellerShopSettingsPageState();
}

class _SellerShopSettingsPageState extends State<SellerShopSettingsPage> {
  final TextEditingController shopNameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController addressCtrl = TextEditingController();
  final TextEditingController descCtrl = TextEditingController();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShopData();
  }

  Future<void> _loadShopData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        shopNameCtrl.text = data['shop_name'] ?? data['name'] ?? '';
        phoneCtrl.text = data['phone'] ?? '';
        addressCtrl.text = data['shop_address'] ?? ''; // পিক আপ এড্রেস
        descCtrl.text = data['shop_description'] ?? '';
      }
    }
    setState(() => isLoading = false);
  }

  Future<void> _saveShopData() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    setState(() => isLoading = true);
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'shop_name': shopNameCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'shop_address': addressCtrl.text.trim(),
        'shop_description': descCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Shop details saved successfully! ✅')));
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
      appBar: AppBar(title: const Text('Shop Settings'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Basic Shop Info', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 5),
                const Text('রাইডার পার্সেল পিক করার জন্য এই ঠিকানায় যোগাযোগ করবে।', style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 25),
                
                TextField(controller: shopNameCtrl, decoration: const InputDecoration(labelText: 'Shop Name', prefixIcon: Icon(Icons.store), border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Contact Phone Number', prefixIcon: Icon(Icons.phone), border: OutlineInputBorder())),
                const SizedBox(height: 15),
                TextField(controller: addressCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Pick-up Address (Details)', prefixIcon: Icon(Icons.location_on), border: OutlineInputBorder(), hintText: 'House/Shop No, Street, Area, City')),
                const SizedBox(height: 15),
                TextField(controller: descCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Shop Description (Optional)', prefixIcon: Icon(Icons.description), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: _saveShopData, 
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('SAVE SETTINGS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                  )
                )
              ],
            ),
          )
    );
  }
}

// ==========================================
// নতুন পেজ ২: Seller Payment Info (বিকাশ/ব্যাংক ডিটেইলস)
// ==========================================
class SellerPaymentInfoPage extends StatefulWidget {
  const SellerPaymentInfoPage({super.key});

  @override
  State<SellerPaymentInfoPage> createState() => _SellerPaymentInfoPageState();
}

class _SellerPaymentInfoPageState extends State<SellerPaymentInfoPage> {
  final TextEditingController bkashCtrl = TextEditingController();
  final TextEditingController nagadCtrl = TextEditingController();
  final TextEditingController accNameCtrl = TextEditingController();
  final TextEditingController accNoCtrl = TextEditingController();
  final TextEditingController bankNameCtrl = TextEditingController();
  final TextEditingController branchCtrl = TextEditingController();
  
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
        bkashCtrl.text = data['bkash_number'] ?? '';
        nagadCtrl.text = data['nagad_number'] ?? '';
        accNameCtrl.text = data['bank_account_name'] ?? '';
        accNoCtrl.text = data['bank_account_no'] ?? '';
        bankNameCtrl.text = data['bank_name'] ?? '';
        branchCtrl.text = data['bank_branch'] ?? '';
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
        'bkash_number': bkashCtrl.text.trim(),
        'nagad_number': nagadCtrl.text.trim(),
        'bank_account_name': accNameCtrl.text.trim(),
        'bank_account_no': accNoCtrl.text.trim(),
        'bank_name': bankNameCtrl.text.trim(),
        'bank_branch': branchCtrl.text.trim(),
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
      appBar: AppBar(title: const Text('Bank / Payment Info'), backgroundColor: Colors.pink, foregroundColor: Colors.white),
      body: isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Mobile Banking (MFS)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.pink)),
                const SizedBox(height: 10),
                TextField(controller: bkashCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'bKash Number (Personal/Agent)', prefixIcon: Icon(Icons.phone_android, color: Colors.pink), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: nagadCtrl, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'Nagad Number', prefixIcon: Icon(Icons.phone_android, color: Colors.orange), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                const Text('Bank Account Details', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blue)),
                const SizedBox(height: 10),
                TextField(controller: bankNameCtrl, decoration: const InputDecoration(labelText: 'Bank Name (e.g. DBBL, Islami Bank)', prefixIcon: Icon(Icons.account_balance, color: Colors.blue), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: accNameCtrl, decoration: const InputDecoration(labelText: 'Account Holder Name', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: accNoCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Account Number', prefixIcon: Icon(Icons.numbers), border: OutlineInputBorder())),
                const SizedBox(height: 10),
                TextField(controller: branchCtrl, decoration: const InputDecoration(labelText: 'Branch Name', prefixIcon: Icon(Icons.business), border: OutlineInputBorder())),
                
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    onPressed: _savePaymentData, 
                    icon: const Icon(Icons.save, color: Colors.white),
                    label: const Text('SAVE PAYMENT INFO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                  )
                )
              ],
            ),
          )
    );
  }
}

// ==========================================
// সেলার Add Product পেজ (Pro Matrix Variant System)
// ==========================================
class AddProductPage extends StatefulWidget { const AddProductPage({super.key}); @override State<AddProductPage> createState() => _AddProductPageState(); }
class _AddProductPageState extends State<AddProductPage> {
  final nameController = TextEditingController(); 
  final priceController = TextEditingController(); 
  final originalPriceController = TextEditingController(); 
  final stockController = TextEditingController(); 
  final descController = TextEditingController(); 
  final tagInput = TextEditingController(); 
  
  String? selectedCategory; 
  List<XFile> selectedImages =[]; 
  String? selectedFileName; 
  List<String> searchTags =[]; 
  final ImagePicker _picker = ImagePicker();

  // =====================================
  // Daraz/Shopee Style Matrix Variables
  // =====================================
  final unitController = TextEditingController(text: 'Watt'); 
  
  List<Map<String, dynamic>> selectedColors =[]; // কালার এবং তার ছবির ডাটা থাকবে
  List<String> selectedSizes =[]; // শুধু সাইজগুলোর নাম থাকবে
  List<Map<String, dynamic>> variantMatrix =[]; // সিস্টেম নিজে এই লিস্ট বানাবে

  final TextEditingController colorInputCtrl = TextEditingController();
  final TextEditingController sizeInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  // কালারের ছবি সিলেক্ট করার ফাংশন
  Future<void> _pickColorImage(int index) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      setState(() {
        selectedColors[index]['image'] = image;
      });
    }
  }

  // অটোমেটিক ম্যাট্রিক্স জেনারেট করার জাদুকরী ফাংশন
  void _generateVariantMatrix() {
    // আগের ডাটা যেন মুছে না যায়, তাই সেভ করে রাখা হচ্ছে
    Map<String, Map<String, dynamic>> existingData = {};
    for (var item in variantMatrix) {
      String key = '${item['color']}_${item['size']}';
      existingData[key] = item;
    }

    variantMatrix.clear();

    if (selectedColors.isEmpty && selectedSizes.isEmpty) {
      _calculateTotalStock();
      return;
    }

    List<Map<String, dynamic>> tempColors = selectedColors.isNotEmpty ? selectedColors :[{'name': 'Default', 'image': null}];
    List<String> tempSizes = selectedSizes.isNotEmpty ? selectedSizes :['Default'];

    // কালার ও সাইজের জোড়া মেলানো হচ্ছে (Cartesian Product)
    for (var c in tempColors) {
      for (var s in tempSizes) {
        String key = '${c['name']}_$s';
        variantMatrix.add({
          'color': c['name'],
          'size': s,
          'price': existingData[key]?['price'] ?? 0,
          'stock': existingData[key]?['stock'] ?? 0,
        });
      }
    }
    _calculateTotalStock();
  }

  void _calculateTotalStock() {
    int total = 0;
    for (var item in variantMatrix) {
      total += (item['stock'] ?? 0) as int;
    }
    setState(() {
      stockController.text = total.toString();
    });
  }

  Future<void> pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1080);
    if (images.isNotEmpty) setState(() => selectedImages.addAll(images));
  }

  void uploadProduct() async {
    if (nameController.text.isEmpty || priceController.text.isEmpty || selectedCategory == null) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Name, Price and Category!'))); 
      return; 
    }
    
    if (tagInput.text.trim().isNotEmpty) { 
      var tags = tagInput.text.split(','); 
      for (var t in tags) { if (t.trim().isNotEmpty) searchTags.add(t.trim()); } 
      tagInput.clear(); 
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      List<String> imageUrls =[];
      for (var image in selectedImages) {
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child('product_images').child(fileName);
        if (kIsWeb) { 
          Uint8List bytes = await image.readAsBytes(); 
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')); 
        } else { 
          await ref.putFile(File(image.path)); 
        }
        imageUrls.add(await ref.getDownloadURL());
      }

      List<String> finalTags = searchTags.map((e) => e.toLowerCase()).toList();
      finalTags.add(nameController.text.trim().toLowerCase());

      String generateSKU = 'DS-${DateTime.now().millisecondsSinceEpoch.toString().substring(9, 13)}${math.Random().nextInt(9)}';

      // --- নতুন: কালারের ছবি আপলোড করার লজিক ---
      Map<String, String> uploadedColorImages = {};
      for (var c in selectedColors) {
        if (c['image'] != null) {
          String cFileName = 'color_${DateTime.now().millisecondsSinceEpoch}_${c['name']}';
          Reference cRef = FirebaseStorage.instance.ref().child('product_images/colors').child(cFileName);
          if (kIsWeb) {
            Uint8List bytes = await (c['image'] as XFile).readAsBytes();
            await cRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
          } else {
            await cRef.putFile(File((c['image'] as XFile).path));
          }
          uploadedColorImages[c['name']] = await cRef.getDownloadURL();
        }
      }

      // ম্যাট্রিক্সে ছবির লিংক যুক্ত করে দেওয়া
      List<Map<String, dynamic>> finalMatrixToSave =[];
      for (var v in variantMatrix) {
        Map<String, dynamic> vCopy = Map.from(v);
        if (uploadedColorImages.containsKey(vCopy['color'])) {
          vCopy['color_image_url'] = uploadedColorImages[vCopy['color']];
        }
        finalMatrixToSave.add(vCopy);
      }
      // ------------------------------------------

      await FirebaseFirestore.instance.collection('products').add({
        'product_name': nameController.text.trim(), 
        'price': priceController.text.trim(), 
        'original_price': originalPriceController.text.trim(), 
        'stock': stockController.text.trim(),
        'category': selectedCategory, 
        'description': descController.text.trim(),
        'search_tags': finalTags, 
        'image_urls': imageUrls, 
        'seller_id': FirebaseAuth.instance.currentUser?.uid, 
        'timestamp': FieldValue.serverTimestamp(), 
        'status': 'pending',
        'sku': generateSKU,
        'variant_unit': unitController.text.trim(), 
        'variants': finalMatrixToSave, // আপডেটেড ম্যাট্রিক্স সেভ হলো
      });

      // --- অ্যাডমিনকে নোটিফিকেশন পাঠানোর লজিক ---
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'New Product Pending 📦',
        'message': 'A seller has uploaded "${nameController.text.trim()}". Please review and approve.',
        'target_role': 'admin', // এটি শুধু অ্যাডমিনদের জন্য
        'sent_at': FieldValue.serverTimestamp(),
      });
      // -----------------------------------------

      if (!mounted) return;
      Navigator.pop(context); 
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Uploaded Successfully! 🎉')));
    } catch (e) { 
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); 
    }
  }

  // =====================================
  // Daraz/Shopee Style Variant Matrix Builder
  // =====================================
  Widget _buildProVariantSystem() {
    return Container(
      padding: const EdgeInsets.all(15), 
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.deepOrange.shade200), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.grey.shade100, blurRadius: 5)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          const Text('Product Variations (Daraz Style)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange)),
          const SizedBox(height: 5),
          const Text('প্রথমে কালার এবং সাইজগুলো যুক্ত করুন। নিচে অটোমেটিক লিস্ট তৈরি হবে।', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Divider(height: 25),

          // --- Step 1: Add Colors & Images ---
          const Text('1. Colors & Images', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
          const SizedBox(height: 10),
          Row(
            children:[
              Expanded(
                child: TextField(
                  controller: colorInputCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. Black, Red...', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                onPressed: () {
                  if (colorInputCtrl.text.isNotEmpty) {
                    setState(() {
                      selectedColors.add({'name': colorInputCtrl.text.trim(), 'image': null});
                      colorInputCtrl.clear();
                      _generateVariantMatrix(); // নতুন কালার দিলেই লিস্ট আপডেট হবে
                    });
                  }
                },
                child: const Text('Add', style: TextStyle(color: Colors.white)),
              )
            ],
          ),
          const SizedBox(height: 10),
          // দেখানো হচ্ছে সিলেক্ট করা কালারগুলো
          if (selectedColors.isNotEmpty)
            Wrap(
              spacing: 10, runSpacing: 10,
              children: selectedColors.asMap().entries.map((entry) {
                int idx = entry.key;
                Map<String, dynamic> c = entry.value;
                return Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children:[
                      // ছবি আপলোডের বাটন (প্রতিটি কালারের জন্য)
                      InkWell(
                        onTap: () => _pickColorImage(idx),
                        child: Container(
                          width: 30, height: 30,
                          decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5)),
                          child: c['image'] != null 
                              ? (kIsWeb ? Image.network(c['image'].path, fit: BoxFit.cover) : Image.file(File(c['image'].path), fit: BoxFit.cover))
                              : const Icon(Icons.add_photo_alternate, size: 16, color: Colors.grey),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 5),
                      InkWell(
                        onTap: () => setState(() { selectedColors.removeAt(idx); _generateVariantMatrix(); }),
                        child: const Icon(Icons.cancel, color: Colors.red, size: 18),
                      )
                    ],
                  ),
                );
              }).toList(),
            ),
          
          const Divider(height: 30),

          // --- Step 2: Add Sizes/Units ---
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children:[
              const Text('2. Sizes / Variations', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: unitController,
                  decoration: const InputDecoration(labelText: 'Unit (e.g. Watt)', isDense: true, border: UnderlineInputBorder()),
                  onChanged: (v) => setState((){}),
                ),
              )
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children:[
              Expanded(
                child: TextField(
                  controller: sizeInputCtrl,
                  decoration: const InputDecoration(hintText: 'e.g. 120, XL, 32...', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () {
                  if (sizeInputCtrl.text.isNotEmpty) {
                    setState(() {
                      selectedSizes.add(sizeInputCtrl.text.trim());
                      sizeInputCtrl.clear();
                      _generateVariantMatrix(); // সাইজ দিলেও লিস্ট আপডেট হবে
                    });
                  }
                },
                child: const Text('Add', style: TextStyle(color: Colors.white)),
              )
            ],
          ),
          const SizedBox(height: 10),
          if (selectedSizes.isNotEmpty)
            Wrap(
              spacing: 8,
              children: selectedSizes.map((s) => Chip(
                label: Text('$s ${unitController.text}'),
                deleteIcon: const Icon(Icons.cancel, color: Colors.red, size: 18),
                onDeleted: () => setState(() { selectedSizes.remove(s); _generateVariantMatrix(); }),
              )).toList(),
            ),

          const Divider(height: 30, color: Colors.deepOrange, thickness: 1),

          // --- Step 3: The Matrix (Stock & Price Table) ---
          const Text('3. Set Stock & Extra Price', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          
          if (variantMatrix.isEmpty)
            const Center(child: Text('Add colors and sizes to generate list.', style: TextStyle(color: Colors.grey)))
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: variantMatrix.length,
              itemBuilder: (context, index) {
                var item = variantMatrix[index];
                bool isFirst = index == 0; // প্রথম আইটেম চেক (জালিয়াতি রোধ)
                
                String variantTitle = '';
                if (item['color'] != 'Default') variantTitle += item['color'];
                if (item['color'] != 'Default' && item['size'] != 'Default') variantTitle += ' - ';
                if (item['size'] != 'Default') variantTitle += '${item['size']} ${unitController.text}';
                if (variantTitle.isEmpty) variantTitle = 'Default Option';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children:[
                      // ভেরিয়েন্টের নাম
                      Expanded(flex: 2, child: Text(variantTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                      const SizedBox(width: 10),
                      // স্টক ফিল্ড
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          initialValue: item['stock'].toString(),
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Stock', isDense: true, border: OutlineInputBorder()),
                          onChanged: (val) {
                            variantMatrix[index]['stock'] = int.tryParse(val) ?? 0;
                            _calculateTotalStock();
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      // এক্সট্রা প্রাইজের ফিল্ড (জালিয়াতি রোধ লজিকসহ)
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          initialValue: item['price'].toString(),
                          keyboardType: TextInputType.number,
                          readOnly: isFirst, // প্রথমটা এডিট করা যাবে না
                          decoration: InputDecoration(
                            labelText: isFirst ? 'Base Price' : '+ Extra ৳',
                            isDense: true, 
                            filled: isFirst, fillColor: isFirst ? Colors.grey.shade200 : Colors.white,
                            border: const OutlineInputBorder()
                          ),
                          onChanged: (val) {
                            variantMatrix[index]['price'] = int.tryParse(val) ?? 0;
                          },
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            if (variantMatrix.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('* প্রথম ভেরিয়েন্টের এক্সট্রা প্রাইজ সবসময় ০ (শূন্য) হবে, যাতে কাস্টমার সঠিক বেস প্রাইজ দেখতে পায়।', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
              ),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, appBar: AppBar(title: const Text('ADD NEW PRODUCT'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          const Text('Product Images', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Row(children:[InkWell(onTap: pickImages, child: Container(height: 90, width: 90, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.deepOrange, width: 2)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.add_a_photo, color: Colors.deepOrange), Text('Add')]))), const SizedBox(width: 10), Expanded(child: SizedBox(height: 90, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: selectedImages.length, itemBuilder: (context, index) {return Container(width: 90, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: kIsWeb ? NetworkImage(selectedImages[index].path) : FileImage(File(selectedImages[index].path)) as ImageProvider, fit: BoxFit.cover)), child: Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() => selectedImages.removeAt(index)))));})))]),
          const SizedBox(height: 25), DropdownButtonFormField<String>(decoration: const InputDecoration(labelText: 'Select Category', border: OutlineInputBorder()), value: selectedCategory, items:['Fashion', 'Electronics', 'Mobiles', 'Home Decor', 'Beauty', 'Watches', 'Baby & Toys', 'Groceries', 'Automotive', 'Women\'s Bags', 'Men\'s Wallets', 'Muslim Fashion', 'Games & Hobbies', 'Computers', 'Sports & Outdoor', 'Men Shoes', 'Cameras', 'Travel & Luggage'].map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(), onChanged: (val) => setState(() => selectedCategory = val)),
          const SizedBox(height: 20), TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name', border: OutlineInputBorder())), const SizedBox(height: 15),
          Row(
            children:[
              Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base Price (৳)', border: OutlineInputBorder()))), 
              const SizedBox(width: 10), 
              Expanded(child: TextField(controller: originalPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Original Price (৳)', border: OutlineInputBorder()))), 
              const SizedBox(width: 10), 
              Expanded(child: TextField(
                controller: stockController, 
                readOnly: true, // এটি ইউজার নিজে এডিট করতে পারবে না
                decoration: InputDecoration(
                  labelText: 'Total Stock', 
                  border: const OutlineInputBorder(),
                  filled: true, fillColor: Colors.grey.shade200 // ছাই রঙের ব্যাকগ্রাউন্ড
                )
              )),
            ]
          ),
          const SizedBox(height: 25), 
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[TextField(controller: tagInput, decoration: InputDecoration(hintText: 'Paste Tags (Comma separated)', suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Colors.teal), onPressed: () { if (tagInput.text.trim().isNotEmpty) { setState(() { var t = tagInput.text.split(','); for(var x in t){if(x.trim().isNotEmpty) searchTags.add(x.trim());} tagInput.clear(); }); } }))), Wrap(spacing: 8, children: searchTags.map((item) => Chip(label: Text(item), onDeleted: () => setState(() => searchTags.remove(item)))).toList())])),
          const SizedBox(height: 25), 
          
          // =====================================
          //[NEW] কল করা হলো প্রো-ভেরিয়েন্ট সিস্টেম
          // =====================================
          _buildProVariantSystem(),

          const SizedBox(height: 25), TextField(controller: descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())), const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: uploadProduct, child: const Text('SUBMIT PRODUCT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))
        ]),
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন প্যানেল: Main Screen (Bottom Nav)
// ==========================================
class AdminMainScreen extends StatefulWidget {
  const AdminMainScreen({super.key});

  @override
  State<AdminMainScreen> createState() => _AdminMainScreenState();
}

class _AdminMainScreenState extends State<AdminMainScreen> {
  int _selectedIndex = 0;

  // অ্যাডমিনের ৫টি পেজ
  final List<Widget> _pages =[
    const AdminDashboard(),       // পেজ ১
    const AdminUserManagement(),  // পেজ ২
    const AdminOrderControl(),    // পেজ ৩
    const AdminFinanceReports(),  // পেজ ৪
    const AdminSettings(),        // পেজ ৫
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const[
          BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.people_alt), label: 'Users'),
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Finance'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
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
            ListTile(leading: const Icon(Icons.logout, color: Colors.red), title: const Text('Secure Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)), onTap: () async { await FirebaseAuth.instance.signOut(); if (context.mounted) { Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage())); } }),
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
                'target_role': isBulk ? widget.role : null,
                'sent_at': FieldValue.serverTimestamp(),
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
            if (isOnline) onlineUsers.add(doc);
            else offlineUsers.add(doc);
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
                if (days == 0) daysAgoText = 'Added today';
                else if (days == 1) daysAgoText = 'Added yesterday';
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
                                    activeColor: Colors.deepOrange,
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
// অ্যাডমিন পেজ ২: User & Seller Management (Address & Action Buttons)
// ==========================================
class AdminUserManagement extends StatefulWidget {
  const AdminUserManagement({super.key});

  @override
  State<AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<AdminUserManagement> {
  int _selectedTab = 1; 

  // ম্যাপের Lat/Lng থেকে আসল ঠিকানা অথবা কাস্টমারের ফায়ারবেস ঠিকানা বের করার ফাংশন
  Future<String> _fetchAddress(Map<String, dynamic> data, String uid, bool isSeller) async {
    if (isSeller) {
      if (data.containsKey('latitude') && data.containsKey('longitude')) {
        try {
          // Geocoding ব্যবহার করে স্থানাঙ্ক থেকে নাম বের করা
          List<Placemark> placemarks = await placemarkFromCoordinates(data['latitude'], data['longitude']);
          if (placemarks.isNotEmpty) {
            Placemark p = placemarks.first;
            String address = '';
            if (p.street != null && p.street!.isNotEmpty) address += '${p.street}, ';
            if (p.subLocality != null && p.subLocality!.isNotEmpty) address += '${p.subLocality}, ';
            if (p.locality != null && p.locality!.isNotEmpty) address += '${p.locality}';
            return address.isNotEmpty ? address : 'Lat: ${data['latitude']}, Lng: ${data['longitude']}';
          }
        } catch (e) {
          return 'Lat: ${data['latitude']}, Lng: ${data['longitude']}';
        }
      }
      return 'No location saved';
    } else {
      // কাস্টমারের ঠিকানা ফায়ারবেস থেকে আনা
      var snap = await FirebaseFirestore.instance.collection('users').doc(uid).collection('addresses').where('is_default', isEqualTo: true).limit(1).get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.first['shipping_address_text'] ?? 'Unknown address';
      }
      return 'No saved address yet';
    }
  }

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
          // উপরের টগল বাটন (Users vs Sellers)
          Padding(
            padding: const EdgeInsets.all(15), 
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center, 
              children:[
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 0), 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !isSellerTab ? Colors.deepOrange : Colors.white, 
                      foregroundColor: !isSellerTab ? Colors.white : Colors.black
                    ), 
                    child: const Text('Customers')
                  )
                ), 
                const SizedBox(width: 10), 
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 1), 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSellerTab ? Colors.teal : Colors.white, 
                      foregroundColor: isSellerTab ? Colors.white : Colors.black
                    ), 
                    child: const Text('Sellers')
                  )
                )
              ]
            )
          ),
          
          // ডাটাবেস থেকে রিয়েল-টাইম ডাটা আনার অংশ
          Expanded(
            child: StreamBuilder(
              stream: FirebaseFirestore.instance.collection('users')
                  .where('role', isEqualTo: !isSellerTab ? 'customer' : 'seller')
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Text(!isSellerTab ? 'No customers found!' : 'No sellers found!', style: const TextStyle(color: Colors.grey)));
                }

                var users = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    var userDoc = users[index];
                    Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
                    
                    String status = data.containsKey('status') ? data['status'] : 'approved';
                    bool isPending = status == 'pending';
                    String imgUrl = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';
                    String userName = data.containsKey('shop_name') && data['shop_name'].toString().isNotEmpty && isSellerTab ? data['shop_name'] : data['name'] ?? 'Unknown';

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: Padding(
                        padding: const EdgeInsets.all(15.0),
                        child: Column(
                          children:[
                            Row(
                              children:[
                                CircleAvatar(
                                  radius: 25,
                                  backgroundColor: Colors.grey.shade200,
                                  backgroundImage: imgUrl.isNotEmpty ? NetworkImage(imgUrl) : null,
                                  child: imgUrl.isEmpty ? Icon(!isSellerTab ? Icons.person : Icons.store, color: Colors.grey) : null,
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, 
                                    children:[
                                      Text(userName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                                      Text(data['email'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      if (isSellerTab)
                                        Text('Status: ${status.toUpperCase()}', style: TextStyle(color: isPending ? Colors.red : Colors.green, fontWeight: FontWeight.bold, fontSize: 12))
                                    ]
                                  )
                                ),
                                if (isSellerTab && isPending)
                                  ElevatedButton(
                                    onPressed: () {
                                      userDoc.reference.update({'status': 'approved'});
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller Approved Successfully! ✅')));
                                    }, 
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), 
                                    child: const Text('Approve', style: TextStyle(color: Colors.white))
                                  )
                                else if (isSellerTab && !isPending)
                                  const Icon(Icons.verified, color: Colors.green)
                              ],
                            ),
                            
                            const Divider(height: 25),
                            
                            // ঠিকানা দেখানোর অংশ
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:[
                                const Icon(Icons.location_on, color: Colors.red, size: 16),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: FutureBuilder<String>(
                                    future: _fetchAddress(data, userDoc.id, isSellerTab),
                                    builder: (context, addrSnap) {
                                      if (addrSnap.connectionState == ConnectionState.waiting) return const Text('Loading address...', style: TextStyle(fontSize: 12, color: Colors.grey));
                                      return Text(addrSnap.data ?? 'No address', style: const TextStyle(fontSize: 12, color: Colors.black54));
                                    }
                                  )
                                ),
                              ]
                            ),
                            const SizedBox(height: 15),

                            // অ্যাকশন বাটনসমূহ (Products, Sales, Orders)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly, 
                              children:[
                                if (isSellerTab) ...[
                                  TextButton.icon(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminSellerProductsPage(sellerId: userDoc.id, sellerName: userName))), 
                                    icon: const Icon(Icons.inventory_2, size: 18, color: Colors.deepPurple), 
                                    label: const Text('Products', style: TextStyle(color: Colors.deepPurple))
                                  ),
                                  TextButton.icon(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminSellerSalesPage(sellerId: userDoc.id, sellerName: userName))), 
                                    icon: const Icon(Icons.bar_chart, size: 18, color: Colors.teal), 
                                    label: const Text('Sales', style: TextStyle(color: Colors.teal))
                                  )
                                ] else ...[
                                  TextButton.icon(
                                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => AdminCustomerOrdersPage(customerId: userDoc.id, customerName: userName))), 
                                    icon: const Icon(Icons.receipt_long, size: 18, color: Colors.blue), 
                                    label: const Text('View Orders', style: TextStyle(color: Colors.blue))
                                  )
                                ]
                              ]
                            )
                          ],
                        ),
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
// নতুন সাব-পেজ ১: সেলারের প্রোডাক্ট লিস্ট
// ==========================================
class AdminSellerProductsPage extends StatelessWidget {
  final String sellerId;
  final String sellerName;
  const AdminSellerProductsPage({super.key, required this.sellerId, required this.sellerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$sellerName\'s Products', style: const TextStyle(fontSize: 16)), backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
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
              
              return Card(
                child: ListTile(
                  leading: Container(width: 50, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5)), child: img.isNotEmpty ? Image.network(img, fit: BoxFit.cover) : const Icon(Icons.image)),
                  title: Text(data['product_name'] ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('Price: ৳${data['price']} | Stock: ${data['stock']}'),
                  trailing: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: data['status'] == 'approved' ? Colors.green.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(5)), child: Text(data['status'] ?? 'pending', style: TextStyle(fontSize: 10, color: data['status'] == 'approved' ? Colors.green : Colors.orange))),
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
// নতুন সাব-পেজ ৩: কাস্টমারের অর্ডার হিস্ট্রি
// ==========================================
class AdminCustomerOrdersPage extends StatelessWidget {
  final String customerId;
  final String customerName;
  const AdminCustomerOrdersPage({super.key, required this.customerId, required this.customerName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$customerName\'s Orders', style: const TextStyle(fontSize: 16)), backgroundColor: Colors.blue, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('orders').where('user_id', isEqualTo: customerId).orderBy('order_date', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('এই কাস্টমার এখনো কোনো অর্ডার করেননি।'));

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              
              String dateString = 'Unknown Date';
              if (data['order_date'] != null) {
                DateTime date = (data['order_date'] as Timestamp).toDate();
                dateString = '${date.day}/${date.month}/${date.year}';
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Text('ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          Text(data['status'] ?? 'Pending', style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Text('Date: $dateString', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      const Divider(),
                      Text('Items: ${(data['items'] as List).length}', style: const TextStyle(fontSize: 13)),
                      const SizedBox(height: 5),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Text(data['payment_method'] ?? 'COD', style: const TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
                          Text('Total: ৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 15)),
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
// অ্যাডমিন পেজ ৩: Order & Delivery Control (Fixed Flow)
// ==========================================
class AdminOrderControl extends StatefulWidget {
  const AdminOrderControl({super.key});

  @override
  State<AdminOrderControl> createState() => _AdminOrderControlState();
}

class _AdminOrderControlState extends State<AdminOrderControl> {
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

                        if (deliveryMethod == 'rider') updateData['assigned_rider_id'] = selectedRiderId;
                        else { updateData['courier_name'] = courierNameCtrl.text.trim(); updateData['tracking_id'] = trackingIdCtrl.text.trim(); }

                        await FirebaseFirestore.instance.collection('orders').doc(orderId).update(updateData);

                        // [NEW] রাইডারকে নোটিফিকেশন পাঠানো
                        if (deliveryMethod == 'rider' && selectedRiderId != null) {
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'target_user_id': selectedRiderId,
                            'title': 'New Delivery Task 📦',
                            'message': 'Admin has assigned a new parcel to you. Check your Active Tasks.',
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
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.amber[100], 
          title: const Text('Logistics & Operations', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          bottom: const TabBar(
            isScrollable: false, // [FIXED]
            labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs:[Tab(text: 'Pending'), Tab(text: 'Process'), Tab(text: 'Transit'), Tab(text: 'Done')]
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো অর্ডার নেই।'));

            var allOrders = snapshot.data!.docs.toList();
            allOrders.sort((a, b) {
              var tA = (a.data() as Map<String, dynamic>)['order_date'];
              var tB = (b.data() as Map<String, dynamic>)['order_date'];
              if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
              return 0;
            });
            
            var pendingOrders = allOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList();
            var processingOrders = allOrders.where((doc) => ['Processing', 'Ready to Ship'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
            var dispatchedOrders = allOrders.where((doc) =>['Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
            var doneOrders = allOrders.where((doc) => ['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

            return TabBarView(
              children:[
                _buildOrderListView(pendingOrders),
                _buildOrderListView(processingOrders),
                _buildOrderListView(dispatchedOrders),
                _buildOrderListView(doneOrders),
              ],
            );
          }
        ),
      ),
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
              const Divider(height: 20),
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
                        Text('Phone: ${data['shipping_phone'] ?? 'N/A'}', style: const TextStyle(fontSize: 12, color: Colors.black87)), 
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
                  _buildActionButton(doc.id, status, data), // data পাস করা হলো
                ],
              )
            ],
          ),
        );
      }
    );
  }

  //[UPDATED] অ্যাডমিন লজিক ও নোটিফিকেশন
  Widget _buildActionButton(String orderId, String status, Map<String, dynamic> orderData) {
    if (status == 'Pending') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), 
        onPressed: () async {
          // ১. স্ট্যাটাস আপডেট
          await FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Processing', 'processing_at': FieldValue.serverTimestamp()});
          
          // ২. এই অর্ডারে যেসব সেলারের প্রোডাক্ট আছে, তাদের সবাইকে নোটিফিকেশন পাঠানো
          List<dynamic> items = orderData['items'] ??[];
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
            });
          }
        }, 
        child: const Text('Confirm Order', style: TextStyle(color: Colors.white))
      );
    } 
    else if (status == 'Processing') {
      return const Text('Waiting for Seller', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12));
    }
    else if (status == 'Ready to Ship') {
      return ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange), onPressed: () => _showAssignDeliveryModal(orderId), icon: const Icon(Icons.local_shipping, color: Colors.white, size: 18), label: const Text('Assign Delivery', style: TextStyle(color: Colors.white)));
    }
    else if (status == 'Dispatched' || status == 'In-Transit') {
      return const Text('Out for Delivery', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 12));
    }
    return const SizedBox();
  }
}

// ==========================================
// অ্যাডমিন পেজ ৪: Finance & Reports (Real-time Cash Flow & Payouts)
// ==========================================
class AdminFinanceReports extends StatelessWidget {
  const AdminFinanceReports({super.key});

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

          double totalDeliveredRevenue = 0; // সফলভাবে ডেলিভারি হওয়া মোট টাকা
          double expectedPendingRevenue = 0; // যে টাকাগুলো এখনো রাস্তায় আছে
          int criticalCount = 0;
          
          int codCount = 0;
          int onlineCount = 0;

          // সেলারদের পাওনা টাকার লিস্ট (Map)
          Map<String, double> sellerPayouts = {};
          double platformCommissionRate = 0.10; // ১০% অ্যাডমিন কমিশন

          for (var doc in snapshot.data!.docs) {
            Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
            String status = data['status'] ?? 'Pending';
            double amount = double.tryParse(data['total_amount'].toString()) ?? 0;
            String paymentMethod = data['payment_method'] ?? 'Cash on Delivery';

            if (status == 'Delivered') {
              totalDeliveredRevenue += amount;
              
              // পেমেন্ট মেথড কাউন্ট
              if (paymentMethod.contains('Cash') || paymentMethod == 'COD') codCount++;
              else onlineCount++;

              // সেলারদের পাওনা হিসাব করা (ডেলিভারি হওয়া প্রোডাক্ট থেকে)
              List<dynamic> items = data['items'] ??[];
              for (var item in items) {
                // আপনার আগের কোডে checkout এর সময় seller_id এর জায়গায় shop_name সেভ করা হয়েছিল
                String shopName = item['seller_id'] ?? 'Unknown Shop'; 
                double price = double.tryParse(item['price'].toString()) ?? 0;
                int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                
                // প্রোডাক্টের দামের ৯০% সেলার পাবে (১০% প্ল্যাটফর্মের লাভ)
                double sellerCut = (price * qty) * (1 - platformCommissionRate);
                
                sellerPayouts[shopName] = (sellerPayouts[shopName] ?? 0) + sellerCut;
              }
            } else if (status != 'Cancelled') {
              expectedPendingRevenue += amount;
              criticalCount++; // পেন্ডিং অর্ডারের সংখ্যা
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

                      // --- এখান থেকে আপনার নতুন বাটন শুরু ---
                      const SizedBox(height: 15),
                      SizedBox(
                        width: double.infinity, 
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                          ),
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminProfitLossReportPage()));
                          }, 
                          icon: const Icon(Icons.analytics, color: Colors.white), 
                          label: const Text('VIEW MONTHLY P&L & SALARIES', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))
                        ),
                      ),
                      const SizedBox(height: 15),
                      // --- বাটন শেষ ---
                    ]
                  )
                ),
                const SizedBox(height: 15),
                
                // ২. Expected / Pipeline Revenue
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
                
                // ৩. Revenue Source (Payment Methods Insights)
                const Text('Payment Methods Insights', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)), 
                  child: Column(
                    children:[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(children:[const Icon(Icons.money, color: Colors.teal), const SizedBox(height: 5), Text('COD (${codPercentage.toStringAsFixed(0)}%)', style: const TextStyle(fontWeight: FontWeight.bold))]),
                          Column(children:[const Icon(Icons.account_balance_wallet, color: Colors.pink), const SizedBox(height: 5), Text('Digital (${onlinePercentage.toStringAsFixed(0)}%)', style: const TextStyle(fontWeight: FontWeight.bold))]),
                        ],
                      ),
                      const SizedBox(height: 15),
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Row(
                          children:[
                            Expanded(flex: codCount == 0 && onlineCount == 0 ? 1 : codCount, child: Container(height: 10, color: Colors.teal)),
                            Expanded(flex: codCount == 0 && onlineCount == 0 ? 1 : onlineCount, child: Container(height: 10, color: Colors.pink)),
                          ],
                        ),
                      )
                    ],
                  )
                ),
                const SizedBox(height: 25),
                
                // ৪. Seller Payouts (সেলারদের কে কত টাকা পাবে)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const[
                    Text('Seller Payouts (Due)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('10% Platform Fee Applied', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
                const SizedBox(height: 10),
                
                if (sellerPayouts.isEmpty)
                  const Center(child: Padding(padding: EdgeInsets.all(20.0), child: Text('No delivered sales to settle yet.', style: TextStyle(color: Colors.grey))))
                else
                  ListView.builder(
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(), 
                    itemCount: sellerPayouts.keys.length, 
                    itemBuilder: (context, index) {
                      String shopName = sellerPayouts.keys.elementAt(index);
                      double amountDue = sellerPayouts[shopName]!;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.orange.shade100, child: const Icon(Icons.store, color: Colors.deepOrange)),
                          title: Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold)), 
                          subtitle: Text('Earnings: ৳${amountDue.toStringAsFixed(0)}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)), 
                          trailing: ElevatedButton(
                            onPressed: () {
                              // পেমেন্ট ক্লিয়ার করার পপ-আপ
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payout of ৳${amountDue.toStringAsFixed(0)} to $shopName processed! (Demo)')));
                            }, 
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))), 
                            child: const Text('Settle', style: TextStyle(color: Colors.white))
                          )
                        ),
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
// অ্যাডমিন পেজ ৫: System Settings & Admin (Super Admin & Staff Logic)
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

  void _showRoleManagementDialog() {
    TextEditingController emailCtrl = TextEditingController();
    String selectedRole = 'admin'; // 'admin' মানে স্টাফ

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
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Assign New Role', border: OutlineInputBorder(), isDense: true),
                  // এখন সুপার অ্যাডমিন স্টাফ বানাতে পারবে
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
                          // প্রোফাইলে সুপার অ্যাডমিন নাকি শুধু অ্যাডমিন তা দেখাবে
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
                          
                          // এই অপশনগুলো সবাই দেখতে পাবে
                          _buildSettingItem(Icons.store, 'Store Details', onTap: () {
                            Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminStoreDetailsPage()));
                          }),
                          _buildSettingItem(Icons.people, 'Customer & Staff List', trailingText: 'View', onTap: () {
                             Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserStatusPage(role: 'admin', title: 'Staff & Admins')));
                          }),
                          
                          // =====================================
                          // শুধুমাত্র SUPER ADMIN এই অপশনগুলো দেখতে ও কন্ট্রোল করতে পারবে
                          // =====================================
                          if (isSuperAdmin) ...[
                            const SizedBox(height: 20),
                            const Text('Super Admin Privileges', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                            const SizedBox(height: 10),
                            
                            _buildSettingItem(Icons.settings_applications, 'App Config (Commission)', onTap: _showAppConfigDialog),
                            _buildSettingItem(Icons.admin_panel_settings, 'Role Management', onTap: _showRoleManagementDialog),
                            _buildSettingItem(Icons.security, 'Security Log', onTap: () {
                               Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminSecurityLogPage()));
                            }),
                            _buildSettingItem(Icons.cloud_download, 'Export Database', onTap: () {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Report export feature will be available soon!')));
                            }),
                          ],
                          
                          // যদি সাধারণ স্টাফ হয়, তবে তাকে মেসেজ দেখাবে
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
                              onPressed: () async {
                                SharedPreferences prefs = await SharedPreferences.getInstance();
                                await prefs.clear();
                                await FirebaseAuth.instance.signOut(); 
                                if(context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
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
// রাইডার মেইন স্ক্রিন (Bottom Nav)
// ==========================================
class RiderMainScreen extends StatefulWidget {
  const RiderMainScreen({super.key});

  @override
  State<RiderMainScreen> createState() => _RiderMainScreenState();
}

class _RiderMainScreenState extends State<RiderMainScreen> {
  int _selectedIndex = 0;

  final List<Widget> _pages =[
    const RiderDashboard(),       // পেজ ১: Dashboard
    const RiderTaskManagement(),  // পেজ ২: Tasks
    const RiderOrderDetails(),    // পেজ ৩: Route/Order
    const RiderDeliveryEarnings(),// পেজ ৪: Delivery
    const RiderProfile(),         // পেজ ৫: Profile
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.deepOrange,
        unselectedItemColor: Colors.grey,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const[
          BottomNavigationBarItem(icon: Icon(Icons.motorcycle), label: 'Dashboard'),
          BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'Tasks'),
          BottomNavigationBarItem(icon: Icon(Icons.map_outlined), label: 'Route'),
          BottomNavigationBarItem(icon: Icon(Icons.check_circle_outline), label: 'Settle'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ১: Dashboard (Gig-Economy Ready & Live Tracking)
// ==========================================
class RiderDashboard extends StatefulWidget {
  const RiderDashboard({super.key});

  @override
  State<RiderDashboard> createState() => _RiderDashboardState();
}

class _RiderDashboardState extends State<RiderDashboard> {

  // রাইডারের অনলাইন/অফলাইন স্ট্যাটাস পরিবর্তন করার ফাংশন
  Future<void> _toggleOnlineStatus(bool currentStatus) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
        'is_online': !currentStatus,
        'last_active': FieldValue.serverTimestamp(),
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(!currentStatus ? 'You are now ONLINE 🟢. Ready to receive tasks!' : 'You are now OFFLINE 🔴.'),
          backgroundColor: !currentStatus ? Colors.green : Colors.red,
          duration: const Duration(seconds: 2),
        )
      );
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
        actions:[IconButton(icon: const Icon(Icons.notifications_active, color: Colors.white), onPressed: () {})]
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            // ==========================================
            // ১. রাইডার প্রোফাইল এবং অনলাইন/অফলাইন টগল
            // ==========================================
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
                      )
                  ],
                );
              }
            ),
            const SizedBox(height: 20),

            // ==========================================
            // ২. পারফরম্যান্স স্ট্যাটাস (লাইভ ডাটা)
            // ==========================================
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').where('assigned_rider_id', isEqualTo: currentUser.uid).snapshots(),
              builder: (context, snapshot) {
                int completedToday = 0;
                double estimatedEarnings = 0;

                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    var data = doc.data() as Map<String, dynamic>;
                    if (data['status'] == 'Delivered') {
                      // যদি ডেলিভারি আজকে হয়ে থাকে (Simple check)
                      if (data['order_date'] != null) {
                         DateTime dt = (data['order_date'] as Timestamp).toDate();
                         if (dt.day == DateTime.now().day && dt.month == DateTime.now().month) {
                           completedToday++;
                           // পার ডেলিভারি একটি ফিক্সড এমাউন্ট ধরা হলো (যেমন: ৪০ টাকা), ভবিষ্যতে এটি ডাইনামিক হবে
                           estimatedEarnings += 40.0; 
                         }
                      }
                    }
                  }
                }

                return Container(
                  width: double.infinity, padding: const EdgeInsets.all(20), 
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)), 
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, 
                    children:[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          const Text('Today\'s Earnings', style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
                          const Text('Base Pay + Task Bonus', style: TextStyle(fontSize: 10, color: Colors.teal)),
                        ],
                      ), 
                      Text('৳${estimatedEarnings.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87)), 
                      const SizedBox(height: 15), 
                      Row(
                        children:[
                          Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10)), child: Column(children:[const Text('Deliveries Today', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)), Text('$completedToday', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal))]))), 
                          const SizedBox(width: 10), 
                          Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10)), child: Column(children: const[Text('Overall Rating', style: TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)), Text('5.0', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange))]))),
                        ]
                      )
                    ]
                  )
                );
              }
            ),
            const SizedBox(height: 25),

            // ==========================================
            // ৩. অ্যাক্টিভ টাস্ক লিস্ট (Admin Assigned)
            // ==========================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween, 
              children: const[
                Text('Active Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), 
                Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey)
              ]
            ),
            const SizedBox(height: 10),

            StreamBuilder<QuerySnapshot>(
              // শুধুমাত্র এই রাইডারকে দেওয়া এবং 'Dispatched' স্ট্যাটাসে থাকা অর্ডারগুলো আনবে
              stream: FirebaseFirestore.instance.collection('orders')
                  .where('assigned_rider_id', isEqualTo: currentUser.uid)
                  .where('status', isEqualTo: 'Dispatched')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()));
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Container(
                    width: double.infinity, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                    child: Column(
                      children: const[
                         Icon(Icons.coffee, size: 40, color: Colors.grey),
                         SizedBox(height: 10),
                         Text('No active tasks right now.\nTake a break or wait for admin to assign.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))
                      ],
                    ),
                  );
                }

                var tasks = snapshot.data!.docs;

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: tasks.length,
                  itemBuilder: (context, index) {
                    var doc = tasks[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    
                    // প্রথম আইটেমের নাম বের করা (সিম্পল দেখানোর জন্য)
                    List<dynamic> items = data['items'] ??[];
                    String itemName = items.isNotEmpty ? items[0]['product_name'] : 'Unknown Item';
                    if (items.length > 1) itemName += ' (+${items.length - 1} more)';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10), 
                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.teal.shade200)), 
                      child: ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.delivery_dining, color: Colors.white)), 
                        title: Text('Deliver: $itemName', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('To: ${data['shipping_name'] ?? 'Customer'}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                            Text('Amount to collect: ৳${data['total_amount']}', style: const TextStyle(fontSize: 12, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                          ],
                        ), 
                        trailing: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(horizontal: 10)),
                          onPressed: () {
                            // পরবর্তীতে এই বাটনে চাপ দিলে ২ নম্বর (Tasks) বা ৩ নম্বর (Route) পেজে নিয়ে যাবে
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Go to Tasks tab for details!')));
                          },
                          child: const Text('View', style: TextStyle(color: Colors.white, fontSize: 12)),
                        )
                      )
                    );
                  }
                );
              }
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ২: Task Management (Fixed Sorting)
// ==========================================
class RiderTaskManagement extends StatelessWidget {
  const RiderTaskManagement({super.key});

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey.shade100,
        appBar: AppBar(
          backgroundColor: Colors.amber[100], elevation: 0,
          title: const Text('TASK MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black),
          bottom: const TabBar(
            isScrollable: false, labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            tabs:[Tab(text: 'Pickup'), Tab(text: 'Transit'), Tab(text: 'Done')]
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').where('assigned_rider_id', isEqualTo: currentUser.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red))));
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No assigned tasks.'));

            var allTasks = snapshot.data!.docs.toList();
            allTasks.sort((a, b) {
              var tA = (a.data() as Map<String, dynamic>)['order_date'];
              var tB = (b.data() as Map<String, dynamic>)['order_date'];
              if (tA is Timestamp && tB is Timestamp) return tB.compareTo(tA);
              return 0;
            });

            var pendingPickup = allTasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Dispatched').toList(); 
            var inTransit = allTasks.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'In-Transit').toList();
            var delivered = allTasks.where((doc) => ['Delivered', 'Delivery Failed'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

            return TabBarView(
              children:[
                _buildTaskList(context, pendingPickup, 'Pick Up', Colors.orange),
                _buildTaskList(context, inTransit, 'Deliver Now', Colors.blue),
                _buildTaskList(context, delivered, 'Done', Colors.green, isCompleted: true),
              ],
            );
          }
        ),
      ),
    );
  }

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

        return Container(
          margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children:[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('Order ID: $orderId', style: const TextStyle(fontWeight: FontWeight.bold)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: actionColor.withOpacity(0.1), borderRadius: BorderRadius.circular(5)), child: Text(status, style: TextStyle(color: actionColor, fontWeight: FontWeight.bold, fontSize: 12))),
                ]
              ),
              const SizedBox(height: 5),
              Text('Customer: $customerName', style: const TextStyle(color: Colors.black87)),
              Text('Drop-off: $address', style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('Collect: ৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                  if (!isCompleted)
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: actionColor), 
                      onPressed: () async {
                        if (status == 'Dispatched') {
                          // Pick Up এ চাপলে In-Transit হবে
                          await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({'status': 'In-Transit'});
                          
                          // কাস্টমারকে Out for Delivery নোটিফিকেশন
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'target_user_id': data['user_id'],
                            'title': 'Out for Delivery 🛵',
                            'message': 'আপনার পার্সেলটি রাইডারের কাছে দেওয়া হয়েছে এবং আপনার ঠিকানায় যাচ্ছে।',
                            'sent_at': FieldValue.serverTimestamp(),
                          });

                          // অ্যাডমিনকে নোটিফিকেশন
                          await FirebaseFirestore.instance.collection('notifications').add({
                            'title': 'Rider Picked Up Parcel 📦',
                            'message': 'অর্ডার #${orderId} রাইডার পিকআপ করেছেন এবং রাস্তায় আছেন।',
                            'target_role': 'admin',
                            'sent_at': FieldValue.serverTimestamp(),
                          });

                          if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Picked Up! Move to In-Transit tab.')));
                        } else if (status == 'In-Transit') {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Go to the ROUTE tab to complete delivery.')));
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

  // সফল ডেলিভারি এবং প্রুফ (ছবি) আপলোড করার লজিক
  Future<void> _processSuccessfulDelivery(QueryDocumentSnapshot doc, double cusLat, double cusLng) async {
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw 'Please enable GPS Location!';
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
      
      Position riderPos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);

      // দূরত্ব চেক (৫০০ মিটার)
      if (cusLat != 0.0 && cusLng != 0.0) {
        double dist = Geolocator.distanceBetween(riderPos.latitude, riderPos.longitude, cusLat, cusLng);
        if (dist > 500) { 
          throw 'You are too far (${(dist).toStringAsFixed(0)} meters) from the customer address!';
        }
      }

      if (!mounted) return;
      Navigator.pop(context); // ক্লোজ প্রথম লোডিং

      // প্রুফ অফ ডেলিভারি (ক্যামেরা)
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera, imageQuality: 50);
      if (photo == null) return; 

      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[CircularProgressIndicator(), SizedBox(height:10), Text('Uploading Proof...', style: TextStyle(color: Colors.white))])));

      String fileName = 'proof_${doc.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      Reference ref = FirebaseStorage.instance.ref().child('delivery_proofs').child(fileName);
      await ref.putFile(File(photo.path));
      String proofUrl = await ref.getDownloadURL();

      // ডেলিভারি সম্পন্ন হলে লাইভ ট্র্যাকিং বন্ধ করা
      _positionStreamSubscription?.cancel();
      _currentlyTrackingOrderId = null;

      // ডাটাবেস আপডেট
      await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
        'status': 'Delivered',
        'delivered_lat': riderPos.latitude,
        'delivered_lng': riderPos.longitude,
        'proof_image_url': proofUrl,
        'delivered_at': FieldValue.serverTimestamp(),
      });

      // [NEW] ডেলিভারি সম্পন্ন হওয়ার নোটিফিকেশন
      await FirebaseFirestore.instance.collection('notifications').add({
        'target_user_id': (doc.data() as Map<String, dynamic>)['user_id'],
        'title': 'Order Delivered 🎉',
        'message': 'আপনার পার্সেলটি সফলভাবে ডেলিভারি করা হয়েছে। D Shop এর সাথে থাকার জন্য ধন্যবাদ!',
        'sent_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery Completed successfully! ✅'), backgroundColor: Colors.green));

    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: Colors.red));
    }
  }

  // ফেইলড ডেলিভারি লজিক
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
                const Text('Please select the exact reason why this delivery could not be completed:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedReason,
                  isExpanded: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items:[
                    'Customer not answering phone',
                    'Customer refused to take parcel',
                    'Wrong or incomplete address',
                    'Customer asked to reschedule',
                    'Product damaged during transit'
                  ].map((r) => DropdownMenuItem(value: r, child: Text(r, style: const TextStyle(fontSize: 13)))).toList(),
                  onChanged: (val) => setDialogState(() => selectedReason = val!),
                ),
              ],
            ),
            actions:[
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () async {
                  _positionStreamSubscription?.cancel(); // ট্র্যাকিং বন্ধ
                  _currentlyTrackingOrderId = null;
                  
                  await FirebaseFirestore.instance.collection('orders').doc(doc.id).update({
                    'status': 'Delivery Failed',
                    'failed_reason': selectedReason,
                    'failed_at': FieldValue.serverTimestamp(),
                  });

                  // [NEW] ডেলিভারি ফেইল হওয়ার নোটিফিকেশন
                  await FirebaseFirestore.instance.collection('notifications').add({
                    'target_user_id': (doc.data() as Map<String, dynamic>)['user_id'],
                    'title': 'Delivery Failed ❌',
                    'message': 'দুঃখিত, আপনার পার্সেলটি ডেলিভারি করা সম্ভব হয়নি। কারণ: $selectedReason',
                    'sent_at': FieldValue.serverTimestamp(),
                  });

                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Delivery marked as FAILED.'), backgroundColor: Colors.orange));
                  }
                }, 
                child: const Text('Submit Report', style: TextStyle(color: Colors.white))
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
                                String address = Uri.encodeComponent(data['shipping_address_text'] ?? '');
                                final Uri googleMapsUrl = Uri.parse("https://www.google.com/maps/dir/?api=1&destination=$address");
                                if (await canLaunchUrl(googleMapsUrl)) await launchUrl(googleMapsUrl);
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
                }).toList(),
                
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
                  value: selectedVehicle,
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
                      onPressed: () async {
                        // অফলাইন করে লগআউট করা
                        if(currentUser != null) await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'is_online': false});
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await FirebaseAuth.instance.signOut(); 
                        if(context.mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
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

// ==========================================
// ক্যাটাগরি পেজ (রঙিন আইকন ও ব্যাক বাটন সহ)
// ==========================================
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  int _selectedCategoryIndex = 0; 

  final List<Map<String, dynamic>> mainCategories =[
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
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;
    int gridColumns = screenWidth > 900 ? 4 : (screenWidth > 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 1,
        // [FIXED] ব্যাক বাটন যুক্ত করা হয়েছে যা হোম পেজে নিয়ে যাবে
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black), 
          onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()))
        ),
        title: const Text('Categories', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true, actions:[IconButton(icon: const Icon(Icons.search, color: Colors.black), onPressed: () {})],
      ),
      body: Row(
        children:[
          Container(
            width: 100, color: Colors.grey.shade50,
            child: ListView.builder(
              itemCount: mainCategories.length,
              itemBuilder: (context, index) {
                bool isSelected = _selectedCategoryIndex == index;
                return InkWell(
                  onTap: () { setState(() { _selectedCategoryIndex = index; }); },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 5),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white : Colors.transparent,
                      border: Border(left: BorderSide(color: isSelected ? Colors.deepOrange : Colors.transparent, width: 4))
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children:[
                        Icon(mainCategories[index]['icon'], color: isSelected ? Colors.deepOrange : mainCategories[index]['color'], size: 24),
                        const SizedBox(height: 5),
                        Text(
                          mainCategories[index]['name'], textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 10, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: Container(
              color: Colors.white, padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${mainCategories[_selectedCategoryIndex]['name']} Products', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  Expanded(
                    child: StreamBuilder(
                      stream: FirebaseFirestore.instance.collection('products')
                          .where('status', isEqualTo: 'approved')
                          .where('category', isEqualTo: mainCategories[_selectedCategoryIndex]['name'])
                          .snapshots(),
                      builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.production_quantity_limits, size: 50, color: Colors.grey.shade300), const SizedBox(height: 10), const Text('No products found here yet!', style: TextStyle(color: Colors.grey))]));

                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: gridColumns, childAspectRatio: 0.70, crossAxisSpacing: 10, mainAxisSpacing: 10),
                          itemCount: snapshot.data!.docs.length,
                          itemBuilder: (context, index) { return _buildRealProductCard(context, snapshot.data!.docs[index]); },
                        );
                      }
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealProductCard(BuildContext context, QueryDocumentSnapshot product) {
    Map<String, dynamic> data = product.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    String firstImage = images.isNotEmpty ? images[0] : '';
    
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
// কাস্টমার লোকেশন সেটআপ পেজ (Map Pin + Dropdown)
// ==========================================
class AddressSetupPage extends StatefulWidget {
  const AddressSetupPage({super.key});

  @override
  State<AddressSetupPage> createState() => _AddressSetupPageState();
}

class _AddressSetupPageState extends State<AddressSetupPage> {
  LatLng _currentPosition = const LatLng(23.6062, 90.1345); // ডিফল্ট দোহারের লোকেশন
  GoogleMapController? _mapController;
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _landmarkController = TextEditingController(); // বাড়ির নাম/ল্যান্ডমার্ক

  // ড্রপডাউনের জন্য ভেরিয়েবল
  String? selectedThana;
  String? selectedUnion;

  // গ্রাম এখন আর ড্রপডাউন হবে না, কাস্টমার টাইপ করবে
  final TextEditingController _villageController = TextEditingController(); 
  
  // আমাদের ডাটাবেস (শুধুমাত্র থানা এবং ইউনিয়ন)
  final Map<String, List<String>> locationData = {
    'দোহার':[
      'দোহার পৌরসভা', 'কুসুমহাটি', 'সুতারপাড়া', 'নয়াবাড়ী', 
      'নারিশা', 'বিলাসপুর', 'মাহমুদপুর', 'মুকসুদপুর', 'রাইপাড়া'
    ],
    'নবাবগঞ্জ':[
      'নবাবগঞ্জ সদর', 'বান্দুরা', 'আগলা', 'চুড়াইন', 'শোল্লা', 'কলাকোপা', 'গালিমপুর'
    ],
    'শ্রীনগর':[
      'শ্রীনগর সদর', 'হাঁসাড়া', 'ভাগ্যকুল', 'বাড়ৈখালী', 'তন্তর'
    ]
  };

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
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
  }

  // ম্যাপ টানলে শুধু স্থানাঙ্ক (Lat/Lng) সেভ হবে, কোনো টেক্সট খুঁজবে না
  void _onCameraMove(CameraPosition position) {
    _currentPosition = position.target;
  }

  void saveAddress() async {
    if (_nameController.text.isEmpty || _phoneController.text.isEmpty || 
        selectedThana == null || selectedUnion == null || _villageController.text.trim().isEmpty || 
        _landmarkController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে সব তথ্য সঠিকভাবে দিন!')));
      return;
    }

    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      showDialog(context: context, builder: (context) => const Center(child: CircularProgressIndicator()));

      String fullAddress = '${_landmarkController.text.trim()}, গ্রাম: ${_villageController.text.trim()}, ইউনিয়ন: $selectedUnion, থানা: $selectedThana, ঢাকা।';

      // চেক করা হচ্ছে ইউজারের আগে কোনো ঠিকানা আছে কি না
      var addressRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('addresses');
      var existingAddresses = await addressRef.limit(1).get();
      
      // যদি আগে কোনো ঠিকানা না থাকে, তবে এটিই অটোমেটিক ডিফল্ট হয়ে যাবে
      bool isFirstAddress = existingAddresses.docs.isEmpty;

      // এখন ডাটা 'addresses' সাব-কালেকশনে সেভ হচ্ছে
      await addressRef.add({
        'shipping_name': _nameController.text.trim(),
        'shipping_phone': _phoneController.text.trim(),
        'shipping_address_text': fullAddress, 
        'latitude': _currentPosition.latitude,
        'longitude': _currentPosition.longitude,
        'is_default': isFirstAddress, // প্রথমবার true হবে
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
          // উপরের অর্ধেক: ম্যাপ (শুধু পিন ড্রপের জন্য)
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

          // নিচের অর্ধেক: ড্রপডাউন ও ফর্ম
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
                        Expanded(child: TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'আপনার নাম', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)))),
                        const SizedBox(width: 10),
                        Expanded(child: TextField(controller: _phoneController, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'ফোন নম্বর', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)))),
                      ],
                    ),
                    const SizedBox(height: 15),
                    
                    // ১. থানা ড্রপডাউন
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'থানা / উপজেলা', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      value: selectedThana,
                      items: locationData.keys.map((String thana) {
                        return DropdownMenuItem<String>(value: thana, child: Text(thana));
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() {
                          selectedThana = newValue;
                          selectedUnion = null; // থানা পাল্টলে ইউনিয়ন রিসেট হবে
                        });
                      },
                    ),
                    const SizedBox(height: 10),

                    // ২. ইউনিয়ন ড্রপডাউন
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(labelText: 'ইউনিয়ন / পৌরসভা', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                      value: selectedUnion,
                      items: selectedThana == null ? [] : locationData[selectedThana]!.map((String union) {
                        return DropdownMenuItem<String>(value: union, child: Text(union));
                      }).toList(),
                      onChanged: (newValue) {
                        setState(() { selectedUnion = newValue; });
                      },
                    ),
                    const SizedBox(height: 10),

                    // ৩. গ্রাম / পাড়ার নাম (ইউজার নিজে টাইপ করবে)
                    TextField(
                      controller: _villageController, 
                      decoration: const InputDecoration(labelText: 'গ্রাম / পাড়া / মহল্লা', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10))
                    ),
                    const SizedBox(height: 10),

                    // ৪. ল্যান্ডমার্ক বা বাড়ির নাম
                    TextField(
                      controller: _landmarkController, 
                      decoration: const InputDecoration(labelText: 'বাড়ির নাম বা ল্যান্ডমার্ক (যেমন: মসজিদের পাশে)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10))
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
// কাস্টমারের অর্ডার হিস্ট্রি পেজ
// ==========================================
class OrderHistoryPage extends StatelessWidget {
  const OrderHistoryPage({super.key});

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
            isScrollable: false, // [FIXED] স্ক্রল অফ করা হয়েছে যাতে ৪টা ট্যাব স্ক্রিনে সমানভাবে ফিট হয়
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
                _buildOrderList(context, allOrders), 
                _buildOrderList(context, allOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList()), 
                _buildOrderList(context, allOrders.where((doc) =>['Processing', 'Ready to Ship', 'Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList()), 
                _buildOrderList(context, allOrders.where((doc) =>['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList()), 
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTimelineRow(String title, dynamic timestamp, bool isCompleted, {bool isLast = false}) {
    String timeStr = '--';
    if (timestamp != null && timestamp is Timestamp) {
      DateTime dt = timestamp.toDate();
      timeStr = '${dt.day}/${dt.month}/${dt.year} ${dt.hour > 12 ? dt.hour - 12 : dt.hour}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'PM' : 'AM'}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children:[
              Icon(isCompleted ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: isCompleted ? Colors.teal : Colors.grey),
              if (!isLast) Container(height: 15, width: 2, color: isCompleted ? Colors.teal : Colors.grey.shade300),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                Text(title, style: TextStyle(fontSize: 12, fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal, color: isCompleted ? Colors.black87 : Colors.grey)),
                if (isCompleted && timestamp != null) Text(timeStr, style: const TextStyle(fontSize: 10, color: Colors.teal)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<QueryDocumentSnapshot> orders) {
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
                    Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(data['status'] ?? 'Pending', style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12))),
                  ],
                ),
                const SizedBox(height: 5),
                Text('Placed on: $dateString', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Divider(height: 20),
                
                // =====================================
                //[NEW] Order Tracking Timeline
                // =====================================
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children:[
                      const Text('Order Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blueGrey)),
                      const SizedBox(height: 8),
                      _buildTimelineRow('Order Placed', data['order_date'], true),
                      _buildTimelineRow('Confirmed & Processing', data['processing_at'], data['status'] != 'Pending'),
                      _buildTimelineRow('Packed & Ready', data['ready_to_ship_at'], ['Ready to Ship', 'Dispatched', 'In-Transit', 'Delivered'].contains(data['status'])),
                      _buildTimelineRow('Handed to Courier/Rider', data['dispatched_at'],['Dispatched', 'In-Transit', 'Delivered'].contains(data['status'])),
                      _buildTimelineRow('Delivered Successfully', data['delivered_at'], data['status'] == 'Delivered', isLast: true),
                    ],
                  ),
                ),
                const Divider(height: 20),

                ListView.builder(
                  shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: items.length,
                  itemBuilder: (context, i) {
                    var item = items[i];
                    return Padding(padding: const EdgeInsets.only(bottom: 5.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[Expanded(child: Text('${item['quantity']}x ${item['product_name']}', maxLines: 1, overflow: TextOverflow.ellipsis)), Text('৳${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold))]));
                  }
                ),
                const Divider(height: 20),
                
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
                            onPressed: () {
                              Navigator.push(context, MaterialPageRoute(builder: (context) => LiveTrackingPage(orderId: order.id)));
                            },
                          ),
                        if (status == 'In-Transit') const SizedBox(width: 8),

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
                          activeColor: Colors.teal,
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
// Admin Manage Categories Page (Firebase Storage & Firestore)
// ==========================================
class AdminManageCategoriesPage extends StatefulWidget {
  const AdminManageCategoriesPage({super.key});

  @override
  State<AdminManageCategoriesPage> createState() => _AdminManageCategoriesPageState();
}

class _AdminManageCategoriesPageState extends State<AdminManageCategoriesPage> {
  final TextEditingController categoryNameController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? selectedImage;
  // আপনার দেওয়া ক্যাটাগরি লিস্ট থেকে শুধু নামগুলো নেওয়া হলো
  final List<String> presetCategories =[
    'Fashion', 'Electronics', 'Mobiles', 'Home Decor', 'Beauty', 
    'Watches', 'Baby & Toys', 'Groceries', 'Automotive', 'Women\'s Bags',
    'Men\'s Wallets', 'Muslim Fashion', 'Games & Hobbies', 'Computers',
    'Sports & Outdoor', 'Men Shoes', 'Cameras', 'Travel & Luggage'
  ];

  // গ্যালারি থেকে ক্যাটাগরির আইকন/ছবি সিলেক্ট করা
  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        selectedImage = image;
      });
    }
  }

  // ফায়ারবেসে ক্যাটাগরি আপলোড করা
  Future<void> uploadCategory() async {
    if (categoryNameController.text.isEmpty || selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter name and select an image!')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      // ১. ছবি স্টোরেজে আপলোড করা
      String fileName = 'category_${DateTime.now().millisecondsSinceEpoch}_${selectedImage!.name}';
      Reference ref = FirebaseStorage.instance.ref().child('category_images').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await selectedImage!.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/png'));
      } else {
        await ref.putFile(File(selectedImage!.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();

      // ২. ডাটাবেসে ক্যাটাগরির নাম ও ছবির লিংক সেভ করা
      await FirebaseFirestore.instance.collection('categories').add({
        'name': categoryNameController.text.trim(),
        'image_url': downloadUrl,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      setState(() {
        selectedImage = null;
        categoryNameController.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Category Added Successfully! 🎉')));
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(title: const Text('Manage Categories'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children:[
          // ক্যাটাগরি আপলোডের ফর্ম
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                const Text('Add New Category', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 15),
                Row(
                  children:[
                    InkWell(
                      onTap: pickImage,
                      child: Container(
                        height: 60, width: 60,
                        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.deepOrange)),
                        child: selectedImage != null 
                            ? (kIsWeb ? Image.network(selectedImage!.path, fit: BoxFit.cover) : Image.file(File(selectedImage!.path), fit: BoxFit.cover))
                            : const Icon(Icons.add_photo_alternate, color: Colors.deepOrange),
                      ),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: TextField(
                        controller: categoryNameController,
                        decoration: InputDecoration(
                          labelText: 'Category Name (e.g. Mobile)', 
                          border: const OutlineInputBorder(), 
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                          // এই অংশটি ড্রপডাউন মেনু তৈরি করবে
                          suffixIcon: PopupMenuButton<String>(
                            icon: const Icon(Icons.arrow_drop_down, color: Colors.deepOrange, size: 30),
                            tooltip: 'Select Category',
                            onSelected: (String value) {
                              // লিস্ট থেকে সিলেক্ট করলে টেক্সট বক্সে অটোমেটিক বসে যাবে
                              setState(() {
                                categoryNameController.text = value;
                              });
                            },
                            itemBuilder: (BuildContext context) {
                              return presetCategories.map((String choice) {
                                return PopupMenuItem<String>(
                                  value: choice,
                                  child: Text(choice),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 15)),
                      onPressed: uploadCategory,
                      child: const Text('ADD', style: TextStyle(color: Colors.white)),
                    )
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 10),
          const Padding(padding: EdgeInsets.all(15.0), child: Align(alignment: Alignment.centerLeft, child: Text('Existing Categories', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
          
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
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade100,
                          backgroundImage: NetworkImage(doc['image_url']),
                        ),
                        title: Text(doc['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            // ডিলিট করার কমান্ড
                            FirebaseFirestore.instance.collection('categories').doc(doc.id).delete();
                          },
                        ),
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
        'type': 'all_users',
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
// নতুন পেজ: Dedicated Shop Page (Immersive Banner & SliverAppBar)
// ==========================================
class ShopPage extends StatefulWidget {
  final String sellerId;
  const ShopPage({super.key, required this.sellerId});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  final ImagePicker _picker = ImagePicker();

  // দোকানের ব্যানার আপলোড করার ফাংশন
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
      
      // ফায়ারবেসে সেভ করা হচ্ছে
      await FirebaseFirestore.instance.collection('users').doc(widget.sellerId).update({
        'shop_banner_url': downloadUrl
      });

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
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
      // AppBar এর বদলে CustomScrollView ব্যবহার করা হয়েছে
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
            shopName = shopData.containsKey('shop_name') && shopData['shop_name'].toString().isNotEmpty ? shopData['shop_name'] : shopData['name'] ?? 'Unknown Shop';
            shopLogo = shopData.containsKey('profile_image_url') ? shopData['profile_image_url'] : '';
            shopBanner = shopData.containsKey('shop_banner_url') ? shopData['shop_banner_url'] : '';
          }

          return CustomScrollView(
            slivers:[
              // ==========================================
              // ১. ম্যাজিক SliverAppBar (ব্যানার একদম উপর পর্যন্ত যাবে)
              // ==========================================
              SliverAppBar(
                expandedHeight: 230.0, // ব্যানারের হাইট
                pinned: true,          // স্ক্রল করলে উপরে আটকে থাকবে
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
                      // ব্যানার ইমেজ বা ডিফল্ট কালার
                      shopBanner.isNotEmpty
                          ? Image.network(shopBanner, fit: BoxFit.cover)
                          : Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.deepOrange, Colors.orange.shade400],
                                  begin: Alignment.topCenter, end: Alignment.bottomCenter
                                )
                              )
                            ),
                      
                      // ডার্ক গ্রেডিয়েন্ট শ্যাডো (যাতে আইকন ও লেখা ছবির সাথে মিশে না যায়)
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors:[
                              Colors.black.withOpacity(0.6), // উপরের দিকে কালো ছায়া (আইকনের জন্য)
                              Colors.transparent, 
                              Colors.black.withOpacity(0.8), // নিচের দিকে কালো ছায়া (দোকানের নামের জন্য)
                            ],
                            stops: const[0.0, 0.4, 1.0],
                          ),
                        ),
                      ),
                      
                      // দোকানের লোগো এবং নাম (ব্যানারের নিচে বসানো হয়েছে)
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

              // ==========================================
              // ২. Tab Bar (All Products)
              // ==========================================
              SliverToBoxAdapter(
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
                  margin: const EdgeInsets.only(bottom: 10),
                  child: const Text('ALL PRODUCTS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 14)),
                ),
              ),

              // ==========================================
              // ৩. Shop Products Grid
              // ==========================================
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

                  // Sorting logic
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: gridColumns, 
                        childAspectRatio: 0.70, 
                        crossAxisSpacing: 10, 
                        mainAxisSpacing: 10
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, index) {
                          var product = products[index];
                          Map<String, dynamic> data = product.data() as Map<String, dynamic>;
                          List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
                          String firstImage = images.isNotEmpty ? images[0] : '';
                          
                          String displayPrice = data.containsKey('discount_price') && data['discount_price'].toString().isNotEmpty ? data['discount_price'].toString() : data['price'].toString();
                          int curP = int.tryParse(displayPrice) ?? 0;
                          int origP = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
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
                                        Text(data['product_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis), 
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

// ==========================================
// কাস্টমার নোটিফিকেশন পেজ (Customer Inbox)
// ==========================================
class CustomerNotificationPage extends StatelessWidget {
  const CustomerNotificationPage({super.key});

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
        // অ্যাডমিনের পাঠানো নোটিফিকেশনগুলো ডাটাবেস থেকে আনা হচ্ছে
        stream: FirebaseFirestore.instance.collection('notifications')
            .orderBy('sent_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children:[
                  Icon(Icons.notifications_off_outlined, size: 80, color: Colors.grey.shade300),
                  const SizedBox(height: 15),
                  const Text('No new notifications', style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          var notifications = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              var doc = notifications[index];
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              
              // সময় বের করা
              String timeString = "Just now";
              if (data['sent_at'] != null) {
                DateTime date = (data['sent_at'] as Timestamp).toDate();
                timeString = "${date.day}/${date.month}/${date.year}";
              }

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(15),
                  leading: CircleAvatar(
                    backgroundColor: Colors.orange.shade100,
                    child: const Icon(Icons.campaign, color: Colors.deepOrange),
                  ),
                  title: Text(data['title'] ?? 'Notice', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 5),
                      Text(data['message'] ?? '', style: const TextStyle(color: Colors.black87)),
                      const SizedBox(height: 10),
                      Text(timeString, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
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
// অ্যাডমিন পেজ: Monthly Profit & Loss (P&L) ও Expense Tracker
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
  double platformCommissionRate = 0.10; // ১০% কমিশন

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

  // নতুন খরচ বা স্টাফের বেতন এন্ট্রি করার ফাংশন
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
                  value: selectedCategory,
                  decoration: const InputDecoration(labelText: 'Expense Category', border: OutlineInputBorder(), isDense: true),
                  items:['Staff Salary', 'Rider Payment', 'Server/API Cost', 'Marketing', 'Others']
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
                  decoration: const InputDecoration(labelText: 'Description (e.g. Rahim Salary Mar 2026)', border: OutlineInputBorder(), isDense: true),
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

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(title: const Text('Monthly P&L Report'), backgroundColor: Colors.teal, foregroundColor: Colors.white),
      body: StreamBuilder<QuerySnapshot>(
        // এই মাসের সমস্ত অর্ডার
        stream: FirebaseFirestore.instance.collection('orders').snapshots(),
        builder: (context, orderSnapshot) {
          return StreamBuilder<QuerySnapshot>(
            // এই মাসের সমস্ত খরচ
            stream: FirebaseFirestore.instance.collection('expenses').snapshots(),
            builder: (context, expenseSnapshot) {
              
              if (orderSnapshot.connectionState == ConnectionState.waiting || expenseSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              double totalIncome = 0; // অ্যাডমিনের কমিশন থেকে আয়
              double totalExpense = 0; // অ্যাডমিনের মোট খরচ

              // ১. আয় হিসাব করা (শুধু এই মাসের Delivered অর্ডার থেকে কমিশন)
              if (orderSnapshot.hasData) {
                for (var doc in orderSnapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data['status'] == 'Delivered' && data['order_date'] != null) {
                    DateTime orderDate = (data['order_date'] as Timestamp).toDate();
                    if (orderDate.month == now.month && orderDate.year == now.year) {
                      List<dynamic> items = data['items'] ??[];
                      for (var item in items) {
                        double price = double.tryParse(item['price'].toString()) ?? 0;
                        int qty = int.tryParse(item['quantity'].toString()) ?? 1;
                        // অ্যাডমিনের লাভ = প্রোডাক্টের দামের ওপর ১০% (বা আপনার সেট করা রেট)
                        totalIncome += (price * qty) * platformCommissionRate; 
                      }
                    }
                  }
                }
              }

              // ২. খরচ হিসাব করা (শুধু এই মাসের)
              List<QueryDocumentSnapshot> thisMonthExpenses =[];
              if (expenseSnapshot.hasData) {
                for (var doc in expenseSnapshot.data!.docs) {
                  var data = doc.data() as Map<String, dynamic>;
                  if (data['date'] != null) {
                    DateTime expDate = (data['date'] as Timestamp).toDate();
                    if (expDate.month == now.month && expDate.year == now.year) {
                      totalExpense += (data['amount'] as num).toDouble();
                      thisMonthExpenses.add(doc);
                    }
                  }
                }
              }

              double netProfit = totalIncome - totalExpense;

              return ListView(
                padding: const EdgeInsets.all(15),
                children:[
                  Text('Report for: ${now.month}/${now.year}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 15),

                  // Profit & Loss Cards
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
                  const SizedBox(height: 30),

                  // Expense List
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children:[
                      const Text('Expense & Salary History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                    const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('No expenses recorded this month.')))
                  else
                    ...thisMonthExpenses.map((doc) {
                      var data = doc.data() as Map<String, dynamic>;
                      DateTime dt = (data['date'] as Timestamp).toDate();
                      return Card(
                        child: ListTile(
                          leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.money_off, color: Colors.white)),
                          title: Text(data['description'], style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('${data['category']} • ${dt.day}/${dt.month}/${dt.year}', style: const TextStyle(fontSize: 12)),
                          trailing: Text('- ৳${data['amount']}', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                        ),
                      );
                    }).toList()
                ],
              );
            }
          );
        }
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