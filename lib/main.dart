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
// মেইন স্ক্রিন (Customer Bottom Navigation Bar)
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
  void _onItemTapped(int index) {
    User? user = FirebaseAuth.instance.currentUser;

    if (index == 2) {
      // Cart বাটনে ক্লিক করলে
      if (user == null) {
        _showLoginPopup(context, "Please login to view your Cart!");
      } else {
        Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage()));
      }
    } else if (index == 3) {
      // Profile বাটনে ক্লিক করলে
      if (user == null) {
        _showLoginPopup(context, "Please login to access your Profile!");
      } else {
        setState(() { _selectedIndex = index; });
      }
    } else {
      // Home এবং Categories সবাই দেখতে পারবে
      setState(() { _selectedIndex = index; });
    }
  }

  // সুন্দর একটি লগিন পপ-আপ দেখানোর ফাংশন (Guest Mode এর জন্য)
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
                    Navigator.pop(context); // পপ-আপ বন্ধ করবে
                    Navigator.push(context, MaterialPageRoute(builder: (context) => const LoginPage())); // লগিন পেজে নিয়ে যাবে
                  },
                  child: const Text('LOGIN / REGISTER', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.pop(context), 
                child: const Text('Continue as Guest', style: TextStyle(color: Colors.grey))
              )
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
// ৪ নম্বর পেজ: Cart Page (Multi-vendor Delivery & Address Check)
// ==========================================
class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  Set<String> selectedItems = {}; 
  int dynamicDeliveryCharge = 0; 
  int uniqueSellerCount = 0; 
  bool isCalculating = true;
  bool hasSavedAddress = false; // নতুন ভেরিয়েবল: ঠিকানা আছে কিনা চেক করতে

  final double shopLatitude = 23.6062; 
  final double shopLongitude = 90.1345;

  @override
  void initState() {
    super.initState();
    _calculateDeliveryCharge();
  }

  Future<void> _calculateDeliveryCharge() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || selectedItems.isEmpty) {
      setState(() { 
        dynamicDeliveryCharge = 0; 
        uniqueSellerCount = 0;
        isCalculating = false;
      });
      return;
    }

    setState(() => isCalculating = true);

    try {
      DocumentSnapshot settingsDoc = await FirebaseFirestore.instance.collection('app_config').doc('delivery_settings').get();
      double baseDistance = 2.0; int baseCharge = 30;
      double midDistance = 5.0; int midCharge = 50;
      int extraPerKm = 10;

      if (settingsDoc.exists) {
        Map<String, dynamic> settingsData = settingsDoc.data() as Map<String, dynamic>;
        baseDistance = (settingsData['base_distance'] as num).toDouble();
        baseCharge = (settingsData['base_charge'] as num).toInt();
        midDistance = (settingsData['mid_distance'] as num).toDouble();
        midCharge = (settingsData['mid_charge'] as num).toInt();
        extraPerKm = (settingsData['extra_per_km'] as num).toInt();
      }

      var addressSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('addresses').where('is_default', isEqualTo: true).limit(1).get();
      
      // ঠিকানা আছে কিনা চেক করছি
      if (addressSnapshot.docs.isEmpty) {
        setState(() { 
          dynamicDeliveryCharge = 0; // ঠিকানা না থাকলে চার্জ ০
          hasSavedAddress = false; 
          isCalculating = false; 
        });
        return;
      }

      hasSavedAddress = true; // ঠিকানা পাওয়া গেছে

      double customerLat = addressSnapshot.docs.first['latitude'];
      double customerLng = addressSnapshot.docs.first['longitude'];

      var cartSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').get();
      Set<String> sellers = {}; 
      
      for (var doc in cartSnapshot.docs) {
        if (selectedItems.contains(doc.id)) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          String sellerId = data.containsKey('seller_id') ? data['seller_id'] : 'default_shop';
          sellers.add(sellerId);
        }
      }

      uniqueSellerCount = sellers.length;
      int totalDeliveryFee = 0;

      for (String sellerId in sellers) {
        double sLat = 23.6062; 
        double sLng = 90.1345;

        if (sellerId != 'default_shop') {
          DocumentSnapshot sellerDoc = await FirebaseFirestore.instance.collection('users').doc(sellerId).get();
          if (sellerDoc.exists && (sellerDoc.data() as Map<String, dynamic>).containsKey('latitude')) {
            sLat = sellerDoc['latitude'];
            sLng = sellerDoc['longitude'];
          }
        }

        double distanceInMeters = Geolocator.distanceBetween(sLat, sLng, customerLat, customerLng);
        double distanceInKm = (distanceInMeters / 1000) * 1.20;

        int currentSellerCharge = 0;
        if (distanceInKm <= baseDistance) {
          currentSellerCharge = baseCharge;
        } else if (distanceInKm <= midDistance) {
          currentSellerCharge = midCharge;
        } else {
          double extraKm = distanceInKm - midDistance;
          currentSellerCharge = midCharge + (extraKm.ceil() * extraPerKm);
        }

        totalDeliveryFee += currentSellerCharge; 
      }

      dynamicDeliveryCharge = totalDeliveryFee;

    } catch (e) {
      dynamicDeliveryCharge = 60; 
    }

    if (mounted) setState(() => isCalculating = false);
  }

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please login to view cart'));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.amber[200], 
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.pop(context)),
        title: const Text('YOUR CART', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions:[
          if (selectedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 28),
              onPressed: () async {
                for (String id in selectedItems) {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(id).delete();
                }
                setState(() => selectedItems.clear());
                _calculateDeliveryCharge(); 
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected items removed!')));
              },
            )
        ],
      ),
      body: isCalculating 
        ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[CircularProgressIndicator(), SizedBox(height: 10), Text('Calculating Delivery Charge...')]))
        : StreamBuilder(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Your cart is empty! Add products.', style: TextStyle(fontSize: 18, color: Colors.grey)));
          }

          int totalSalePrice = 0;
          int totalOriginalPrice = 0; 

          for (var doc in snapshot.data!.docs) {
            if (selectedItems.contains(doc.id)) { 
              Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
              int price = int.tryParse(data['price'].toString()) ?? 0;
              int originalPrice = data.containsKey('original_price') && data['original_price'].toString().isNotEmpty 
                  ? int.parse(data['original_price'].toString()) 
                  : price;
              int quantity = (data['quantity'] as num).toInt();
              
              totalSalePrice += (price * quantity);
              totalOriginalPrice += (originalPrice * quantity);
            }
          }
          
          int totalSavings = totalOriginalPrice - totalSalePrice;
          int grandTotal = totalSalePrice > 0 ? totalSalePrice + dynamicDeliveryCharge : 0; 

          return Column(
            children:[
              // ঠিকানা না থাকলে ওয়ার্নিং ব্যানার
              if (!hasSavedAddress && selectedItems.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade100,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                  child: Row(
                    children:[
                      const Icon(Icons.warning_amber_rounded, color: Colors.red),
                      const SizedBox(width: 10),
                      const Expanded(child: Text('Please add a delivery address to checkout.', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))),
                      TextButton(
                        onPressed: () {
                          // ঠিকানা যোগ করার পেজে নিয়ে যাবে
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const AddressSetupPage())).then((_) => _calculateDeliveryCharge());
                        },
                        child: const Text('ADD NOW', style: TextStyle(color: Colors.red, decoration: TextDecoration.underline)),
                      )
                    ],
                  ),
                ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(15),
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var cartItem = snapshot.data!.docs[index];
                    Map<String, dynamic> data = cartItem.data() as Map<String, dynamic>;
                    String imageUrl = data.containsKey('image_url') ? data['image_url'] : '';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        children:[
                          Checkbox(
                            value: selectedItems.contains(cartItem.id),
                            activeColor: Colors.deepOrange,
                            onChanged: (val) {
                              setState(() { 
                                val! ? selectedItems.add(cartItem.id) : selectedItems.remove(cartItem.id); 
                              });
                              _calculateDeliveryCharge(); 
                            },
                          ),
                          Container(
                            height: 60, width: 60,
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                            child: imageUrl.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(imageUrl, fit: BoxFit.cover)) : const Icon(Icons.checkroom, color: Colors.blue),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children:[
                                Text(cartItem['product_name'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 5),
                                Text('৳${cartItem['price']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                                if (data.containsKey('selected_color') && data['selected_color'].toString().isNotEmpty) Text('Color: ${data['selected_color']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (data.containsKey('selected_size') && data['selected_size'].toString().isNotEmpty) Text('Size: ${data['selected_size']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                          Row(
                            children:[
                              InkWell(
                                onTap: () { 
                                  if (cartItem['quantity'] > 1) {
                                    FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).update({'quantity': FieldValue.increment(-1)}); 
                                    _calculateDeliveryCharge(); 
                                  }
                                },
                                child: Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)), child: const Icon(Icons.remove, size: 20)),
                              ),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('${cartItem['quantity']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              InkWell(
                                onTap: () { 
                                  FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).update({'quantity': FieldValue.increment(1)}); 
                                  _calculateDeliveryCharge();
                                },
                                child: Container(decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(5)), child: const Icon(Icons.add, size: 20, color: Colors.deepOrange)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.amber[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children:[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children:[
                        const Text('ORDER SUMMARY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        if (uniqueSellerCount > 1)
                          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.deepOrange.shade100, borderRadius: BorderRadius.circular(10)), child: Text('From $uniqueSellerCount Shops', style: const TextStyle(color: Colors.deepOrange, fontSize: 10, fontWeight: FontWeight.bold))),
                      ],
                    ),
                    const SizedBox(height: 15),
                    
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Subtotal'), Text('৳$totalOriginalPrice', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 5),
                    
                    if (totalSavings > 0) ...[
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Discount Savings', style: TextStyle(color: Colors.red)), Text('-৳$totalSavings', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 5),
                    ],

                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[
                      const Text('Delivery Charge'), 
                      Text(hasSavedAddress ? '৳$dynamicDeliveryCharge' : 'Select Address', style: TextStyle(fontWeight: FontWeight.bold, color: hasSavedAddress ? Colors.black : Colors.red))
                    ]),
                    
                    const Divider(thickness: 1, height: 20),
                    
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children:[
                        const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), 
                        Text('৳$grandTotal', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 20))
                      ]
                    ),
                    const SizedBox(height: 15),

                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        // ঠিকানা না থাকলে বা পণ্য সিলেক্ট না করলে বাটন ডিজেবল থাকবে
                        onPressed: (!isCalculating && totalSalePrice > 0 && hasSavedAddress) ? () { 
                          // নির্বাচিত আইটেমগুলো নিয়ে চেকআউট পেজে পাঠানো
                          Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(grandTotal: grandTotal, selectedItemIds: selectedItems.toList()))); 
                        } : null,
                        child: const Text('CHECKOUT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
}

// ==========================================
// ৫ নম্বর পেজ: Checkout & Payment Method (Real Address & Save Order)
// ==========================================
class CheckoutPage extends StatefulWidget {
  final int grandTotal; 
  final List<String> selectedItemIds; // কার্ট থেকে কোন কোন পণ্য কিনেছে তার লিস্ট
  
  const CheckoutPage({super.key, required this.grandTotal, required this.selectedItemIds});
  
  @override 
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  String selectedPayment = 'Cash on Delivery';
  
  // কাস্টমারের আসল ঠিকানা সেভ রাখার জন্য
  Map<String, dynamic>? deliveryAddress;
  bool isLoadingAddress = true;

  @override
  void initState() {
    super.initState();
    _fetchDeliveryAddress();
  }

  // ফায়ারবেস থেকে ডিফল্ট ঠিকানা নিয়ে আসা
  Future<void> _fetchDeliveryAddress() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      var addressSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('addresses').where('is_default', isEqualTo: true).limit(1).get();
      if (addressSnapshot.docs.isNotEmpty) {
        setState(() {
          deliveryAddress = addressSnapshot.docs.first.data() as Map<String, dynamic>;
        });
      }
    }
    setState(() => isLoadingAddress = false);
  }

  void confirmOrder() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null || deliveryAddress == null || widget.selectedItemIds.isEmpty) return;
    
    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      // ১. কার্ট থেকে শুধু সিলেক্ট করা পণ্যগুলো আনা
      List<Map<String, dynamic>> itemsToOrder =[];
      var cartSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').get();
      
      for (var doc in cartSnapshot.docs) { 
        if (widget.selectedItemIds.contains(doc.id)) {
          Map<String, dynamic> itemData = doc.data() as Map<String, dynamic>;
          itemsToOrder.add({
            'product_name': itemData['product_name'], 
            'price': itemData['price'], 
            'quantity': itemData['quantity'],
            'seller_id': itemData.containsKey('seller_id') ? itemData['seller_id'] : 'unknown',
            'image_url': itemData.containsKey('image_url') ? itemData['image_url'] : '',
          }); 
        }
      }

      // ২. অর্ডার সেভ করা (আসল ঠিকানা সহ)
      await FirebaseFirestore.instance.collection('orders').add({
        'user_id': user.uid, 
        'items': itemsToOrder, 
        'total_amount': widget.grandTotal, 
        'payment_method': selectedPayment, 
        'status': 'Pending', 
        'order_date': FieldValue.serverTimestamp(), 
        'shipping_name': deliveryAddress!['shipping_name'],
        'shipping_phone': deliveryAddress!['shipping_phone'],
        'shipping_address': deliveryAddress!['shipping_address_text'],
        'latitude': deliveryAddress!['latitude'],
        'longitude': deliveryAddress!['longitude'],
      });

      // ৩. কার্ট থেকে শুধু অর্ডার করা পণ্যগুলো ডিলিট করা
      for (String docId in widget.selectedItemIds) { 
        await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(docId).delete(); 
      }
      
      if (!mounted) return;
      Navigator.pop(context); // লোডিং অফ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Placed Successfully! 🎉')));
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false);
    } catch (e) { 
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); 
    }
  }

  @override 
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[50], 
      appBar: AppBar(backgroundColor: Colors.teal[400], elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)), title: const Text('PAYMENT METHOD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), centerTitle: true),
      body: isLoadingAddress 
      ? const Center(child: CircularProgressIndicator()) 
      : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(children:[_buildPaymentOption('Credit/Debit Card', Icons.credit_card, Colors.blue), const Divider(height: 1), _buildPaymentOption('bKash', Icons.account_balance_wallet, Colors.pink), const Divider(height: 1), _buildPaymentOption('Nagad', Icons.account_balance_wallet_outlined, Colors.orange), const Divider(height: 1), _buildPaymentOption('Cash on Delivery', Icons.local_shipping, Colors.teal)])),
          const SizedBox(height: 30),
          const Text('DELIVERY ADDRESS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
          
          // ফায়ারবেস থেকে আসা আসল ঠিকানা দেখানো
          Container(
            width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), 
            child: deliveryAddress != null 
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children:[
                    Text(deliveryAddress!['shipping_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                    Text(deliveryAddress!['shipping_phone'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 13)), 
                    const SizedBox(height: 5), 
                    Text(deliveryAddress!['shipping_address_text'] ?? '', style: const TextStyle(color: Colors.black87, fontSize: 14))
                  ]
                )
              : const Text('No default address found! Please add one from your profile.', style: TextStyle(color: Colors.red)),
          ),
          
          const SizedBox(height: 30),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Order Total + Delivery', style: TextStyle(fontSize: 16)), Text('৳${widget.grandTotal}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
          const SizedBox(height: 10),
          Row(children: const[Icon(Icons.lock, size: 16, color: Colors.grey), SizedBox(width: 5), Text('Secure Payment', style: TextStyle(color: Colors.grey))]),
          const SizedBox(height: 30),
          
          // ঠিকানা না থাকলে কনফার্ম বাটন ডিজেবল থাকবে
          SizedBox(
            width: double.infinity, height: 50, 
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[400], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
              onPressed: deliveryAddress != null ? confirmOrder : null, 
              child: const Text('CONFIRM ORDER', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
            )
          )
        ]),
      ),
    );
  }
  
  Widget _buildPaymentOption(String title, IconData icon, Color iconColor) {
    return RadioListTile<String>(title: Row(children:[Icon(icon, color: iconColor), const SizedBox(width: 15), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]), value: title, groupValue: selectedPayment, activeColor: Colors.deepOrange, onChanged: (value) => setState(() => selectedPayment = value!));
  }
}

// ==========================================
// ৩ নম্বর পেজ: Product Details (Fixed Fly Animation + Dynamic Pricing)
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

  // জাদুকরী Fly to Cart এনিমেশন ফাংশন (Restored)
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
    if (user == null) return;

    Map<String, dynamic> data = widget.product.data() as Map<String, dynamic>;
    List<dynamic> colors = data.containsKey('colors') ? data['colors'] :[];
    List<dynamic> sizes = data.containsKey('sizes') ? data['sizes'] :[];

    if (colors.isNotEmpty && selectedColor == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a color first!'))); return; }
    if (sizes.isNotEmpty && selectedSize == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a size first!'))); return; }

    // এনিমেশন কল করা হলো
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
        'added_at': FieldValue.serverTimestamp(),
      });
    }
    if (!mounted) return;
    if (isBuyNow) { Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())); } 
    else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item flying to Cart! 🚀'), duration: Duration(seconds: 1))); }
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
            key: _cartKey, // <--- কার্ট আইকনের Key
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
                        // <--- ছবির Key
                        Center(child: Container(key: _imageKey, height: 300, width: double.infinity, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: mainImage.isNotEmpty ? Image.network(mainImage, fit: BoxFit.contain) : const Icon(Icons.image, size: 100, color: Colors.grey))),
                        const SizedBox(height: 15),
                        if (images.length > 1) SizedBox(height: 60, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: images.length, itemBuilder: (context, index) { bool isSelected = _selectedImageIndex == index; return InkWell(onTap: () => setState(() => _selectedImageIndex = index), child: Container(margin: const EdgeInsets.only(right: 10), height: 60, width: 60, decoration: BoxDecoration(border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300, width: 2), borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(images[index]), fit: BoxFit.cover)))); })),
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
                  Container(
                    width: double.infinity, color: Colors.white, padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        if(colors.isNotEmpty) ...[
                          const Text('Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10), 
                          Wrap(spacing: 10, children: colors.map((c) {
                              bool isSelected = selectedColor == c;
                              int extra = (c['extra_price'] as num).toInt();
                              return InkWell(
                                onTap: () => setState(() => selectedColor = isSelected ? null : c),
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), decoration: BoxDecoration(color: isSelected ? Colors.deepOrange.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Text('${c['name']} ${extra > 0 ? '(+৳$extra)' : ''}', style: TextStyle(color: isSelected ? Colors.deepOrange : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)))
                              );
                            }).toList()
                          ), 
                          const SizedBox(height: 20)
                        ],
                        if(sizes.isNotEmpty) ...[
                          const Text('Sizes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10), 
                          Wrap(spacing: 10, children: sizes.map((s) {
                              bool isSelected = selectedSize == s;
                              int extra = (s['extra_price'] as num).toInt();
                              return InkWell(
                                onTap: () => setState(() => selectedSize = isSelected ? null : s),
                                child: Container(padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), decoration: BoxDecoration(color: isSelected ? Colors.teal.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.teal : Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Text('${s['name']} ${extra > 0 ? '(+৳$extra)' : ''}', style: TextStyle(color: isSelected ? Colors.teal : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)))
                              );
                            }).toList()
                          ), 
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
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
                                return Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Text(snapshot.data!['name'] ?? 'Verified Seller', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Row(children: const[Icon(Icons.verified, color: Colors.green, size: 14), SizedBox(width: 4), Text('Verified Shop', style: TextStyle(color: Colors.green, fontSize: 12))])]);
                              }
                              return const Text('Loading shop info...', style: TextStyle(color: Colors.grey));
                            }
                          ),
                        ),
                        OutlinedButton(onPressed: (){}, style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.deepOrange), foregroundColor: Colors.deepOrange), child: const Text('View Shop'))
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
                              Text(data.containsKey('description') && data['description'].toString().isNotEmpty ? data['description'] : 'No description available for this product.', style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5), maxLines: _isDescExpanded ? null : 4, overflow: _isDescExpanded ? TextOverflow.visible : TextOverflow.ellipsis),
                              const SizedBox(height: 5),
                              Row(mainAxisAlignment: MainAxisAlignment.center, children:[Text(_isDescExpanded ? 'Show Less' : 'Read More', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)), Icon(_isDescExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.teal)])
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
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
        actions:[IconButton(icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())))],
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
// ১ নম্বর পেজ: User Profile (Superfast with Local Cache)
// ==========================================
class UserDashboard extends StatefulWidget {
  const UserDashboard({super.key});

  @override
  State<UserDashboard> createState() => _UserDashboardState();
}

class _UserDashboardState extends State<UserDashboard> {
  User? currentUser = FirebaseAuth.instance.currentUser;
  final ImagePicker _picker = ImagePicker();

  // লোকাল ভেরিয়েবল (ইনস্ট্যান্ট দেখানোর জন্য)
  String _userName = 'Loading...';
  String _profileImageUrl = '';

  @override
  void initState() {
    super.initState();
    _loadProfileData(); // পেজ ওপেন হলেই ডাটা লোড হবে
  }

  // ম্যাজিক ফাংশন: লোকাল মেমরি থেকে ডাটা আনবে, এরপর ফায়ারবেস থেকে আপডেট করবে
  Future<void> _loadProfileData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    
    // ১. প্রথমে লোকাল মেমরি (Cache) থেকে সাথে সাথে ডাটা দেখাবে (0 second delay)
    if (mounted) {
      setState(() {
        _userName = prefs.getString('user_name') ?? 'Customer';
        _profileImageUrl = prefs.getString('profile_image') ?? '';
      });
    }

    // ২. ব্যাকগ্রাউন্ডে ফায়ারবেস থেকে চেক করবে নতুন কোনো আপডেট আছে কি না
    if (currentUser != null) {
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String newName = data['name'] ?? 'Customer';
        String newImage = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';

        // যদি ডাটাবেসের ডাটার সাথে লোকাল ডাটার অমিল থাকে, তবে আপডেট করে সেভ করবে
        if (_userName != newName || _profileImageUrl != newImage) {
          prefs.setString('user_name', newName);
          prefs.setString('profile_image', newImage);
          if (mounted) {
            setState(() {
              _userName = newName;
              _profileImageUrl = newImage;
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
      
      // ফায়ারবেসে সেভ
      await FirebaseFirestore.instance.collection('users').doc(currentUser!.uid).update({'profile_image_url': downloadUrl});

      // লোকাল মেমরিতেও সাথে সাথে সেভ করে দেওয়া
      SharedPreferences prefs = await SharedPreferences.getInstance();
      prefs.setString('profile_image', downloadUrl);

      if (!mounted) return;
      Navigator.pop(context); 
      
      // UI আপডেট করা
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
                    // এখন আর FutureBuilder নেই, সরাসরি লোকাল মেমরি থেকে ছবি দেখাচ্ছে
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
                      // লোকাল মেমরি থেকে ইনস্ট্যান্ট নাম
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
          const SizedBox(height: 20),
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
                  // লগআউট করার সময় লোকাল মেমরি ক্লিয়ার করে দেওয়া
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
// অ্যাডভান্সড সাইন-আপ পেজ (Role Based + Map + Social Login)
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
  
  String selectedRole = 'customer'; // ডিফল্টভাবে কাস্টমার সিলেক্ট থাকবে
  LatLng? vendorLocation; // সেলার/রাইডারের লোকেশন সেভ রাখার জন্য

  // ইমেইল দিয়ে অ্যাকাউন্ট খোলার মেইন ফাংশন
  void createAccount() async {
    if (nameController.text.isEmpty || emailController.text.isEmpty || passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সবগুলো ঘর পূরণ করুন!')));
      return;
    }

    // সেলার বা রাইডার হলে লোকেশন দেওয়া বাধ্যতামূলক
    if (selectedRole != 'customer' && vendorLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সেলার বা রাইডার হিসেবে যুক্ত হতে ম্যাপে লোকেশন সেট করা বাধ্যতামূলক! 📍')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      // ফায়ারবেস অথেনটিকেশন
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: emailController.text.trim(), 
        password: passwordController.text.trim()
      );
      
      // ডাটাবেসে সেভ করার জন্য ডাটা প্রস্তুত করা
      Map<String, dynamic> userData = {
        'name': nameController.text.trim(), 
        'email': emailController.text.trim(), 
        'role': selectedRole, 
        'created_at': FieldValue.serverTimestamp()
      };

      // যদি সেলার বা রাইডার হয়, তবে তাদের লোকেশন এবং পেন্ডিং স্ট্যাটাস যোগ হবে
      if (selectedRole != 'customer') {
        userData['latitude'] = vendorLocation!.latitude;
        userData['longitude'] = vendorLocation!.longitude;
        userData['status'] = 'pending'; // অ্যাডমিন এপ্রুভ না করা পর্যন্ত পেন্ডিং থাকবে
      }

      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set(userData);
      
      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Created Successfully! 🎉')));
      
      // রোল অনুযায়ী পেজে পাঠানো
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
            // রোল সিলেক্ট করার টগল বাটন
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
            TextField(controller: emailController, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email Address', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), 
            const SizedBox(height: 15), 
            TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password (min 6 chars)', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))), 
            const SizedBox(height: 20), 

            // সেলার বা রাইডার সিলেক্ট করলে লোকেশন বাটন দেখাবে
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
                        // ম্যাপ পেজ থেকে লোকেশন নিয়ে আসবে
                        LatLng? result = await Navigator.push(context, MaterialPageRoute(builder: (context) => const LocationPickerScreen()));
                        if (result != null) {
                          setState(() { vendorLocation = result; });
                        }
                      }, 
                      child: Text(vendorLocation == null ? 'Set on Map' : 'Change', style: const TextStyle(color: Colors.white))
                    )
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: createAccount, child: const Text('CREATE ACCOUNT', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
            
            const SizedBox(height: 30),
            Row(children: const[Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("OR SIGN UP WITH", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))), Expanded(child: Divider())]),
            const SizedBox(height: 20),

            // Google এবং Phone বাটন (Social Login)
            Row(
              children:[
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.g_mobiledata, color: Colors.red, size: 30),
                    label: const Text('Google', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Firebase settings required for Google Sign-In! We will do it next.')));
                    },
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                    icon: const Icon(Icons.phone_android, color: Colors.blue, size: 24),
                    label: const Text('Phone', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone Authentication coming soon!')));
                    },
                  ),
                ),
              ],
            )
          ]
        )
      )
    );
  }

  // রোল সিলেক্ট করার টগল বাটনের ডিজাইন
  Widget _buildRoleOption(String title, String role, IconData icon) {
    bool isSelected = selectedRole == role;
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() { 
            selectedRole = role; 
            vendorLocation = null; // রোল চেঞ্জ করলে লোকেশন রিসেট হয়ে যাবে
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.deepOrange : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected ? [const BoxShadow(color: Colors.black12, blurRadius: 5)] :[],
          ),
          child: Column(
            children:[
              Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
              const SizedBox(height: 5),
              Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
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
// সেলার ড্যাশবোর্ড এবং পেজসমূহ
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

class SellerDashboard extends StatelessWidget {
  const SellerDashboard({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(backgroundColor: Colors.deepOrange, title: const Text('D Shop Seller', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), actions:[IconButton(icon: const Icon(Icons.notifications_none, color: Colors.white), onPressed: () {})]),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Row(children:[const CircleAvatar(radius: 30, backgroundColor: Colors.orange, child: Icon(Icons.person, color: Colors.white, size: 30)), const SizedBox(width: 15), Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Rahim Ahmed', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text('Seller ID: #98765', style: TextStyle(color: Colors.grey))])]),
            const SizedBox(height: 25),
            const Text('Overall Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            Row(children:[_buildStatCard("Today's Sales", "৳১০,৫০০", Colors.teal[50]!, Colors.teal), const SizedBox(width: 15), _buildStatCard("Active Orders", "১৫", Colors.orange[50]!, Colors.orange)]),
            const SizedBox(height: 25),
            const Text('Product Low Stock', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            _buildLowStockItem("Cotton T-Shirt", "৳২,০০০", "5", Colors.red), _buildLowStockItem("Smart Watch", "৳২,৮০০", "3", Colors.orange),
            const SizedBox(height: 25),
            const Text('QUICK ACTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), const SizedBox(height: 10),
            Row(children:[_buildQuickAction(Icons.add_circle_outline, "Add Product", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage()))), const SizedBox(width: 15), _buildQuickAction(Icons.analytics_outlined, "Analytics", Colors.amber, () {})]),
          ],
        ),
      ),
    );
  }
  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {return Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)), child: Column(children:[Text(title, style: const TextStyle(fontSize: 14)), const SizedBox(height: 5), Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor))]))); }
  Widget _buildLowStockItem(String name, String price, String count, Color statusColor) {return ListTile(contentPadding: EdgeInsets.zero, leading: Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.image)), title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)), subtitle: Text(price), trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children:[const Text('Critical', style: TextStyle(fontSize: 10, color: Colors.grey)), Text(count, style: TextStyle(fontWeight: FontWeight.bold, color: statusColor))])); }
  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {return Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))), child: Column(children:[Icon(icon, color: color, size: 30), const SizedBox(height: 5), Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color))]))));}
}

class ProductManagement extends StatelessWidget {
  const ProductManagement({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.amber[200], elevation: 0, title: const Text('PRODUCT MANAGEMENT', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)), leading: const Icon(Icons.arrow_back_ios, color: Colors.black)),
      body: Column(children:[
        Padding(padding: const EdgeInsets.all(15.0), child: TextField(decoration: InputDecoration(hintText: 'Search for products...', prefixIcon: const Icon(Icons.search), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
        Expanded(child: ListView.builder(itemCount: 5, padding: const EdgeInsets.symmetric(horizontal: 15), itemBuilder: (context, index) {return Card(margin: const EdgeInsets.only(bottom: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), child: ListTile(leading: Container(width: 60, height: 60, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.headphones)), title: const Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold)), subtitle: const Text('Price: ৳২,৮০০\nStock: ১৬'), trailing: Column(children:[const Text('Status', style: TextStyle(fontSize: 10)), Switch(value: true, activeThumbColor: Colors.teal, onChanged: (v) {})])));})),
      ]),
      floatingActionButton: FloatingActionButton.extended(backgroundColor: Colors.blue, onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage())), label: const Text('Add New Product'), icon: const Icon(Icons.add)),
    );
  }
}

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

class SellerProfile extends StatelessWidget {
  const SellerProfile({super.key});
  @override Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.orange[100], elevation: 0),
      body: Column(children:[
        Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.orange[100], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))), child: Column(children:[const CircleAvatar(radius: 50, backgroundColor: Colors.white, child: Icon(Icons.person, size: 50, color: Colors.orange)), const SizedBox(height: 10), const Text('Rahim Ahmed', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), const Text('Ahmed Electronics', style: TextStyle(color: Colors.grey)), ElevatedButton(onPressed: () {}, child: const Text('Edit Info'))])),
        Expanded(child: ListView(padding: const EdgeInsets.all(20), children:[_buildProfileItem(Icons.store, "Store Name/Logo"), _buildProfileItem(Icons.phone, "Contact Info"), _buildProfileItem(Icons.description, "Tax Information"), const SizedBox(height: 30), TextButton(onPressed: () async {await FirebaseAuth.instance.signOut(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));}, child: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18)))])),
      ]),
    );
  }
  Widget _buildProfileItem(IconData icon, String title) {return ListTile(leading: Icon(icon, color: Colors.deepOrange), title: Text(title), trailing: const Icon(Icons.arrow_forward_ios, size: 15));}
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
// অ্যাডমিন পেজ ১: Dashboard (Overall Platform & Smart Drawer)
// ==========================================
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, 
        title: const Text('D Shop ADMIN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white), // ড্রয়ার আইকনের কালার সাদা করার জন্য
      ),
      
      // ==========================================
      // অ্যাডমিন সাইড মেনু (Smart Admin Drawer)
      // ==========================================
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children:[
            // অ্যাডমিন প্রোফাইল হেডার
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
            
            // মেনু অপশনগুলো
            ListTile(
              leading: const Icon(Icons.notifications_active, color: Colors.blue),
              title: const Text('Push Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('Send offers to all', style: TextStyle(fontSize: 10, color: Colors.grey)),
              onTap: () {
                Navigator.pop(context); // ড্রয়ার বন্ধ করতে
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminNotificationPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.category, color: Colors.teal),
              title: const Text('Manage Categories', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminManageCategoriesPage())); // নতুন পেজে যাবে
              },
            ),
            ListTile(
              leading: const Icon(Icons.view_carousel, color: Colors.orange),
              title: const Text('Manage Banners', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context, 
                  MaterialPageRoute(builder: (context) => const AdminBannerManagementPage())
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.motorcycle, color: Colors.purple),
              title: const Text('Manage Riders', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context); // ড্রয়ার বন্ধ করতে
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminManageRidersPage()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.green),
              title: const Text('Delivery Zones & Charges', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context); // ড্রয়ার বন্ধ করতে
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AdminDeliveryZonePage()),
                );
              },
            ),
            const Divider(height: 30, thickness: 1),
            
            // লগ আউট বাটন
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Secure Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                if (context.mounted) {
                  Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));
                }
              },
            ),
          ],
        ),
      ),

      // ==========================================
      // ড্যাশবোর্ড বডি (আগের মতোই থাকবে)
      // ==========================================
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            const Text('Overall Platform', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.teal[100], borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Today\'s Revenue'), Text('৳১,২০,৫০০', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))])),
            const SizedBox(height: 15),
            Row(
              children:[
                Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.green[100], borderRadius: BorderRadius.circular(15)), child: Column(children: const[Text('Total Orders'), Text('১৫০', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))),
                const SizedBox(width: 15),
                Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(15)), child: Column(children: const[Text('New Signups'), Text('৫০', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))),
              ],
            ),
            const SizedBox(height: 25),
            const Text('Sales Overview (7 Days)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Container(height: 200, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15)), child: const Center(child: Icon(Icons.bar_chart, size: 100, color: Colors.teal))),
            const SizedBox(height: 25),
            const Text('Action Center', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            InkWell(
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminProductApprovalPage()));
              },
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow:[BoxShadow(color: Colors.grey.shade200, blurRadius: 10, offset: const Offset(0, 5))],
                ),
                child: Row(
                  children:[
                    const CircleAvatar(
                      backgroundColor: Colors.deepOrange,
                      child: Icon(Icons.pending_actions, color: Colors.white),
                    ),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children:[
                          const Text('Pending Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('products')
                                .where('status', isEqualTo: 'pending')
                                .snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              int count = snapshot.hasData ? snapshot.data!.docs.length : 0;
                              return Text('$count products need your approval', 
                                style: const TextStyle(color: Colors.grey, fontSize: 13));
                            },
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  ],
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
// অ্যাডমিন পেজ ২: User & Seller Management (Approval System)
// ==========================================
class AdminUserManagement extends StatefulWidget {
  const AdminUserManagement({super.key});

  @override
  State<AdminUserManagement> createState() => _AdminUserManagementState();
}

class _AdminUserManagementState extends State<AdminUserManagement> {
  // কোন ট্যাবে আছে তা ট্র্যাক করার জন্য (0 = Users, 1 = Sellers)
  int _selectedTab = 1; 

  @override
  Widget build(BuildContext context) {
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
                      backgroundColor: _selectedTab == 0 ? Colors.deepOrange : Colors.white, 
                      foregroundColor: _selectedTab == 0 ? Colors.white : Colors.black
                    ), 
                    child: const Text('Customers')
                  )
                ), 
                const SizedBox(width: 10), 
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => setState(() => _selectedTab = 1), 
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _selectedTab == 1 ? Colors.teal : Colors.white, 
                      foregroundColor: _selectedTab == 1 ? Colors.white : Colors.black
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
                  .where('role', isEqualTo: _selectedTab == 0 ? 'customer' : 'seller')
                  .snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Text(
                      _selectedTab == 0 ? 'No customers found!' : 'No sellers found!', 
                      style: const TextStyle(color: Colors.grey)
                    )
                  );
                }

                var users = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: users.length,
                  itemBuilder: (context, index) {
                    var userDoc = users[index];
                    Map<String, dynamic> data = userDoc.data() as Map<String, dynamic>;
                    
                    // সেলারের স্ট্যাটাস চেক
                    String status = data.containsKey('status') ? data['status'] : 'approved';
                    bool isPending = status == 'pending';
                    String imgUrl = data.containsKey('profile_image_url') ? data['profile_image_url'] : '';

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
                                  child: imgUrl.isEmpty ? Icon(_selectedTab == 0 ? Icons.person : Icons.store, color: Colors.grey) : null,
                                ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start, 
                                    children:[
                                      Text(data['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
                                      Text(data['email'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                      // সেলার হলে স্ট্যাটাস দেখাবে
                                      if (_selectedTab == 1)
                                        Text(
                                          'Status: ${status.toUpperCase()}', 
                                          style: TextStyle(
                                            color: isPending ? Colors.red : Colors.green, 
                                            fontWeight: FontWeight.bold, 
                                            fontSize: 12
                                          )
                                        )
                                    ]
                                  )
                                ),
                                // যদি সেলার হয় এবং Pending থাকে, তবেই Approve বাটন দেখাবে
                                if (_selectedTab == 1 && isPending)
                                  ElevatedButton(
                                    onPressed: () {
                                      // ডাটাবেসে স্ট্যাটাস আপডেট করে Approved করে দেওয়া হচ্ছে
                                      userDoc.reference.update({'status': 'approved'});
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seller Approved Successfully! ✅')));
                                    }, 
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), 
                                    child: const Text('Approve', style: TextStyle(color: Colors.white))
                                  )
                                else if (_selectedTab == 1 && !isPending)
                                  const Icon(Icons.verified, color: Colors.green) // এপ্রুভ হয়ে গেলে টিক চিহ্ন দেখাবে
                              ],
                            ),
                            // সেলার হলে লোকেশন এবং অন্যান্য অপশন দেখাবে
                            if (_selectedTab == 1) ...[
                              const Divider(height: 25),
                              Row(
                                children:[
                                  const Icon(Icons.location_on, color: Colors.red, size: 16),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      data.containsKey('latitude') ? 'Location Pinned (Lat: ${data['latitude'].toString().substring(0, 5)}...)' : 'No location saved', 
                                      style: const TextStyle(fontSize: 12, color: Colors.grey)
                                    )
                                  ),
                                ]
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround, 
                                children:[
                                  TextButton.icon(onPressed: (){}, icon: const Icon(Icons.inventory_2, size: 16), label: const Text('Products')),
                                  TextButton.icon(onPressed: (){}, icon: const Icon(Icons.bar_chart, size: 16), label: const Text('Sales'))
                                ]
                              )
                            ]
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
// অ্যাডমিন পেজ ৩: Order & Delivery Control
// ==========================================
class AdminOrderControl extends StatelessWidget {
  const AdminOrderControl({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.amber[100], title: const Text('Operations Control', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          bottom: const TabBar(labelColor: Colors.black, indicatorColor: Colors.deepOrange, tabs:[Tab(text: 'All Orders'), Tab(text: 'Dispatched'), Tab(text: 'Problematic')]),
        ),
        body: ListView.builder(
          padding: const EdgeInsets.all(15), itemCount: 3,
          itemBuilder: (context, index) {
            return Container(
              margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const[Text('ID: 210977', style: TextStyle(fontWeight: FontWeight.bold)), Text('Value: ৳২,৮০০', style: TextStyle(fontWeight: FontWeight.bold))]),
                  const SizedBox(height: 10),
                  Row(
                    children:[
                      Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.shopping_bag, color: Colors.blue)),
                      const SizedBox(width: 15),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Smart Watch', style: TextStyle(fontWeight: FontWeight.bold)), Text('Customer: Jane Doe', style: TextStyle(fontSize: 12)), Text('Rider: Unassigned', style: TextStyle(fontSize: 12, color: Colors.red))])),
                      ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), child: const Text('Track', style: TextStyle(color: Colors.white)))
                    ],
                  )
                ],
              ),
            );
          }
        ),
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ ৪: Finance & Reports
// ==========================================
class AdminFinanceReports extends StatelessWidget {
  const AdminFinanceReports({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.orange[200], title: const Text('Financial Oversight', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.amber[100], borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Total Platform Balance'), Text('৳৫,০০,০০০', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold))])),
            const SizedBox(height: 15),
            Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(15)), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Pending Payouts'), Text('৳৮০,৫০০', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red))]), Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)), child: const Text('Critical: 2', style: TextStyle(color: Colors.white)))])),
            const SizedBox(height: 25),
            const Text('Revenue Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Container(height: 150, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)), child: const Center(child: Icon(Icons.pie_chart, size: 80, color: Colors.teal))),
            const SizedBox(height: 25),
            const Text('Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ListView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: 3, itemBuilder: (context, index) {
              return ListTile(contentPadding: EdgeInsets.zero, title: const Text('Seller Payout'), subtitle: const Text('Pending: ৳১৫,০০০'), trailing: ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange), child: const Text('Settle', style: TextStyle(color: Colors.white))));
            })
          ],
        ),
      ),
    );
  }
}

// ==========================================
// অ্যাডমিন পেজ ৫: System Settings & Admin
// ==========================================
class AdminSettings extends StatelessWidget {
  const AdminSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.deepOrange, title: const Text('D Shop ADMIN', style: TextStyle(color: Colors.white)), centerTitle: true),
      body: SingleChildScrollView(
        child: Column(
          children:[
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: const BoxDecoration(color: Colors.white), child: Column(children: const[CircleAvatar(radius: 40, backgroundImage: NetworkImage('https://via.placeholder.com/150')), SizedBox(height: 10), Text('Rahim Ahmed', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), Text('Chief Admin', style: TextStyle(color: Colors.grey))])),
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children:[
                  const Text('Control Center', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _buildSettingItem(Icons.store, 'Store Details'),
                  _buildSettingItem(Icons.settings_applications, 'App Config'),
                  _buildSettingItem(Icons.people, 'Staff Accounts', trailingText: 'Edit'),
                  _buildSettingItem(Icons.admin_panel_settings, 'Role Management'),
                  _buildSettingItem(Icons.cloud_download, 'Data Backup'),
                  _buildSettingItem(Icons.security, 'Security Log'),
                  const SizedBox(height: 30),
                  SizedBox(width: double.infinity, child: TextButton(onPressed: () async {await FirebaseAuth.instance.signOut(); Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage()));}, child: const Text('Log Out', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold))))
                ],
              ),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem(IconData icon, String title, {String? trailingText}) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey[700]),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: trailingText != null ? Text(trailingText, style: const TextStyle(color: Colors.deepOrange)) : const Icon(Icons.arrow_forward_ios, size: 15),
      onTap: () {},
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
                        decoration: const InputDecoration(labelText: 'Category Name (e.g. Mobile)', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
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