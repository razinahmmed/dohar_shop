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


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  Widget initialPage = FirebaseAuth.instance.currentUser == null
      ? const LoginPage()
      : const MainScreen();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: initialPage,
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
    if (index == 2) {
      // কার্ট বাটনে চাপ দিলে ইনডেক্স পাল্টাবে না, বরং নতুন পেজে পাঠিয়ে দেবে
      // এতে ফ্লাটার মনে রাখবে যে সে একটা নতুন পর্দার ওপর আছে
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const CartPage()),
      );
    } else {
      // বাকি পেজগুলোর জন্য আগের মতোই ইনডেক্স পরিবর্তন হবে
      setState(() {
        _selectedIndex = index;
      });
    }
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
// ৪ নম্বর পেজ: Cart Page (কার্ট পেজ)
// ==========================================
class CartPage extends StatefulWidget {
  const CartPage({super.key});
  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  // ১০-২০টি পণ্য একসাথে সিলেক্ট করে ডিলিট করার জন্য এই সেটটি ব্যবহার হবে
  Set<String> selectedItems = {}; 

  @override
  Widget build(BuildContext context) {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text('Please login to view cart'));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.amber[200], 
        elevation: 0,
        // ১. ব্যাক বাটন ফিক্স
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.black), 
          onPressed: () => Navigator.pop(context) 
        ),
        title: const Text('YOUR CART', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          // ২. তোমার আইডিয়া: মাল্টি-ডিলিট বাটন (সিলেক্ট করলেই দেখা যাবে)
          if (selectedItems.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red, size: 28),
              onPressed: () async {
                for (String id in selectedItems) {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(id).delete();
                }
                setState(() => selectedItems.clear());
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selected items removed!')));
              },
            )
        ],
      ),
      body: StreamBuilder(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').snapshots(),
        builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Your cart is empty! Add products.', style: TextStyle(fontSize: 18, color: Colors.grey)));
          }

          // আগের লুপটি পরিবর্তন করে শুধু সিলেক্ট করা আইটেম যোগ করো
          int total = 0;
          for (var doc in snapshot.data!.docs) {
            // ম্যাজিক কন্ডিশন: যদি আইটেমটি selectedItems সেটে থাকে [cite: 14]
            if (selectedItems.contains(doc.id)) { 
              var rawPrice = doc['price'];
              int price = 0;
              if (rawPrice is String) { 
                price = int.tryParse(rawPrice.replaceAll(',', '')) ?? 0; 
              } else if (rawPrice is num) { 
                price = rawPrice.toInt(); 
              }
              int quantity = (doc['quantity'] as num).toInt();
              total += (price * quantity);
            }
          }
          int deliveryCharge = 20; 
          int grandTotal = total + deliveryCharge;

          return Column(
            children: [
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
                        children: [
                          // ৩. চেক বক্স সিলেকশন (ডিলিট করার জন্য)
                          Checkbox(
                            value: selectedItems.contains(cartItem.id),
                            activeColor: Colors.deepOrange,
                            onChanged: (val) {
                              setState(() {
                                val! ? selectedItems.add(cartItem.id) : selectedItems.remove(cartItem.id);
                              });
                            },
                          ),
                          Container(
                            height: 60, width: 60,
                            decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(10)),
                            child: imageUrl.isNotEmpty
                                ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(imageUrl, fit: BoxFit.cover))
                                : const Icon(Icons.checkroom, color: Colors.blue),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cartItem['product_name'], style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 5),
                                Text('৳${cartItem['price']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                                // কাস্টমারের সিলেক্ট করা কালার ও সাইজ দেখানো
                                if (data.containsKey('selected_color') && data['selected_color'].toString().isNotEmpty)
                                  Text('Color: ${data['selected_color']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                if (data.containsKey('selected_size') && data['selected_size'].toString().isNotEmpty)
                                  Text('Size: ${data['selected_size']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                // স্টক ওয়ার্নিং (ডায়নামিক স্টক চেক)
                                if (data.containsKey('max_stock') && (data['max_stock'] as num).toInt() < 10)
                                  Text('Only ${data['max_stock']} items left!', style: const TextStyle(fontSize: 11, color: Colors.red, fontStyle: FontStyle.italic)),
                              ],
                            ),
                          ),
                          // ৪. প্লাস-মাইনাস বাটন দিয়ে রিয়েল-টাইম আপডেট
                          Row(
                            children: [
                              InkWell(
                                onTap: () {
                                  if (cartItem['quantity'] > 1) {
                                    FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).update({'quantity': FieldValue.increment(-1)});
                                  }
                                },
                                child: Container(decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)), child: const Icon(Icons.remove, size: 20)),
                              ),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 10), child: Text('${cartItem['quantity']}', style: const TextStyle(fontWeight: FontWeight.bold))),
                              InkWell(
                                onTap: () {
                                  FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).update({'quantity': FieldValue.increment(1)});
                                },
                                child: Container(decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(5)), child: const Icon(Icons.add, size: 20, color: Colors.deepOrange)),
                              ),
                            ],
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () { FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(cartItem.id).delete(); },
                            child: const Icon(Icons.cancel_outlined, color: Colors.grey),
                          )
                        ],
                      ),
                    );
                  },
                ),
              ),
              // ওর্ডার সামারি সেকশন (তোমার আগের ডিজাইন অনুযায়ী)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.amber[100], borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('ORDER SUMMARY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Subtotal'), Text('৳$total', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    const SizedBox(height: 5),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Delivery Charge'), Text('৳$deliveryCharge', style: const TextStyle(fontWeight: FontWeight.bold))]),
                    const Divider(thickness: 1, height: 20),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)), Text('৳$grandTotal', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity, height: 50,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                        onPressed: () { Navigator.push(context, MaterialPageRoute(builder: (context) => CheckoutPage(grandTotal: grandTotal))); },
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
// ৫ নম্বর পেজ: Checkout & Payment Method
// ==========================================
class CheckoutPage extends StatefulWidget {
  final int grandTotal; 
  const CheckoutPage({super.key, required this.grandTotal});
  @override State<CheckoutPage> createState() => _CheckoutPageState();
}
class _CheckoutPageState extends State<CheckoutPage> {
  String selectedPayment = 'Cash on Delivery';
  void confirmOrder() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      var cartSnapshot = await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').get();
      List<Map<String, dynamic>> items =[];
      for (var doc in cartSnapshot.docs) { items.add({'product_name': doc['product_name'], 'price': doc['price'], 'quantity': doc['quantity']}); }
      await FirebaseFirestore.instance.collection('orders').add({'user_id': user.uid, 'items': items, 'total_amount': widget.grandTotal, 'payment_method': selectedPayment, 'status': 'Pending', 'order_date': FieldValue.serverTimestamp(), 'shipping_address': 'Rahim Ahmed, H-12, R-15, Sec-7, Uttara, Dhaka'});
      for (var doc in cartSnapshot.docs) { await FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart').doc(doc.id).delete(); }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Placed Successfully! 🎉')));
      Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const MainScreen()), (route) => false);
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'))); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.teal[50], 
      appBar: AppBar(backgroundColor: Colors.teal[400], elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white), onPressed: () => Navigator.pop(context)), title: const Text('PAYMENT METHOD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          Container(decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(children:[_buildPaymentOption('Credit/Debit Card', Icons.credit_card, Colors.blue), const Divider(height: 1), _buildPaymentOption('bKash', Icons.account_balance_wallet, Colors.pink), const Divider(height: 1), _buildPaymentOption('Nagad', Icons.account_balance_wallet_outlined, Colors.orange), const Divider(height: 1), _buildPaymentOption('Cash on Delivery', Icons.local_shipping, Colors.teal)])),
          const SizedBox(height: 30),
          const Text('SELECTED ADDRESS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), const SizedBox(height: 10),
          Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Rahim Ahmed', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), SizedBox(height: 5), Text('H-12, R-15, Sec-7,\nUttara, Dhaka', style: TextStyle(color: Colors.grey, fontSize: 14))])),
          const SizedBox(height: 30),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children:[const Text('Order Total + Delivery', style: TextStyle(fontSize: 16)), Text('৳${widget.grandTotal}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
          const SizedBox(height: 10),
          Row(children: const[Icon(Icons.lock, size: 16, color: Colors.grey), SizedBox(width: 5), Text('Secure Payment', style: TextStyle(color: Colors.grey))]),
          const SizedBox(height: 30),
          SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal[400], shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: confirmOrder, child: const Text('CONFIRM PAYMENT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))
        ]),
      ),
    );
  }
  Widget _buildPaymentOption(String title, IconData icon, Color iconColor) {
    return RadioListTile<String>(title: Row(children:[Icon(icon, color: iconColor), const SizedBox(width: 15), Text(title, style: const TextStyle(fontWeight: FontWeight.bold))]), value: title, groupValue: selectedPayment, activeColor: Colors.deepOrange, onChanged: (value) => setState(() => selectedPayment = value!));
  }
}

// ==========================================
// ৩ নম্বর পেজ: Product Details (Dynamic Pricing based on Variants)
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

  void runAddToCartAnimation(String imageUrl) {
    // আগের মতই এনিমেশন কোড...
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
            return Positioned(left: left, top: top, child: Opacity(opacity: 1.0 - (value * 0.3), child: ClipRRect(borderRadius: BorderRadius.circular(100), child: Image.network(imageUrl, width: size, height: size, fit: BoxFit.cover))));
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

    if (!isBuyNow) runAddToCartAnimation(imageUrl);

    var cartRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('cart');
    // একই প্রোডাক্ট, একই কালার এবং একই সাইজ কিনা তা চেক করা
    var existingItem = await cartRef
        .where('product_name', isEqualTo: widget.product['product_name'])
        .where('selected_color', isEqualTo: selectedColor?['name'] ?? '')
        .where('selected_size', isEqualTo: selectedSize?['name'] ?? '')
        .get();

    if (existingItem.docs.isNotEmpty) {
      await cartRef.doc(existingItem.docs.first.id).update({'quantity': FieldValue.increment(1)});
    } else {
      await cartRef.add({
        'product_name': widget.product['product_name'],
        'price': finalPrice, // ক্যালকুলেট করা ফাইনাল দাম
        'quantity': 1,
        'image_url': imageUrl,
        'selected_color': selectedColor?['name'] ?? '',
        'selected_size': selectedSize?['name'] ?? '',
        'max_stock': maxStock, // কার্টে স্টক ওয়ার্নিং দেখানোর জন্য
        'added_at': FieldValue.serverTimestamp(),
      });
    }
    if (!mounted) return;
    if (isBuyNow) { Navigator.push(context, MaterialPageRoute(builder: (context) => const CartPage())); } 
    else { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Item flying to Cart! 🚀'), duration: Duration(seconds: 1))); }
  }

  // কাস্টমার কোনো প্রোডাক্ট দেখলে তা ফায়ারবেসে 'recently_viewed' এ সেভ করে রাখা
  void _saveToRecentlyViewed() async {
    User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    var recentRef = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('recently_viewed');
    
    // প্রোডাক্টটি আগে থেকেই দেখা থাকলে তার সময় আপডেট করা, নাহলে নতুন করে সেভ করা
    await recentRef.doc(widget.product.id).set({
      'product_id': widget.product.id,
      'category': widget.product['category'],
      'viewed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  void initState() {
    super.initState();
    // পেজ ওপেন হওয়ার সাথে সাথেই এটি 'Recently Viewed' হিসেবে সেভ হয়ে যাবে
    _saveToRecentlyViewed(); 
  }

  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> data = widget.product.data() as Map<String, dynamic>;
    List<dynamic> images = data.containsKey('image_urls') ? data['image_urls'] :[];
    List<dynamic> colors = data.containsKey('colors') ? data['colors'] :[];
    List<dynamic> sizes = data.containsKey('sizes') ? data['sizes'] :[];
    String mainImage = images.isNotEmpty && images.length > _selectedImageIndex ? images[_selectedImageIndex] : '';
    
    // প্রাইস ক্যালকুলেশন লজিক
    int basePrice = int.tryParse(data['price'].toString()) ?? 0;
    int originalPrice = int.tryParse(data.containsKey('original_price') ? data['original_price'].toString() : '0') ?? 0;
    int stock = int.tryParse(data['stock'].toString()) ?? 0;
    
    // ভেরিয়েন্ট সিলেক্ট করলে অতিরিক্ত দাম যোগ হবে
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
          // উইশলিস্ট (হার্ট) বাটন (Magic Logic)
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('users').doc(FirebaseAuth.instance.currentUser!.uid).collection('wishlist').doc(widget.product.id).snapshots(),
            builder: (context, snapshot) {
              bool isWished = snapshot.hasData && snapshot.data!.exists;
              return IconButton(
                icon: Icon(isWished ? Icons.favorite : Icons.favorite_border, color: isWished ? Colors.red : Colors.black),
                onPressed: () async {
                  User? user = FirebaseAuth.instance.currentUser;
                  if (user == null) return;
                  
                  var ref = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('wishlist').doc(widget.product.id);
                  if (isWished) {
                    await ref.delete();
                    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Removed from Wishlist 💔')));
                  } else {
                    // প্রোডাক্টের পুরো ডাটা উইশলিস্টে সেভ করে রাখছি
                    await ref.set(widget.product.data() as Map<String, dynamic>); 
                    if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to Wishlist ❤️')));
                  }
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

                  // ডায়নামিক কালার এবং সাইজ সিলেকশন
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                  decoration: BoxDecoration(color: isSelected ? Colors.deepOrange.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.deepOrange : Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), 
                                  child: Text('${c['name']} ${extra > 0 ? '(+৳$extra)' : ''}', style: TextStyle(color: isSelected ? Colors.deepOrange : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))
                                )
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
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), 
                                  decoration: BoxDecoration(color: isSelected ? Colors.teal.shade50 : Colors.white, border: Border.all(color: isSelected ? Colors.teal : Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), 
                                  child: Text('${s['name']} ${extra > 0 ? '(+৳$extra)' : ''}', style: TextStyle(color: isSelected ? Colors.teal : Colors.black, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal))
                                )
                              );
                            }).toList()
                          ), 
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // সেলার শপ ডিটেইলস
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

                  // ডেসক্রিপশন বক্স
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

                  // রেকমেন্ডেড প্রডাক্ট সেকশন
                  Container(
                    color: Colors.white, padding: const EdgeInsets.symmetric(vertical: 15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:[
                        const Padding(padding: EdgeInsets.symmetric(horizontal: 15), child: Text('You May Also Like', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))), const SizedBox(height: 10),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('products').where('status', isEqualTo: 'approved').where('category', isEqualTo: data['category']).limit(6).snapshots(),
                          builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const SizedBox();
                            var recDocs = snapshot.data!.docs.where((d) => d.id != widget.product.id).toList();
                            if (recDocs.isEmpty) return const Padding(padding: EdgeInsets.all(15.0), child: Text('No recommendations yet.', style: TextStyle(color: Colors.grey)));
                            return SizedBox(height: 200, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), itemCount: recDocs.length, itemBuilder: (context, index) {
                                  var recData = recDocs[index].data() as Map<String, dynamic>; String img = (recData.containsKey('image_urls') && (recData['image_urls'] as List).isNotEmpty) ? recData['image_urls'][0] : '';
                                  return InkWell(onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => ProductDetailsPage(product: recDocs[index]))), child: Container(width: 140, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[Expanded(child: Container(width: double.infinity, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(10))), child: img.isNotEmpty ? ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(10)), child: Image.network(img, fit: BoxFit.cover)) : const Icon(Icons.image))), Padding(padding: const EdgeInsets.all(8.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(recData['product_name'], maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)), const SizedBox(height: 4), Text('৳${recData['price']}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold))]))])));
                                }));
                          }
                        )
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
                          // ব্যানার সেকশন
                          StreamBuilder(
                            stream: FirebaseFirestore.instance.collection('banners').snapshots(),
                            builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                              if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                                return SizedBox(height: 140, child: PageView.builder(itemCount: snapshot.data!.docs.length, itemBuilder: (context, index) { return Container(margin: const EdgeInsets.all(15), decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), image: DecorationImage(image: NetworkImage(snapshot.data!.docs[index]['image_url']), fit: BoxFit.cover))); }));
                              }
                              return Container(margin: const EdgeInsets.all(15), height: 120, decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), gradient: LinearGradient(colors:[Colors.orange.shade200, Colors.deepOrange.shade100])), child: Row(children:[const Padding(padding: EdgeInsets.all(15.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children:[Text('FESTIVE OFFER!', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)), Text('UP TO 20% OFF', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)), SizedBox(height: 5), Text('Explore Now >', style: TextStyle(color: Colors.deepOrange, fontSize: 12, fontWeight: FontWeight.bold))])), const Spacer(), const Icon(Icons.card_giftcard, size: 80, color: Colors.redAccent), const SizedBox(width: 20)]));
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
// লগিন ও সাইন আপ পেজ
// ==========================================
class LoginPage extends StatefulWidget { const LoginPage({super.key}); @override State<LoginPage> createState() => _LoginPageState(); }
class _LoginPageState extends State<LoginPage> {
  final TextEditingController emailController = TextEditingController(); final TextEditingController passwordController = TextEditingController();
  void login() async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(), 
        password: passwordController.text.trim()
      );
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).get();
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login Successful!')));
      
      String role = userDoc['role'];
      // রোল অনুযায়ী সঠিক পেজে পাঠানো হচ্ছে
      if (role == 'admin') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AdminMainScreen()));
      } else if (role == 'seller') {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SellerMainScreen()));
      } else if (role == 'rider') { // <--- রাইডার যুক্ত করা হলো
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const RiderMainScreen()));
      } else {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
    }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(backgroundColor: Colors.orange[50], body: Center(child: Padding(padding: const EdgeInsets.all(20.0), child: Column(mainAxisAlignment: MainAxisAlignment.center, children:[const Icon(Icons.shopping_cart_checkout, size: 80, color: Colors.deepOrange), const SizedBox(height: 20), const Text('Welcome to D Shop', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.deepOrange)), const SizedBox(height: 40), TextField(controller: emailController, decoration: InputDecoration(labelText: 'Email', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white)), const SizedBox(height: 15), TextField(controller: passwordController, obscureText: true, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)), filled: true, fillColor: Colors.white)), const SizedBox(height: 30), SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: login, child: const Text('LOGIN', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)))), const SizedBox(height: 20), TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const SignupPage())), child: const Text("Don't have an account? Sign Up", style: TextStyle(color: Colors.deepOrange, fontSize: 16)))]))));
  }
}

class SignupPage extends StatefulWidget { const SignupPage({super.key}); @override State<SignupPage> createState() => _SignupPageState(); }
class _SignupPageState extends State<SignupPage> {
  final TextEditingController nameController = TextEditingController(); final TextEditingController emailController = TextEditingController(); final TextEditingController passwordController = TextEditingController();
  void createAccount() async {
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: emailController.text.trim(), password: passwordController.text.trim());
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({'name': nameController.text.trim(), 'email': emailController.text.trim(), 'role': 'customer', 'created_at': FieldValue.serverTimestamp()});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Created Successfully!')));
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}'))); }
  }
  @override Widget build(BuildContext context) {
    return Scaffold(appBar: AppBar(title: const Text('Create Account'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white), body: Padding(padding: const EdgeInsets.all(20.0), child: Column(children:[TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Full Name', border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: emailController, decoration: const InputDecoration(labelText: 'Email Address', border: OutlineInputBorder())), const SizedBox(height: 15), TextField(controller: passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 6 chars)', border: OutlineInputBorder())), const SizedBox(height: 30), SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green), onPressed: createAccount, child: const Text('SIGN UP', style: TextStyle(color: Colors.white, fontSize: 18))))])));
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
                Navigator.pop(context); // মেনু বন্ধ করবে
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Notification system coming soon!')));
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
                // আমরা আগে যেই ব্যানার পেজ বানিয়েছিলাম সেখানে নিয়ে যাবে
                Navigator.push(context, MaterialPageRoute(builder: (context) => const AdminBannerUploadPage()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.motorcycle, color: Colors.purple),
              title: const Text('Manage Riders', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider management coming soon!')));
              },
            ),
            ListTile(
              leading: const Icon(Icons.map, color: Colors.green),
              title: const Text('Delivery Zones & Charges', style: TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Zone setting coming soon!')));
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
// অ্যাডমিন পেজ ২: User & Seller Management
// ==========================================
class AdminUserManagement extends StatelessWidget {
  const AdminUserManagement({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.orange[200], title: const Text('Management Hub', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)), iconTheme: const IconThemeData(color: Colors.black)),
      body: Column(
        children:[
          Padding(padding: const EdgeInsets.all(15), child: Row(mainAxisAlignment: MainAxisAlignment.center, children:[ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black), child: const Text('Users')), const SizedBox(width: 10), ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.black), child: const Text('Sellers'))])),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              itemCount: 4,
              itemBuilder: (context, index) {
                return Card(
                  margin: const EdgeInsets.only(bottom: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  child: Padding(
                    padding: const EdgeInsets.all(15.0),
                    child: Column(
                      children:[
                        Row(
                          children:[
                            Container(width: 50, height: 50, decoration: BoxDecoration(color: Colors.red[100], borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.store, color: Colors.red)),
                            const SizedBox(width: 15),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const[Text('Shop Name', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), Text('Status: Pending', style: TextStyle(color: Colors.grey))])),
                            ElevatedButton(onPressed: (){}, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), child: const Text('Verify', style: TextStyle(color: Colors.white))),
                          ],
                        ),
                        const Divider(),
                        Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: const[Text('Manage Products', style: TextStyle(color: Colors.blue)), Text('View Sales', style: TextStyle(color: Colors.blue))])
                      ],
                    ),
                  ),
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
// Admin Banner Upload Page (Firebase Storage)
// ==========================================
class AdminBannerUploadPage extends StatefulWidget {
  const AdminBannerUploadPage({super.key});
  @override
  State<AdminBannerUploadPage> createState() => _AdminBannerUploadPageState();
}

class _AdminBannerUploadPageState extends State<AdminBannerUploadPage> {
  final ImagePicker _picker = ImagePicker();

  Future<void> uploadBanner() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      String fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
      Reference ref = FirebaseStorage.instance.ref().child('banners').child(fileName);
      
      if (kIsWeb) {
        Uint8List bytes = await image.readAsBytes();
        await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      } else {
        await ref.putFile(File(image.path));
      }
      
      String downloadUrl = await ref.getDownloadURL();

      await FirebaseFirestore.instance.collection('banners').add({
        'image_url': downloadUrl,
        'uploaded_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Banner Uploaded Successfully! 🎉')));
    } catch (e) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manage Banners'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Column(
        children:[
          Padding(
            padding: const EdgeInsets.all(15.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, minimumSize: const Size(double.infinity, 50)),
              onPressed: uploadBanner, 
              icon: const Icon(Icons.add_photo_alternate, color: Colors.white), 
              label: const Text('Upload New Banner', style: TextStyle(color: Colors.white, fontSize: 16))
            ),
          ),
          const Expanded(
            child: BannerList(),
          ),
        ],
      ),
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