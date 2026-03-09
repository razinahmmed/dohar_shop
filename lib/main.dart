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
import 'package:url_launcher/url_launcher.dart'; // একদম উপরে বসান
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:async';
import 'package:geolocator/geolocator.dart';

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

  // এখন আর লগিন চেক করবে না, সরাসরি MainScreen এ ঢুকতে দেবে (Guest Mode)
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MainScreen(), 
  ));
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

  // কাস্টমার অ্যাপে নোটিফিকেশন রিসিভ করার সেটআপ
  void _setupPushNotifications() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    // ইউজারের কাছে পারমিশন চাওয়া
    await messaging.requestPermission(alert: true, badge: true, sound: true);

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
                    onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Placed Successfully!')));
                        Navigator.pop(context);
                    },
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
// ৩ নম্বর পেজ: Product Details (Fixed Variant Selection & Related Products)
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
  int _selectedImageIndex = 0; 
  bool _isDescExpanded = false; 
  
  Map<String, dynamic>? selectedColor;
  Map<String, dynamic>? selectedSize;

  // জাদুকরী Fly to Cart এনিমেশন ফাংশন
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

  void addToCart(BuildContext context, String imageUrl, int finalPrice, int maxStock, {bool isBuyNow = false}) async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please login to add items to your cart!')));
      return; 
    }

    Map<String, dynamic> data = widget.product.data() as Map<String, dynamic>;
    List<dynamic> colors = data.containsKey('colors') ? data['colors'] :[];
    List<dynamic> sizes = data.containsKey('sizes') ? data['sizes'] :[];

    if (colors.isNotEmpty && selectedColor == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে কালার সিলেক্ট করুন!'))); return; }
    if (sizes.isNotEmpty && selectedSize == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে সাইজ সিলেক্ট করুন!'))); return; }

    if (!isBuyNow) runAddToCartAnimation(imageUrl);

    var cartRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart');
    var existingItem = await cartRef
        .where('product_name', isEqualTo: widget.product['product_name'])
        .where('selected_color', isEqualTo: selectedColor != null ? selectedColor!['name'] : '')
        .where('selected_size', isEqualTo: selectedSize != null ? selectedSize!['name'] : '')
        .get();

    if (existingItem.docs.isNotEmpty) {
      await cartRef.doc(existingItem.docs.first.id).update({'quantity': FieldValue.increment(1)});
    } else {
      await cartRef.add({
        'product_name': widget.product['product_name'],
        'price': finalPrice, 
        'original_price': data['original_price'] ?? data['price'],
        'quantity': 1,
        'image_url': imageUrl,
        'selected_color': selectedColor != null ? selectedColor!['name'] : '',
        'selected_size': selectedSize != null ? selectedSize!['name'] : '',
        'max_stock': maxStock, 
        'seller_id': data.containsKey('seller_id') ? data['seller_id'] : 'unknown',
        'added_at': FieldValue.serverTimestamp(),
      });
    }
    if (!mounted) return;
    if (isBuyNow) { Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())); } 
    else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item added to Cart! 🚀'), duration: Duration(seconds: 1))); }
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

  @override
  void initState() {
    super.initState();
    _saveToRecentlyViewed(); 
  }

  // নিচে সিমিলার প্রোডাক্ট দেখানোর জন্য ছোট কার্ডের উইজেট
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
        // একই পেজে অন্য প্রোডাক্ট ওপেন হবে
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: doc)));
      },
      child: Container(
        width: isGrid ? null : 140,
        margin: isGrid ? null : const EdgeInsets.only(right: 10),
        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(8)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                children: [
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
    List<dynamic> colors = data.containsKey('colors') ? data['colors'] :[];
    List<dynamic> sizes = data.containsKey('sizes') ? data['sizes'] :[];
    String mainImage = images.isNotEmpty && images.length > _selectedImageIndex ? images[_selectedImageIndex] : '';
    
    int basePrice = int.tryParse(data['price'].toString()) ?? 0;
    int originalPrice = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int stock = int.tryParse(data['stock'].toString()) ?? 0;
    
    int extraColorPrice = selectedColor != null ? (selectedColor!['extra_price'] as num).toInt() : 0;
    int extraSizePrice = selectedSize != null ? (selectedSize!['extra_price'] as num).toInt() : 0;
    
    int finalCurrentPrice = basePrice + extraColorPrice + extraSizePrice;
    int finalOriginalPrice = originalPrice > 0 ? (originalPrice + extraColorPrice + extraSizePrice) : 0;

    int discountPercent = 0;
    if (finalOriginalPrice > finalCurrentPrice) {
      discountPercent = (((finalOriginalPrice - finalCurrentPrice) / finalOriginalPrice) * 100).round();
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100, 
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black, size: 20), onPressed: () => Navigator.pop(context)),
        actions:[
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseAuth.instance.currentUser != null ? FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('wishlist').doc(widget.product.id).snapshots() : const Stream<DocumentSnapshot>.empty(),
            builder: (context, snapshot) {
              bool isWished = snapshot.hasData && snapshot.data!.exists;
              return IconButton(
                icon: Icon(isWished ? Icons.favorite : Icons.favorite_border, color: isWished ? Colors.red : Colors.black),
                onPressed: () async {
                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  var ref = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wishlist').doc(widget.product.id);
                  if (isWished) { await ref.delete(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Wishlist 💔'))); } 
                  else { await ref.set(widget.product.data() as Map<String, dynamic>); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Wishlist ❤️'))); }
                },
              );
            },
          ),
          IconButton(icon: const Icon(Icons.share, color: Colors.black), onPressed: () {}), 
          IconButton(
            key: _cartKey, 
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage()))
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
                        Center(child: Container(key: _imageKey, height: 300, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: mainImage.isNotEmpty ? Image.network(mainImage, fit: BoxFit.contain) : const Icon(Icons.image, size: 100, color: Colors.grey))),
                        const SizedBox(height: 15),
                        if (images.length > 1) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: images.length, itemBuilder: (context, index) { bool isSelected = _selectedImageIndex == index; return InkWell(onTap: () => setState(() => _selectedImageIndex = index), child: Container(margin: const EdgeInsets.only(right: 10), height: 60, width: 60, decoration: BoxDecoration(border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 1.5), borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(images[index]), fit: BoxFit.cover)))); })),
                        const SizedBox(height: 20),
                        Text(data['product_name'] ?? 'Product Name', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 10),
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
                                Text('Stock: $stock', style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                                if (stock > 0 && stock < 10) Text('Hurry, almost sold out!', style: TextStyle(color: Colors.red.shade400, fontSize: 10, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10), 
                  
                  // ভেরিয়েন্ট সিলেকশন (কালার এবং সাইজ)
                  Container(
                    width: double.infinity, color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        if(colors.isNotEmpty) ...[
                          const Text('Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10), 
                          Wrap(spacing: 10, children: colors.map((c) {
                              // [FIXED]: অবজেক্ট কম্পেয়ার না করে নাম দিয়ে কম্পেয়ার করা হয়েছে যাতে বর্ডার ঠিকমত আসে
                              bool isSelected = selectedColor != null && selectedColor!['name'] == c['name'];
                              int extra = (c['extra_price'] as num).toInt();
                              return InkWell(
                                onTap: () => setState(() => selectedColor = isSelected ? null : c),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.deepOrange.shade50 : Colors.white, 
                                    border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 1.5), // বর্ডার ভিজিবল করা হয়েছে
                                    borderRadius: BorderRadius.circular(5)
                                  ), 
                                  child: Text(
                                    '${c['name']} ${extra > 0 ? '(+৳$extra)' : ''}', 
                                    style: TextStyle(color: isSelected ? Colors.deepOrange : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)
                                  )
                                )
                              );
                            }).toList()
                          ), 
                          const SizedBox(height: 20)
                        ],
                        if(sizes.isNotEmpty) ...[
                          const Text('Sizes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10), 
                          Wrap(spacing: 10, children: sizes.map((s) {
                              // [FIXED]: অবজেক্ট কম্পেয়ার না করে নাম দিয়ে কম্পেয়ার করা হয়েছে
                              bool isSelected = selectedSize != null && selectedSize!['name'] == s['name'];
                              int extra = (s['extra_price'] as num).toInt();
                              return InkWell(
                                onTap: () => setState(() => selectedSize = isSelected ? null : s),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                  decoration: BoxDecoration(
                                    color: isSelected ? Colors.teal.shade50 : Colors.white, 
                                    border: Border.all(color: isSelected ? Colors.teal : Colors.grey.shade300, width: 1.5), 
                                    borderRadius: BorderRadius.circular(5)
                                  ), 
                                  child: Text(
                                    '${s['name']} ${extra > 0 ? '(+৳$extra)' : ''}', 
                                    style: TextStyle(color: isSelected ? Colors.teal : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)
                                  )
                                )
                              );
                            }).toList()
                          ), 
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  
                  // শপ ডিটেলস
                  Container(
                    color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Row(
                      children:[
                        CircleAvatar(radius: 25, backgroundColor: Colors.teal.shade50, child: const Icon(Icons.storefront, color: Colors.teal, size: 28)), const SizedBox(width: 15),
                        Expanded(
                          child: FutureBuilder<DocumentSnapshot>(
                            future: FirebaseFirestore.instance.collection('users').doc(data['seller_id']).get(),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data!.exists) {
                                var shopData = snapshot.data!.data() as Map<String, dynamic>;
                                String shopName = shopData.containsKey('shop_name') && shopData['shop_name'].toString().isNotEmpty ? shopData['shop_name'] : shopData['name'];
                                return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(shopName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Row(children: const[Icon(Icons.verified, color: Colors.green, size: 14), SizedBox(width: 4), Text('Verified Shop', style: TextStyle(color: Colors.green, fontSize: 12))])]);
                              }
                              return const Text('Loading shop info...', style: TextStyle(color: Colors.grey));
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
                  
                  // প্রোডাক্ট ডেসক্রিপশন
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
                              Text(data.containsKey('description') && data['description'].toString().isNotEmpty ? data['description'] : 'No description available for this product.', style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5), maxLines: _isDescExpanded ? null : 4, overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis),
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
                  // NEW: More from this Shop
                  // =====================================
                  if (data['seller_id'] != null)
                    Container(
                      color: Colors.white, padding: const EdgeInsets.all(15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
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
                  // NEW: Similar Products
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
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: () => addToCart(context, mainImage, finalCurrentPrice, stock, isBuyNow: false), child: const Text('ADD TO CART', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 15),
                Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 15)), onPressed: () => addToCart(context, mainImage, finalCurrentPrice, stock, isBuyNow: true), child: const Text('BUY NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
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
                                height: 105, 
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
                              stream: FirebaseFirestore.instance.collection('products').orderBy('timestamp', descending: true).snapshots(),
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

  Widget _buildStaticCategory(String label, IconData icon, Color iconColor) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { setState(() { selectedCategoryFilter = isSelected ? '' : label; }); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.deepOrange, width: 2.5) : Border.all(color: Colors.transparent, width: 2.5)),
            child: CircleAvatar(radius: 26, backgroundColor: iconColor.withOpacity(0.15), child: Icon(icon, color: iconColor, size: 28))
          ), 
          const SizedBox(height: 5), 
          SizedBox(width: 60, child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis))
        ])
      ),
    );
  }

  Widget _buildDynamicCategory(String label, String imageUrl) {
    bool isSelected = selectedCategoryFilter == label;
    return InkWell(
      onTap: () { setState(() { selectedCategoryFilter = isSelected ? '' : label; }); },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8), 
        child: Column(children:[
          Container(
            decoration: BoxDecoration(shape: BoxShape.circle, border: isSelected ? Border.all(color: Colors.deepOrange, width: 2.5) : Border.all(color: Colors.transparent, width: 2.5)),
            child: CircleAvatar(radius: 26, backgroundColor: Colors.grey.shade100, backgroundImage: NetworkImage(imageUrl))
          ), 
          const SizedBox(height: 5), 
          SizedBox(width: 60, child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: isSelected ? Colors.deepOrange : Colors.black), maxLines: 2, overflow: TextOverflow.ellipsis))
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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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
// লগিন পেজ (Login Page)
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

      if (role == 'admin') {
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
// সেলার ড্যাশবোর্ড: রিয়েল ডাটা (Dynamic)
// ==========================================
class SellerDashboard extends StatelessWidget {
  const SellerDashboard({super.key});
  
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
            // ফায়ারবেস থেকে সেলারের রিয়েল ডাটা আনা হচ্ছে
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
                        Text('Seller ID: #${currentUser.uid.substring(0, 6).toUpperCase()}', style: const TextStyle(color: Colors.grey)) // রিয়েল আইডি
                      ]
                    )
                  ]
                );
              }
            ),
            const SizedBox(height: 25),
            const Text('Overall Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(children:[_buildStatCard("Today's Sales", "৳০", Colors.teal[50]!, Colors.teal), const SizedBox(width: 15), _buildStatCard("Active Orders", "০", Colors.orange[50]!, Colors.orange)]),
            const SizedBox(height: 25),
            
            const Text('QUICK ACTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
            Row(
              children:[
                _buildQuickAction(Icons.add_circle_outline, "Add Product", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage()))), 
                const SizedBox(width: 15), 
                _buildQuickAction(Icons.shopping_cart, "Go to Shopping", Colors.deepOrange, () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()))) // সেলার শপিং করতে পারবে
              ]
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {return Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)), child: Column(children:[Text(title, style: const TextStyle(fontSize: 14)), const SizedBox(height: 5), Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor))]))); }
  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {return Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))), child: Column(children:[Icon(icon, color: color, size: 30), const SizedBox(height: 5), Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color))]))));}
}

// ==========================================
// সেলার প্রোডাক্ট ম্যানেজমেন্ট: রিয়েল ডাটা (Index Fixed)
// ==========================================
class ProductManagement extends StatelessWidget {
  const ProductManagement({super.key});
  
  @override 
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber[200], elevation: 0, title: const Text('PRODUCT MANAGEMENT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: Column(
        children:[
          Padding(padding: const EdgeInsets.all(15.0), child: TextField(decoration: InputDecoration(hintText: 'Search for products...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
          
          Expanded(
            child: StreamBuilder(
              // [FIXED] .orderBy বাদ দেওয়া হয়েছে যাতে Index Error না আসে
              stream: FirebaseFirestore.instance.collection('products')
                  .where('seller_id', isEqualTo: currentUser?.uid)
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                }
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('You have not uploaded any products yet.'));
                }

                // ডাটাবেস এর বদলে অ্যাপের ভেতরেই লেটেস্ট প্রোডাক্ট আগে দেখানোর জন্য Sort করা হচ্ছে
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

                    return Card(
                      margin: const EdgeInsets.only(bottom: 15), 
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                      child: ListTile(
                        leading: Container(
                          width: 60, height: 60, 
                          decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), 
                          child: firstImage.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)
                        ), 
                        title: Text(data['product_name'] ?? 'Product Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis), 
                        subtitle: Text('Price: ৳${data['price']}\nStock: ${data['stock']} | Status: ${status.toUpperCase()}', style: TextStyle(fontSize: 12, color: status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange))), 
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            doc.reference.delete();
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Deleted!')));
                          },
                        )
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
// সেলার অর্ডার ম্যানেজমেন্ট 
// ==========================================
class SellerOrderManagement extends StatelessWidget {
  const SellerOrderManagement({super.key});
  @override Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(backgroundColor: Colors.amber[200], title: const Text('ORDER MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), bottom: const TabBar(isScrollable: true, labelColor: Colors.black, indicatorColor: Colors.deepOrange, tabs:[Tab(text: 'All Orders'), Tab(text: 'Pending'), Tab(text: 'Shipped'), Tab(text: 'Delivered')])),
        body: ListView.builder(padding: const EdgeInsets.all(15), itemCount: 4, itemBuilder: (context, index) {return Container(margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey[200]!)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Order ID: 210977', style: TextStyle(fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(10)), child: const Text('Pending', style: TextStyle(fontSize: 12, color: Colors.orange)))]), const Text('Customer: Jane Doe', style: TextStyle(color: Colors.grey)), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Total Value: ৳৩,২০০'), ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), child: const Text('Update Status', style: TextStyle(color: Colors.white)))])]));}),
      ),
    );
  }
}

// ==========================================
// সেলার পেমেন্ট ও রিপোর্টস 
// ==========================================
class PaymentsReports extends StatelessWidget {
  const PaymentsReports({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber[200], title: const Text('PAYMENTS & REPORTS', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(padding: const EdgeInsets.all(15), child: Column(children: [Row(children:[_buildBalanceCard("Available Balance", "৳২৫,০০০"), const SizedBox(width: 15), _buildBalanceCard("Pending Payout", "৳৮,৫০০")]), const SizedBox(height: 25), const Text('Sales Report', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 15), Container(height: 200, width: double.infinity, color: Colors.grey[100], child: const Center(child: Text('Chart Placeholder'))), const SizedBox(height: 25), ListTile(tileColor: Colors.white, leading: const Icon(Icons.account_balance), title: const Text('Link a Bank Account'), trailing: const Icon(Icons.arrow_forward_ios, size: 15)), const SizedBox(height: 10), ListTile(tileColor: Colors.white, leading: const Icon(Icons.account_balance_wallet, color: Colors.pink), title: const Text('Add bKash'), trailing: const Icon(Icons.arrow_forward_ios, size: 15))])),
    );
  }
  Widget _buildBalanceCard(String title, String amount) {return Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(15)), child: Column(children:[Text(title, style: const TextStyle(fontSize: 12)), Text(amount, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))); }
}

// ==========================================
// সেলার প্রোফাইল (Profile Picture Upload + Switch Modes)
// ==========================================
class SellerProfile extends StatefulWidget {
  const SellerProfile({super.key});

  @override
  State<SellerProfile> createState() => _SellerProfileState();
}

class _SellerProfileState extends State<SellerProfile> {
  final ImagePicker _picker = ImagePicker();

  // ছবি আপলোডের ফাংশন
  Future<void> _uploadSellerProfilePicture() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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
      
      // ফায়ারবেসে সেভ করা হচ্ছে
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'profile_image_url': downloadUrl});

      // লোকাল ক্যাশে আপডেট রাখা
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('profile_image', downloadUrl);

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দোকানের লোগো সফলভাবে আপডেট হয়েছে! 🎉')));
      // StreamBuilder অটোমেটিক ছবি আপডেট করে নিবে
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
      // FutureBuilder এর বদলে StreamBuilder দেওয়া হয়েছে যাতে ছবি আপলোড করলেই সাথে সাথে চেঞ্জ হয়
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
                    // ==============================
                    // ক্লিকেবল প্রোফাইল ছবি
                    // ==============================
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
                    // কাস্টমাররা দোকান কেমন দেখছে সেটা দেখার বাটন
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
                    // সাধারণ কাস্টমার হিসেবে কেনাকাটা করার বাটন
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
                    
                    _buildProfileItem(Icons.settings, "Shop Settings"), 
                    _buildProfileItem(Icons.account_balance, "Bank / Payment Info"), 
                    const SizedBox(height: 30), 
                    
                    TextButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.red),
                      onPressed: () async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.clear();
                        await FirebaseAuth.instance.signOut(); 
                        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
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
  Widget _buildProfileItem(IconData icon, String title) {return ListTile(leading: Icon(icon, color: Colors.grey.shade700), title: Text(title), trailing: const Icon(Icons.arrow_forward_ios, size: 15));}
}

// ==========================================
// সেলার Add Product পেজ (Variant Pricing সহ)
// ==========================================
class AddProductPage extends StatefulWidget { const AddProductPage({super.key}); @override State<AddProductPage> createState() => _AddProductPageState(); }
class _AddProductPageState extends State<AddProductPage> {
  final nameController = TextEditingController(); final priceController = TextEditingController(); final originalPriceController = TextEditingController(); final stockController = TextEditingController(); final descController = TextEditingController(); 
  final tagInput = TextEditingController(); 
  
  // ভেরিয়েন্ট কন্ট্রোলার
  final colorNameInput = TextEditingController(); final colorPriceInput = TextEditingController();
  final sizeNameInput = TextEditingController(); final sizePriceInput = TextEditingController();

  String? selectedCategory; List<XFile> selectedImages =[]; String? selectedFileName; 
  // এখন লিস্টগুলো Map আকারে সেভ হবে (নাম এবং দাম)
  List<Map<String, dynamic>> colors = []; 
  List<Map<String, dynamic>> sizes =[]; 
  List<String> searchTags =[]; 
  final ImagePicker _picker = ImagePicker();

  Future<void> pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) setState(() => selectedImages.addAll(images));
  }

  void uploadProduct() async {
    if (nameController.text.isEmpty || priceController.text.isEmpty || selectedCategory == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill Name, Price and Category!'))); return; }
    if (tagInput.text.trim().isNotEmpty) { var tags = tagInput.text.split(','); for (var t in tags) { if (t.trim().isNotEmpty) searchTags.add(t.trim()); } tagInput.clear(); }
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      List<String> imageUrls =[];
      for (var image in selectedImages) {
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child('product_images').child(fileName);
        if (kIsWeb) { Uint8List bytes = await image.readAsBytes(); await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')); } 
        else { await ref.putFile(File(image.path)); }
        imageUrls.add(await ref.getDownloadURL());
      }

      List<String> finalTags = searchTags.map((e) => e.toLowerCase()).toList();
      finalTags.add(nameController.text.trim().toLowerCase());

      await FirebaseFirestore.instance.collection('products').add({
        'product_name': nameController.text.trim(), 'price': priceController.text.trim(), 'original_price': originalPriceController.text.trim(), 'stock': stockController.text.trim(),
        'category': selectedCategory, 'description': descController.text.trim(),
        'colors': colors, 'sizes': sizes, // Map ডাটা সেভ হচ্ছে
        'search_tags': finalTags, 'image_urls': imageUrls, 'pdf_catalog': selectedFileName ?? "", 'seller_id': FirebaseAuth.instance.currentUser?.uid, 'timestamp': FieldValue.serverTimestamp(), 'status': 'pending',
      });

      if (!mounted) return;
      Navigator.pop(context); Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Uploaded Successfully! 🎉')));
    } catch (e) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }

  // নতুন অ্যাডভান্সড ভেরিয়েন্ট ইনপুট (নাম এবং দাম)
  Widget _buildAdvancedVariantInput(String title, TextEditingController nameCtrl, TextEditingController priceCtrl, List<Map<String, dynamic>> list) {
    void addItems() {
      if (nameCtrl.text.trim().isNotEmpty) {
        setState(() { 
          list.add({
            'name': nameCtrl.text.trim(), 
            'extra_price': priceCtrl.text.trim().isEmpty ? 0 : int.parse(priceCtrl.text.trim())
          }); 
          nameCtrl.clear(); priceCtrl.clear(); 
        });
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      Row(children:[
        Expanded(flex: 2, child: TextField(controller: nameCtrl, onSubmitted: (_) => addItems(), decoration: const InputDecoration(hintText: 'Name (e.g. XL)', contentPadding: EdgeInsets.all(10)))),
        const SizedBox(width: 10),
        Expanded(flex: 1, child: TextField(controller: priceCtrl, keyboardType: TextInputType.number, onSubmitted: (_) => addItems(), decoration: const InputDecoration(hintText: '+ Extra ৳', contentPadding: EdgeInsets.all(10)))),
        IconButton(icon: const Icon(Icons.add_circle, color: Colors.teal, size: 30), onPressed: addItems)
      ]),
      const SizedBox(height: 5),
      Wrap(spacing: 8, children: list.map((item) => Chip(label: Text('${item['name']} ${item['extra_price'] > 0 ? '(+৳${item['extra_price']})' : ''}'), onDeleted: () => setState(() => list.remove(item)))).toList())
    ]);
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
          Row(children:[Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Sale Price (৳)', border: OutlineInputBorder()))), const SizedBox(width: 10), Expanded(child: TextField(controller: originalPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Original Price (৳)', border: OutlineInputBorder()))), const SizedBox(width: 10), Expanded(child: TextField(controller: stockController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock Qty', border: OutlineInputBorder())))]),
          const SizedBox(height: 25), 
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[TextField(controller: tagInput, decoration: InputDecoration(hintText: 'Paste Tags (Comma separated)', suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Colors.teal), onPressed: () { if (tagInput.text.trim().isNotEmpty) { setState(() { var t = tagInput.text.split(','); for(var x in t){if(x.trim().isNotEmpty) searchTags.add(x.trim());} tagInput.clear(); }); } }))), Wrap(spacing: 8, children: searchTags.map((item) => Chip(label: Text(item), onDeleted: () => setState(() => searchTags.remove(item)))).toList())])),
          const SizedBox(height: 25), 
          _buildAdvancedVariantInput('Add Colors', colorNameInput, colorPriceInput, colors), const SizedBox(height: 15), 
          _buildAdvancedVariantInput('Add Sizes', sizeNameInput, sizePriceInput, sizes),
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
// অ্যাডমিন প্রোডাক্ট এপ্রুভাল পেজ (বিস্তারিত তথ্য সহ)
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
              List<dynamic> colors = data.containsKey('colors') ? data['colors'] :[];
              List<dynamic> sizes = data.containsKey('sizes') ? data['sizes'] :[];
              List<dynamic> tags = data.containsKey('search_tags') ? data['search_tags'] :[];
              
              String firstImage = images.isNotEmpty ? images[0] : '';
              bool isFlash = flashSaleStates[doc.id] ?? false;

              return Card(
                margin: const EdgeInsets.all(10), elevation: 3,
                child: ExpansionTile(
                  leading: Container(
                    width: 50, height: 50,
                    decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                    child: firstImage.isNotEmpty 
                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover))
                        : const Icon(Icons.image, color: Colors.grey),
                  ),
                  title: Text(data['product_name'] ?? 'No Name', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('Sale Price: ৳${data['price']} | Stock: ${data['stock']}'),
                  children:[
                    Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          // সব ছবি দেখানো
                          if(images.isNotEmpty) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: images.length, itemBuilder: (context, i) => Container(margin: const EdgeInsets.only(right: 10), width: 60, decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), image: DecorationImage(image: NetworkImage(images[i]), fit: BoxFit.cover))))),
                          const Divider(),
                          Text('Category: ${data['category']}'),
                          Text('Original Price: ৳${data['original_price'] ?? 'N/A'}'),
                          const SizedBox(height: 10),
                          if(colors.isNotEmpty) Text('Colors: ${colors.map((c) => c['name']).join(", ")}'),
                          if(sizes.isNotEmpty) Text('Sizes: ${sizes.map((s) => s['name']).join(", ")}'),
                          if(tags.isNotEmpty) Text('Tags: ${tags.join(", ")}', style: const TextStyle(color: Colors.blue)),
                          const SizedBox(height: 10),
                          const Text('Description:', style: TextStyle(fontWeight: FontWeight.bold)),
                          Text(data['description'] ?? 'No description'),
                          const Divider(),
                          // একশনের অংশ (এপ্রুভ/রিজেক্ট)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children:[const Text('Flash Sale?'), Switch(value: isFlash, activeColor: Colors.teal, onChanged: (v) => setState(() => flashSaleStates[doc.id] = v))]),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                                onPressed: () {
                                  doc.reference.update({'status': 'approved', 'is_flash_sale': isFlash, 'reject_reason': ""});
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product Approved!')));
                                },
                                child: const Text('APPROVE', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children:[
                              Expanded(child: TextField(controller: rejectController, decoration: const InputDecoration(hintText: 'রিজেক্টের কারণ...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)))),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                onPressed: () {
                                  if(rejectController.text.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('দয়া করে কারণ লিখুন!'))); return; }
                                  doc.reference.update({'status': 'rejected', 'reject_reason': rejectController.text.trim()});
                                  rejectController.clear();
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
// অ্যাডমিন পেজ ৩: Order & Delivery Control (Smart Logistics System)
// ==========================================
class AdminOrderControl extends StatefulWidget {
  const AdminOrderControl({super.key});

  @override
  State<AdminOrderControl> createState() => _AdminOrderControlState();
}

class _AdminOrderControlState extends State<AdminOrderControl> {
  // ডেলিভারি অ্যাসাইন করার জন্য স্মার্ট পপ-আপ (নিজস্ব রাইডার বা কুরিয়ার)
  void _showAssignDeliveryModal(String orderId) {
    String deliveryMethod = 'rider'; // ডিফল্ট: নিজস্ব রাইডার
    String? selectedRiderId;
    TextEditingController courierNameCtrl = TextEditingController();
    TextEditingController trackingIdCtrl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  const Text('Assign Delivery', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  
                  // ডেলিভারি মেথড নির্বাচন
                  Row(
                    children:[
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Own Rider', style: TextStyle(fontSize: 14)),
                          value: 'rider', groupValue: deliveryMethod,
                          activeColor: Colors.deepOrange,
                          onChanged: (val) => setModalState(() => deliveryMethod = val!),
                        )
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Courier Service', style: TextStyle(fontSize: 14)),
                          value: 'courier', groupValue: deliveryMethod,
                          activeColor: Colors.deepOrange,
                          onChanged: (val) => setModalState(() => deliveryMethod = val!),
                        )
                      ),
                    ]
                  ),
                  const Divider(),

                  // অপশন ১: নিজস্ব রাইডার নির্বাচন
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
                              isExpanded: true,
                              hint: const Padding(padding: EdgeInsets.all(10.0), child: Text('Choose a rider')),
                              value: selectedRiderId,
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
                  // অপশন ২: কুরিয়ার সার্ভিস
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
                        // ভ্যালিডেশন
                        if (deliveryMethod == 'rider' && selectedRiderId == null) return;
                        if (deliveryMethod == 'courier' && (courierNameCtrl.text.isEmpty || trackingIdCtrl.text.isEmpty)) return;

                        // ফায়ারবেসে অর্ডার আপডেট করা হচ্ছে
                        Map<String, dynamic> updateData = {
                          'status': 'Dispatched',
                          'delivery_type': deliveryMethod,
                          'dispatched_at': FieldValue.serverTimestamp(),
                        };

                        if (deliveryMethod == 'rider') {
                          updateData['assigned_rider_id'] = selectedRiderId;
                        } else {
                          updateData['courier_name'] = courierNameCtrl.text.trim();
                          updateData['tracking_id'] = trackingIdCtrl.text.trim();
                        }

                        await FirebaseFirestore.instance.collection('orders').doc(orderId).update(updateData);
                        
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
            isScrollable: true,
            labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
            tabs:[
              Tab(text: 'New Pending'), 
              Tab(text: 'Processing (Need Delivery)'), 
              Tab(text: 'Dispatched (On Way)'), 
              Tab(text: 'Resolved / Done')
            ]
          ),
        ),
        body: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('orders').orderBy('order_date', descending: true).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('কোনো অর্ডার নেই।'));

            var allOrders = snapshot.data!.docs;
            
            // ট্যাব অনুযায়ী অর্ডার ফিল্টার করা
            var pendingOrders = allOrders.where((doc) => doc['status'] == 'Pending').toList();
            var processingOrders = allOrders.where((doc) => doc['status'] == 'Processing').toList();
            var dispatchedOrders = allOrders.where((doc) => doc['status'] == 'Dispatched').toList();
            var doneOrders = allOrders.where((doc) => doc['status'] == 'Delivered' || doc['status'] == 'Cancelled').toList();

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

  // অর্ডার লিস্ট দেখানোর মূল উইজেট
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
              // হেডার
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children:[
                  Text('ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)), 
                  Text('৳${data['total_amount']}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange, fontSize: 16))
                ]
              ),
              const Divider(height: 20),
              
              // বডি (কাস্টমার ও আইটেম ইনফো)
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
                        
                        // যদি রাইডার বা কুরিয়ারে দেওয়া থাকে
                        if (data.containsKey('delivery_type')) ...[
                           const SizedBox(height: 5),
                           Text(
                             data['delivery_type'] == 'rider' ? 'Assigned: Internal Rider' : 'Courier: ${data['courier_name']} (Trk: ${data['tracking_id']})', 
                             style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.bold)
                           )
                        ]
                      ]
                    )
                  ),
                ],
              ),
              const SizedBox(height: 15),
              
              // ডাইনামিক অ্যাকশন বাটন (স্ট্যাটাসের ওপর ভিত্তি করে)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children:[
                  Text('Status: $status', style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  _buildActionButton(doc.id, status),
                ],
              )
            ],
          ),
        );
      }
    );
  }

  // স্ট্যাটাস অনুযায়ী বাটন লজিক
  Widget _buildActionButton(String orderId, String status) {
    if (status == 'Pending') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), 
        onPressed: () => FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Processing'}),
        child: const Text('Confirm Order', style: TextStyle(color: Colors.white))
      );
    } 
    else if (status == 'Processing') {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange), 
        onPressed: () => _showAssignDeliveryModal(orderId),
        icon: const Icon(Icons.local_shipping, color: Colors.white, size: 18),
        label: const Text('Assign Delivery', style: TextStyle(color: Colors.white))
      );
    }
    else if (status == 'Dispatched') {
      return ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), 
        onPressed: () => FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Delivered'}),
        child: const Text('Mark as Delivered', style: TextStyle(color: Colors.white))
      );
    }
    else {
      return OutlinedButton(onPressed: (){}, child: const Text('View Details'));
    }
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
                    children:[
                      const Text('Total Successful Revenue', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)), 
                      const SizedBox(height: 5),
                      Text('৳${totalDeliveredRevenue.toStringAsFixed(0)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)),
                      const Text('From all delivered orders', style: TextStyle(fontSize: 12, color: Colors.black54)), 
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
// অ্যাডমিন পেজ ৫: System Settings & Admin (Functional Setup)
// ==========================================
class AdminSettings extends StatefulWidget {
  const AdminSettings({super.key});

  @override
  State<AdminSettings> createState() => _AdminSettingsState();
}

class _AdminSettingsState extends State<AdminSettings> {
  final ImagePicker _picker = ImagePicker();

  // অ্যাডমিন প্রোফাইল ছবি আপলোড করার ফাংশন
  Future<void> _uploadAdminProfilePicture() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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
      
      // ফায়ারবেসে সেভ
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).update({'profile_image_url': downloadUrl});

      if (!mounted) return;
      Navigator.pop(context); 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Admin profile picture updated! 🎉')));
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // অ্যাপ কনফিগ (Platform Commission) আপডেট করার পপ-আপ
  void _showAppConfigDialog() {
    TextEditingController commissionCtrl = TextEditingController();
    
    // ফায়ারবেস থেকে আগের কমিশন ডাটা নিয়ে আসা
    FirebaseFirestore.instance.collection('app_config').doc('finance_settings').get().then((doc) {
      if (doc.exists) {
        commissionCtrl.text = (doc['platform_commission'] ?? 10).toString();
      }
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
            TextField(
              controller: commissionCtrl, 
              keyboardType: TextInputType.number, 
              decoration: const InputDecoration(hintText: 'e.g. 10', border: OutlineInputBorder(), isDense: true)
            ),
            const SizedBox(height: 10),
            const Text('*This % will be deducted from seller payouts.', style: TextStyle(fontSize: 10, color: Colors.deepOrange)),
          ],
        ),
        actions:[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('app_config').doc('finance_settings').set({
                'platform_commission': double.tryParse(commissionCtrl.text) ?? 10.0,
              }, SetOptions(merge: true));
              if(mounted) Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Commission Rate Updated Successfully!')));
            }, 
            child: const Text('Save', style: TextStyle(color: Colors.white))
          )
        ],
      )
    );
  }

  // রোল ম্যানেজমেন্ট পপ-আপ (যেকোনো ইউজারকে অ্যাডমিন/সেলার বানানোর অপশন)
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
                TextField(
                  controller: emailCtrl, 
                  decoration: const InputDecoration(labelText: 'User Email Address', border: OutlineInputBorder(), isDense: true)
                ),
                const SizedBox(height: 15),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Assign New Role', border: OutlineInputBorder(), isDense: true),
                  items: ['admin', 'seller', 'rider', 'customer'].map((r) => DropdownMenuItem(value: r, child: Text(r.toUpperCase()))).toList(),
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
                  
                  // ইমেইল দিয়ে ইউজার খোঁজা
                  var snap = await FirebaseFirestore.instance.collection('users').where('email', isEqualTo: emailCtrl.text.trim()).get();
                  if(snap.docs.isNotEmpty) {
                    await snap.docs.first.reference.update({'role': selectedRole});
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
            // অ্যাডমিন প্রোফাইল হেডার (StreamBuilder দিয়ে রিয়েল-টাইম ছবি চেঞ্জ হবে)
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('users').doc(currentUser?.uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const SizedBox(height: 150, child: Center(child: CircularProgressIndicator()));
                
                var data = snapshot.hasData && snapshot.data!.exists ? snapshot.data!.data() as Map<String, dynamic> : {};
                String name = data['name'] ?? 'Chief Admin';
                String img = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';

                return Container(
                  width: double.infinity, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white), 
                  child: Column(
                    children: [
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
                      const Text('Chief Admin', style: TextStyle(color: Colors.grey))
                    ]
                  )
                );
              }
            ),
            
            // মেনু অপশনগুলো
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  const Text('Control Center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  
                  _buildSettingItem(Icons.store, 'Store Details', onTap: () {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Store info setup is coming soon!')));
                  }),
                  
                  _buildSettingItem(Icons.settings_applications, 'App Config', onTap: _showAppConfigDialog),
                  
                  _buildSettingItem(Icons.people, 'Staff Accounts', trailingText: 'Manage', onTap: () {
                     // আগে তৈরি করা AdminUserStatusPage ব্যবহার করা হলো
                     Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminUserStatusPage(role: 'admin', title: 'Staff & Admins')));
                  }),
                  
                  _buildSettingItem(Icons.admin_panel_settings, 'Role Management', onTap: _showRoleManagementDialog),
                  
                  _buildSettingItem(Icons.cloud_download, 'Data Backup', onTap: () {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulating Database Backup... Done! ✅')));
                  }),
                  
                  _buildSettingItem(Icons.security, 'Security Log', onTap: () {
                     ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No security breaches detected. System is safe.')));
                  }),
                  
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
        ),
      ),
    );
  }

  // হেল্পার উইজেট
  Widget _buildSettingItem(IconData icon, String title, {String? trailingText, VoidCallback? onTap}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon, color: Colors.grey[700]),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        trailing: trailingText != null 
          ? Text(trailingText, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)) 
          : const Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey),
        onTap: onTap,
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
// রাইডার পেজ ১: Dashboard
// ==========================================
class RiderDashboard extends StatelessWidget {
  const RiderDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(backgroundColor: Colors.deepOrange, title: const Text('D Shop RIDER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), leading: const Icon(Icons.menu, color: Colors.white), actions:[IconButton(icon: const Icon(Icons.notifications_active, color: Colors.white), onPressed: () {})]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Row(children:[
              const CircleAvatar(radius: 35, backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white, size: 40)), const SizedBox(width: 15),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children:[const Text('Rahim Ahmed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(10)), child: Row(children: const[Icon(Icons.verified, size: 14, color: Colors.green), SizedBox(width: 4), Text('Verified Rider', style: TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold))]))])
            ]),
            const SizedBox(height: 20),
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[const Text('Today\'s Earnings', style: TextStyle(fontSize: 16)), const Text('৳৪,৫০০', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black87)), const SizedBox(height: 15), Row(children:[Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.teal[50], borderRadius: BorderRadius.circular(10)), child: Column(children: const[Text('Deliveries Completed', style: TextStyle(fontSize: 10, color: Colors.teal)), Text('12', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal))]))), const SizedBox(width: 10), Expanded(child: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber[50], borderRadius: BorderRadius.circular(10)), child: Column(children: const[Text('Overall Rating', style: TextStyle(fontSize: 10, color: Colors.orange)), Text('4.8/5', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange))])))]),])),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Active Tasks', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Icon(Icons.arrow_forward_ios, size: 15, color: Colors.grey)]),
            const SizedBox(height: 10),
            _buildActiveTaskItem("Pick-up", "Cotton T-Shirt", "Jane Doe", Colors.amber),
            _buildActiveTaskItem("Drop-off", "Smart Watch", "Jane Doe", Colors.redAccent),
            const SizedBox(height: 20),
            const Text('QUICK ACTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
            Row(children:[Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.power_settings_new, color: Colors.white), label: const Text('Go Offline', style: TextStyle(color: Colors.white)), onPressed: (){})), const SizedBox(width: 15), Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, padding: const EdgeInsets.symmetric(vertical: 12)), icon: const Icon(Icons.analytics, color: Colors.white), label: const Text('Analytics', style: TextStyle(color: Colors.white)), onPressed: (){}))])
          ],
        ),
      ),
    );
  }

  Widget _buildActiveTaskItem(String type, String item, String name, Color color) {
    return Container(margin: const EdgeInsets.only(bottom: 10), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: ListTile(leading: Icon(type == 'Pick-up' ? Icons.shopping_bag : Icons.location_on, color: color), title: Text('$type: $item', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), subtitle: Text('Drop-off: $name', style: const TextStyle(fontSize: 12)), trailing: const Icon(Icons.arrow_forward_ios, size: 12)));
  }
}

// ==========================================
// রাইডার পেজ ২: Task Management
// ==========================================
class RiderTaskManagement extends StatelessWidget {
  const RiderTaskManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.amber[100], elevation: 0,
          title: const Text('TASK MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black),
          bottom: const TabBar(isScrollable: true, labelColor: Colors.black, indicatorColor: Colors.deepOrange, tabs:[Tab(text: 'All Tasks'), Tab(text: 'Pending'), Tab(text: 'In-Transit'), Tab(text: 'Delivered')]),
        ),
        body: ListView(
          padding: const EdgeInsets.all(15),
          children:[
            _buildTaskCard("21309", "Pick-up", "21 Customer, Uttara, Dhaka", "Assigned", Colors.teal),
            _buildTaskCard("21307", "Drop-off", "71 Raman Sarhiar, H-12, Uttara, Dhaka", "Pending Acceptance", Colors.orange),
            _buildTaskCard("21337", "Drop-off", "71 Raman Sarhiar, H-12, Uttara, Dhaka", "In-Transit", Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _buildTaskCard(String id, String type, String address, String status, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          Text('Task ID: $id', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('Type: $type', style: const TextStyle(color: Colors.grey)),
          Text('Address: $address', style: const TextStyle(color: Colors.grey)),
          Row(children:[const Text('Status: ', style: TextStyle(color: Colors.grey)), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(5)), child: Text(status, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)))]),
          const SizedBox(height: 15),
          SizedBox(width: double.infinity, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: (){}, child: const Text('Complete Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
        ],
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ৩: Order Details & Navigation
// ==========================================
class RiderOrderDetails extends StatelessWidget {
  const RiderOrderDetails({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber[100], elevation: 0, title: const Text('ORDER DETAILS & NAV', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black), actions: const[Icon(Icons.filter_alt_outlined, color: Colors.deepOrange), SizedBox(width: 15)]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            const Text('Current Task: In-Transit', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('(Order ID: ২১১৩৭)', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 15),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Row(children: const[Text('Customer: ', style: TextStyle(fontWeight: FontWeight.bold)), Text('Jane Doe')]), Row(children: const[Text('Phone: ', style: TextStyle(fontWeight: FontWeight.bold)), Text('01-524-2330')]), Row(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Address: ', style: TextStyle(fontWeight: FontWeight.bold)), Expanded(child: Text('Address (mapped), H-12, Rs.10.1, Sec-7, Uttara, Dhaka'))]), const SizedBox(height: 15), SizedBox(width: double.infinity, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), icon: const Icon(Icons.navigation, color: Colors.white), label: const Text('Navigate', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), onPressed: (){}))])),
            const SizedBox(height: 20),
            const Text('Order Content', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
            _buildOrderContentItem('KY২৬৬০০', '৳২,৮০০', Icons.headphones),
            _buildOrderContentItem('SMART WATCH', '৳২,৮০০', Icons.watch),
            const SizedBox(height: 20),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), child: Row(children: const[Text('In-Transit'), Icon(Icons.arrow_drop_down)]))]),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), icon: const Icon(Icons.call, color: Colors.white), label: const Text('Call Customer', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)), onPressed: (){}))
          ],
        ),
      ),
    );
  }
  Widget _buildOrderContentItem(String title, String price, IconData icon) {
    return Card(margin: const EdgeInsets.only(bottom: 10), child: ListTile(leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: Icon(icon)), title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(price, style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))));
  }
}

// ==========================================
// রাইডার পেজ ৪: Delivery & Earnings (Settle)
// ==========================================
class RiderDeliveryEarnings extends StatelessWidget {
  const RiderDeliveryEarnings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.amber[50],
      appBar: AppBar(backgroundColor: Colors.amber[100], elevation: 0, title: const Text('DELIVERY & EARNINGS', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            const Text('Complete Delivery', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), const SizedBox(height: 15),
            Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[const Text('Delivery Summary', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const Divider(), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Order ID'), Text('21307', style: TextStyle(fontWeight: FontWeight.bold))]), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Taka'), Text('৳৩,২০০', style: TextStyle(fontWeight: FontWeight.bold))]), Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Customer'), Text('Jane Doe', style: TextStyle(fontWeight: FontWeight.bold))])])),
            const SizedBox(height: 20),
            const Text('Cash Collection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
            Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(children:[RadioListTile(value: 1, groupValue: 2, onChanged: (v){}, title: Row(children: const[Icon(Icons.account_balance_wallet, color: Colors.pink), SizedBox(width: 10), Text('bKash/Nagad')])), const Divider(height: 1), RadioListTile(value: 2, groupValue: 2, activeColor: Colors.teal, onChanged: (v){}, title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Row(children:[Icon(Icons.money, color: Colors.teal), SizedBox(width: 10), Text('Cash')]), Text('৳৩,২০০', style: TextStyle(fontWeight: FontWeight.bold))]))])),
            const SizedBox(height: 20),
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(children:[const Text('Signature', style: TextStyle(fontFamily: 'cursive', fontSize: 32, color: Colors.black54)), const Divider(), const Text('Digital Signature pad', style: TextStyle(color: Colors.grey)), const SizedBox(height: 10), OutlinedButton.icon(onPressed: (){}, icon: const Icon(Icons.camera_alt), label: const Text('Attach Photo (optional)'))])),
            const SizedBox(height: 20),
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: (){}, child: const Text('Mark as Delivered', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))
          ],
        ),
      ),
    );
  }
}

// ==========================================
// রাইডার পেজ ৫: Profile
// ==========================================
class RiderProfile extends StatelessWidget {
  const RiderProfile({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.orange[100], elevation: 0, leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: Column(
        children:[
          Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.orange[100], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))), child: Column(children:[const CircleAvatar(radius: 40, backgroundColor: Colors.teal, child: Icon(Icons.person, color: Colors.white, size: 40)), const SizedBox(height: 10), const Text('Rahim Ahmed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), Row(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.verified, color: Colors.green, size: 16), SizedBox(width: 5), Text('Verified Rider', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))]), const SizedBox(height: 10), ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.deepOrange), child: const Text('Edit details'))])),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children:[
                const Text('EARNING HISTORY', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Date 15, 2021'), Text('৳6,000', style: TextStyle(fontWeight: FontWeight.bold))]), const Divider(),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('Date 21, 2022'), Text('৳1,000', style: TextStyle(fontWeight: FontWeight.bold))]),
                const SizedBox(height: 25),
                const Text('RIDER RATINGS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)), const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Recent 5 Ratings'), Row(children: List.generate(5, (index) => const Icon(Icons.star, color: Colors.orange, size: 18)))]),
                const SizedBox(height: 5), const Text('Common compliments: Fast | Polite', style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 25),
                const Text('SHOP SETTINGS', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ListTile(contentPadding: EdgeInsets.zero, title: const Text('Payout Method'), trailing: const Icon(Icons.arrow_forward_ios, size: 15), onTap: (){}),
                ListTile(contentPadding: EdgeInsets.zero, title: Row(children: const[Icon(Icons.account_balance, color: Colors.red), SizedBox(width: 10), Text('Link Bank Account'), SizedBox(width: 10), Icon(Icons.account_balance_wallet, color: Colors.pink), SizedBox(width: 5), Icon(Icons.account_balance_wallet_outlined, color: Colors.orange)]), trailing: const Icon(Icons.arrow_forward_ios, size: 15), onTap: (){}),
                ListTile(contentPadding: EdgeInsets.zero, title: Row(children: const[Icon(Icons.directions_bike), SizedBox(width: 10), Text('Vehicle Info')]), trailing: const Icon(Icons.arrow_forward_ios, size: 15), onTap: (){}),
                ListTile(contentPadding: EdgeInsets.zero, title: Row(children: const[Icon(Icons.help_outline), SizedBox(width: 10), Text('Help & Support')]), trailing: const Icon(Icons.arrow_forward_ios, size: 15), onTap: (){}),
                const SizedBox(height: 20),
                TextButton(onPressed: () async {await FirebaseAuth.instance.signOut(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));}, child: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)))
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ==========================================
// ক্যাটাগরি পেজ (রঙিন আইকন ও ১৮টি রিয়েল ক্যাটাগরি সহ)
// ==========================================
class CategoryPage extends StatefulWidget {
  const CategoryPage({super.key});

  @override
  State<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends State<CategoryPage> {
  int _selectedCategoryIndex = 0; 

  // হোম পেজের সাথে মিল রেখে ১৮টি রঙিন ক্যাটাগরি
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
        title: const Text('Categories', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true, actions:[IconButton(icon: const Icon(Icons.search, color: Colors.black), onPressed: () {})],
      ),
      body: Row(
        children:[
          // বাম দিকের মেনু
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
                      children: [
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

          // ডান দিকের রিয়েল প্রোডাক্ট গ্রিড
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
                          .where('category', isEqualTo: mainCategories[_selectedCategoryIndex]['name']) // ক্যাটাগরির নাম ম্যাচ করানো হলো
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

  // রিয়েল প্রোডাক্ট কার্ড ডিজাইনের হেল্পার ফাংশন
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
// কাস্টমারের অর্ডার হিস্ট্রি পেজ (Order Tracking)
// ==========================================
class OrderHistoryPage extends StatelessWidget {
  const OrderHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please login')));

    return DefaultTabController(
      length: 4, // ৪টি ট্যাব থাকবে
      child: Scaffold(
        backgroundColor: Colors.grey[100],
        appBar: AppBar(
          title: const Text('My Orders', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          backgroundColor: Colors.deepOrange,
          leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)),
          bottom: const TabBar(
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs:[
              Tab(text: 'All Orders'),
              Tab(text: 'Pending'),
              Tab(text: 'Shipped'),
              Tab(text: 'Delivered'),
            ],
          ),
        ),
        
        // ফায়ারবেস থেকে ইউজারের সব অর্ডার নিয়ে আসা হচ্ছে (নতুনগুলো আগে)
        body: StreamBuilder(
          stream: FirebaseFirestore.instance
              .collection('orders')
              .where('user_id', isEqualTo: user.uid)
              .orderBy('order_date', descending: true)
              .snapshots(),
          builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children:[
                    Icon(Icons.receipt_long, size: 60, color: Colors.grey.shade300),
                    const SizedBox(height: 10),
                    const Text('No orders found!', style: TextStyle(color: Colors.grey, fontSize: 16)),
                  ]
                )
              );
            }

            var allOrders = snapshot.data!.docs;

            return TabBarView(
              children:[
                _buildOrderList(allOrders), // সব অর্ডার
                _buildOrderList(allOrders.where((doc) => doc['status'] == 'Pending').toList()), // শুধু পেন্ডিং
                _buildOrderList(allOrders.where((doc) => doc['status'] == 'Shipped').toList()), // শুধু শিপড
                _buildOrderList(allOrders.where((doc) => doc['status'] == 'Delivered').toList()), // শুধু ডেলিভারড
              ],
            );
          },
        ),
      ),
    );
  }

  // অর্ডার লিস্ট ডিজাইনের হেল্পার ফাংশন
  Widget _buildOrderList(List<QueryDocumentSnapshot> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('No orders in this status.', style: TextStyle(color: Colors.grey)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(15),
      itemCount: orders.length,
      itemBuilder: (context, index) {
        var order = orders[index];
        Map<String, dynamic> data = order.data() as Map<String, dynamic>;
        List<dynamic> items = data['items'] ??[];
        
        // তারিখ বের করা
        String dateString = 'Unknown Date';
        if (data['order_date'] != null) {
          DateTime date = (data['order_date'] as Timestamp).toDate();
          // সহজ ফরম্যাট: দিন/মাস/বছর
          dateString = '${date.day}/${date.month}/${date.year}';
        }

        // স্ট্যাটাস অনুযায়ী কালার চেঞ্জ
        Color statusColor = Colors.orange; // Pending এর জন্য কমলা
        if (data['status'] == 'Shipped') statusColor = Colors.blue;
        if (data['status'] == 'Delivered') statusColor = Colors.green;
        if (data['status'] == 'Cancelled') statusColor = Colors.red;

        return Card(
          margin: const EdgeInsets.only(bottom: 15),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(15.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children:[
                // হেডার (Order ID ও স্ট্যাটাস)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    Text('Order ID: ${order.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                      child: Text(data['status'], style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text('Date: $dateString', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const Divider(height: 20),
                
                // অর্ডার করা আইটেমগুলোর লিস্ট
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    var item = items[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 5.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children:[
                          Expanded(child: Text('${item['quantity']}x ${item['product_name']}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                          Text('৳${item['price']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    );
                  }
                ),
                
                const Divider(height: 20),
                
                // ফুটার (Total Amount)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children:[
                    const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('৳${data['total_amount']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
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
    final List<XFile> images = await _picker.pickMultiImage(); // একাধিক ছবি সিলেক্ট 
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
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
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