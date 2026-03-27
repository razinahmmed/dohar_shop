import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';

// আমাদের নিজেদের ফাইলগুলোর লিংক (যাতে এক পেজ থেকে অন্য পেজে যাওয়া যায়)
import 'auth_screens.dart';
import 'customer_screens.dart';
import 'package:dohar_shop/notification_service.dart';


// ==========================================
// সেলার মেইন স্ক্রিন (Bottom Nav With Badges & Auto-Navigation)
// ==========================================
class SellerMainScreen extends StatefulWidget {
  final int initialPage; // নোটিফিকেশন থেকে নির্দিষ্ট পেজে যাওয়ার জন্য
  const SellerMainScreen({super.key, this.initialPage = 0});

  @override
  State<SellerMainScreen> createState() => _SellerMainScreenState();
}

class _SellerMainScreenState extends State<SellerMainScreen> {
  late int _selectedIndex;

  // সেলারের ৫টি মূল পেজ
  final List<Widget> _pages = [
    const SellerDashboard(),         // ইনডেক্স ০: Stats
    const ProductManagement(),      // ইনডেক্স ১: Products
    const SellerOrderManagement(),   // ইনডেক্স ২: Orders (To Pack)
    const PaymentsReports(),        // ইনডেক্স ৩: Reports
    const SellerProfile(),           // ইনডেক্স ৪: Profile
  ];

  @override
  void initState() {
    super.initState();
    // অ্যাপ ওপেন হওয়ার সময় ইনডেক্স সেট করা (ডিফল্ট ০, নোটিফিকেশন থেকে আসলে ২)
    _selectedIndex = widget.initialPage;
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        int actionNeeded = 0;

        // শুধু সেই অর্ডারগুলো গুনবে যেগুলো 'Processing' অবস্থায় আছে এবং এই সেলারের প্রোডাক্ট আছে
        if (snapshot.hasData) {
          for (var doc in snapshot.data!.docs) {
            var data = doc.data() as Map<String, dynamic>;
            if (data['status'] == 'Processing') { // সেলার শুধু প্যাক করার অর্ডারগুলো দেখবে
              List items = data['items'] ?? [];
              if (items.any((item) => item['seller_id'] == currentUser?.uid)) {
                actionNeeded++;
              }
            }
          }
        }

        return Scaffold(
          body: _pages[_selectedIndex],
          bottomNavigationBar: BottomNavigationBar(
            type: BottomNavigationBarType.fixed,
            currentIndex: _selectedIndex,
            selectedItemColor: Colors.deepOrange,
            unselectedItemColor: Colors.grey,
            onTap: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.dashboard_outlined),
                label: 'Stats',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.inventory_2_outlined),
                label: 'Products',
              ),
              BottomNavigationBarItem(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.shopping_bag_outlined),
                    if (actionNeeded > 0)
                      Positioned(
                        right: -6,
                        top: -6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            '$actionNeeded',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                label: 'Orders',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.analytics_outlined),
                label: 'Reports',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.store_mall_directory_outlined),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
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
  String _selectedFilter = 'Top Sales'; // 🔴 ডিফল্ট ফিল্টার পরিবর্তন করা হলো

  @override 
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return const Center(child: Text('Please login'));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.deepOrange, 
        title: const Text('D Shop Seller', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), 
        actions:[
          IconButton(
            icon: const Icon(Icons.notifications_active, color: Colors.white), 
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CustomerNotificationPage()))
          )
        ]
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
                
                String shopName = data['shop_name']?.toString() ?? data['name']?.toString() ?? 'Seller';
                if (shopName.isEmpty || shopName == 'null') shopName = 'Seller';
                
                String profileImg = data['profile_image_url']?.toString() ?? '';

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

            // Stats & Quick Actions
            const Text('Overall Performance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 15),
            
            // 🔴 রিয়েল ডাটা ক্যালকুলেশন
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('orders').snapshots(),
              builder: (context, snapshot) {
                double todaySales = 0;
                int activeOrders = 0;

                if (snapshot.hasData) {
                  DateTime now = DateTime.now();
                  
                  for (var doc in snapshot.data!.docs) {
                    var data = doc.data() as Map<String, dynamic>;
                    String status = data['status'] ?? 'Pending';
                    List items = data['items'] ?? [];

                    bool isMyOrder = false;
                    double myOrderTotal = 0;

                    for (var item in items) {
                      if (item['seller_id'] == currentUser.uid) {
                        isMyOrder = true;
                        myOrderTotal += (double.tryParse(item['price'].toString()) ?? 0) * (int.tryParse(item['quantity'].toString()) ?? 1);
                      }
                    }

                    if (isMyOrder) {
                      // ১. অ্যাক্টিভ অর্ডার কাউন্ট (ডেলিভারড, ক্যান্সেল বা ফেইল বাদে বাকি সবই রানিং অর্ডার)
                      if (['Pending', 'Processing', 'Ready to Ship', 'Dispatched', 'In-Transit'].contains(status)) {
                        activeOrders++;
                      }

                      // ২. আজকের মোট সেলস (ক্যান্সেল বা ফেইল হওয়া বাদে)
                      if (data['order_date'] != null && status != 'Cancelled' && status != 'Delivery Failed') {
                        DateTime orderDate = (data['order_date'] as Timestamp).toDate();
                        if (orderDate.year == now.year && orderDate.month == now.month && orderDate.day == now.day) {
                          todaySales += myOrderTotal;
                        }
                      }
                    }
                  }
                }

                return Row(
                  children:[
                    _buildStatCard("Today's Sales", "৳${todaySales.toStringAsFixed(0)}", Colors.teal[50]!, Colors.teal), 
                    const SizedBox(width: 15), 
                    _buildStatCard("Active Orders", "$activeOrders", Colors.orange[50]!, Colors.orange)
                  ]
                );
              }
            ),
            const SizedBox(height: 25),
            
            const Text('QUICK ACTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), 
            const SizedBox(height: 10),
            Row(
              children:[
                _buildQuickAction(Icons.add_circle_outline, "Add Product", Colors.teal, () => Navigator.push(context, MaterialPageRoute(builder: (context) => const AddProductPage()))), 
                const SizedBox(width: 15), 
              ]
            ),
            
            const SizedBox(height: 30),
            const Divider(height: 1, thickness: 1),
            const SizedBox(height: 20),

            // Product Insights / Overview
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

                if (_selectedFilter == 'Low Stock') {
                  displayList = allProducts.where((doc) {
                    int stock = int.tryParse((doc.data() as Map<String, dynamic>)['stock'].toString()) ?? 0;
                    return stock <= 5; 
                  }).toList();
                } 
                else if (_selectedFilter == 'Top Sales') {
                  displayList = allProducts.toList();
                  displayList.sort((a, b) {
                    int salesA = (a.data() as Map<String, dynamic>)['sales_count'] ?? 0;
                    int salesB = (b.data() as Map<String, dynamic>)['sales_count'] ?? 0;
                    return salesB.compareTo(salesA); 
                  });
                } 
                else if (_selectedFilter == 'Newest') {
                  displayList = allProducts.toList();
                  displayList.sort((a, b) {
                    Timestamp? tA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    Timestamp? tB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    if (tA == null || tB == null) return 0;
                    return tB.compareTo(tA); 
                  });
                }

                if (displayList.isEmpty) {
                  return Container(
                    width: double.infinity, padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                    child: Text(_selectedFilter == 'Low Stock' ? 'Great! All products have sufficient stock. 🎉' : 'No data available for this filter.', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                  );
                }

                return ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(), 
                  itemCount: displayList.length > 5 ? 5 : displayList.length, 
                  itemBuilder: (context, index) {
                    var doc = displayList[index];
                    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
                    
                    // ===========================================
                    // [SUPER SAFE FIX] Null string prevention (যেটা আপনি খুঁজছিলেন)
                    // ===========================================
                    String firstImage = '';
                    var urls = data['image_urls'];
                    if (urls != null && urls is List && urls.isNotEmpty) {
                      firstImage = urls[0]?.toString() ?? '';
                    }
                    // ===========================================
                    
                    int stock = int.tryParse(data['stock']?.toString() ?? '0') ?? 0;
                    int sales = data['sales_count'] ?? 0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        // 🔴 ক্লিক করলেই এডিট পেজে নিয়ে যাবে
                        onTap: () {
                           Navigator.push(context, MaterialPageRoute(builder: (context) => EditProductPage(productId: doc.id, productData: data)));
                        },
                        leading: Container(
                          width: 50, height: 50, 
                          decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)), 
                          child: firstImage.isNotEmpty ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(firstImage, fit: BoxFit.cover)) : const Icon(Icons.image, color: Colors.grey)
                        ),
                        title: Text(data['product_name']?.toString() ?? 'Product', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text('৳${data['price'] ?? 0}', style: const TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold)),
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

  Widget _buildStatCard(String title, String value, Color bgColor, Color textColor) {
    return Expanded(child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(15)), child: Column(children:[Text(title, style: const TextStyle(fontSize: 14)), const SizedBox(height: 5), Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: textColor))]))); 
  }
  
  Widget _buildQuickAction(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(child: InkWell(onTap: onTap, child: Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: color.withOpacity(0.3))), child: Column(children:[Icon(icon, color: color, size: 30), const SizedBox(height: 5), Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: color))]))));
  }
}

// ==========================================
// সেলার প্রোডাক্ট ম্যানেজমেন্ট: (Fixed Null Crash 100%)
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
              stream: FirebaseFirestore.instance.collection('products').where('seller_id', isEqualTo: currentUser?.uid).snapshots(),
              builder: (context, AsyncSnapshot<QuerySnapshot> snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('You have not uploaded any products yet.'));

                List<QueryDocumentSnapshot> docs = snapshot.data!.docs.toList();
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
                    
                    //[SUPER SAFE FIX]
                    String firstImage = '';
                    var urls = data['image_urls'];
                    if (urls != null && urls is List && urls.isNotEmpty) {
                      firstImage = urls[0]?.toString() ?? '';
                    }
                    
                    String status = data['status']?.toString() ?? 'pending';
                    bool isActive = data['is_active'] ?? true;

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
                                  Text(data['product_name']?.toString() ?? 'Product Name', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 2, overflow: TextOverflow.ellipsis), 
                                  const SizedBox(height: 5),
                                  Text('Price: ৳${data['price'] ?? 0} | Stock: ${data['stock'] ?? 0}'),
                                  const SizedBox(height: 5),
                                  Row(
                                    children:[
                                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: status == 'approved' ? Colors.green.shade50 : (status == 'rejected' ? Colors.red.shade50 : Colors.orange.shade50), borderRadius: BorderRadius.circular(5)), child: Text(status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: status == 'approved' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange)))),
                                      const SizedBox(width: 10),
                                      if (!isActive) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(5)), child: const Text('HIDDEN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey))),
                                    ],
                                  )
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  Navigator.push(context, MaterialPageRoute(builder: (context) => EditProductPage(productId: doc.id, productData: data)));
                                } else if (value == 'toggle_visibility') { doc.reference.update({'is_active': !isActive}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isActive ? 'Product hidden!' : 'Product visible!'))); }
                                else if (value == 'delete') { 
                                  // Soft Delete: ডাটাবেস থেকে মুছবে না, শুধু হাইড করে দিবে
                                  doc.reference.update({'status': 'deleted', 'is_active': false}); 
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Product removed from shop!'), backgroundColor: Colors.red)); 
                                }
                              },
                              itemBuilder: (context) =>[
                                const PopupMenuItem(value: 'edit', child: Row(children:[Icon(Icons.edit, color: Colors.blue, size: 20), SizedBox(width: 10), Text('Edit Product')])),
                                PopupMenuItem(value: 'toggle_visibility', child: Row(children:[Icon(isActive ? Icons.visibility_off : Icons.visibility, color: Colors.grey, size: 20), SizedBox(width: 10), Text(isActive ? 'Hide' : 'Show')])),
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
  List<dynamic> existingImageUrls = [];
  List<Map<String, dynamic>> variantMatrix = [];
  
  // ডিফল্টভাবে শুধু স্টক এডিট অন থাকবে
  bool isStockUpdateOnly = true; 
  bool hasRealVariants = false; // ভেরিয়েন্ট আছে কি না চেক করার জন্য

  @override
  void initState() {
    super.initState();
    var data = widget.productData;
    
    nameController = TextEditingController(text: data['product_name']?.toString() ?? '');
    priceController = TextEditingController(text: (data['price'] ?? 0).toString());
    originalPriceController = TextEditingController(text: (data['original_price'] ?? data['price'] ?? 0).toString());
    stockController = TextEditingController(text: (data['stock'] ?? 0).toString());
    descController = TextEditingController(text: data['description']?.toString() ?? '');
    unitController = TextEditingController(text: data['variant_unit']?.toString() ?? 'Unit');
    selectedCategory = data['category']?.toString();
    
    if (data['image_urls'] != null && data['image_urls'] is List) {
      existingImageUrls = List<dynamic>.from(data['image_urls']);
    }
    
    if (data['variants'] != null && data['variants'] is List) {
      try {
        variantMatrix = List<Map<String, dynamic>>.from(
          (data['variants'] as List).map((x) => Map<String, dynamic>.from(x))
        );
      } catch (e) {
        variantMatrix = [];
      }
    }

    // চেক করা হচ্ছে আসল ভেরিয়েন্ট আছে কিনা
    if (variantMatrix.length > 1 || (variantMatrix.isNotEmpty && (variantMatrix[0]['color'] != 'Default' || variantMatrix[0]['size'] != 'Default'))) {
      hasRealVariants = true;
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

    // যদি ভেরিয়েন্ট না থাকে, তবে মেইন স্টকের ডাটা ভেরিয়েন্ট ম্যাট্রিক্সেও আপডেট করে দিতে হবে
    if (!hasRealVariants && variantMatrix.isNotEmpty) {
      variantMatrix[0]['stock'] = int.tryParse(stockController.text.trim()) ?? 0;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      Map<String, dynamic> updateData = {};

      if (isStockUpdateOnly) {
        updateData = {
          'stock': int.tryParse(stockController.text.trim()) ?? 0,
          'variants': variantMatrix,
          'updated_at': FieldValue.serverTimestamp(),
        };
      } else {
        updateData = {
          'product_name': nameController.text.trim(),
          'price': int.tryParse(priceController.text.trim()) ?? 0,
          'original_price': int.tryParse(originalPriceController.text.trim()) ?? 0,
          'stock': int.tryParse(stockController.text.trim()) ?? 0,
          'description': descController.text.trim(),
          'category': selectedCategory,
          'variant_unit': unitController.text.trim(),
          'variants': variantMatrix,
          'status': 'pending', 
          'updated_at': FieldValue.serverTimestamp(),
        };
      }

      await FirebaseFirestore.instance.collection('products').doc(widget.productId).update(updateData);

      if (!isStockUpdateOnly) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'title': 'Product Updated 📦',
          'message': 'সেলার "${nameController.text.trim()}" এডিট করেছেন। এপ্রুভ করুন।',
          'topic': 'admins',
          'sent_at': FieldValue.serverTimestamp(),
        });
      }

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // Loader close
      Navigator.pop(context); // Go back
      
      String msg = isStockUpdateOnly ? 'Stock updated instantly! ⚡' : 'Product updated and sent for approval! ⏳';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: isStockUpdateOnly ? Colors.green : Colors.blue));

    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
            
            // 🟢 কুইক স্টক আপডেট মোড অন থাকলে শুধু এটি দেখাবে
            if (isStockUpdateOnly) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [Icon(Icons.flash_on, color: Colors.green), SizedBox(width: 5), Text('Quick Stock Update', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16))]),
                    const SizedBox(height: 5),
                    const Text('এই মোডে প্রোডাক্টের স্ট্যাটাস পেন্ডিং হবে না, সাথে সাথেই অ্যাপে আপডেট হয়ে যাবে।', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    const SizedBox(height: 15),
                    Text('Product: ${nameController.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 15),

                    if (!hasRealVariants)
                      TextField(
                        controller: stockController, 
                        keyboardType: TextInputType.number, 
                        decoration: const InputDecoration(labelText: 'Total Stock', border: OutlineInputBorder(), fillColor: Colors.white, filled: true)
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(10), color: Colors.white),
                        child: ListView.builder(
                          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                          itemCount: variantMatrix.length,
                          itemBuilder: (context, index) {
                            var item = variantMatrix[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                children:[
                                  Expanded(flex: 2, child: Text('${item['color']} - ${item['size']} ${unitController.text}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))),
                                  const SizedBox(width: 10),
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
                                ],
                              ),
                            );
                          }
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  onPressed: _updateProduct, 
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: const Text('INSTANT UPDATE STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                ),
              ),
              const SizedBox(height: 40),
              const Center(child: Text('Want to change Name, Price or Description?', style: TextStyle(color: Colors.grey))),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity, height: 45,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.blue), foregroundColor: Colors.blue),
                  onPressed: () => setState(() => isStockUpdateOnly = false), 
                  icon: const Icon(Icons.edit),
                  label: const Text('Unlock Full Edit Mode (Requires Approval)')
                ),
              ),
            ] 
            
            // 🔴 ফুল এডিট মোড (আপলোড পেজের মতো)
            else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                child: const Row(children: [Icon(Icons.warning, color: Colors.red), SizedBox(width: 10), Expanded(child: Text('Full Edit Mode: Updating this will send the product to Admin for approval again.', style: TextStyle(color: Colors.red, fontSize: 12)))]),
              ),
              const SizedBox(height: 20),
              
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

              Builder(
                builder: (context) {
                  List<String> catList = ['Fashion', 'Electronics', 'Mobiles', 'Home Decor', 'Beauty', 'Watches', 'Baby & Toys', 'Groceries', 'Automotive', 'Women\'s Bags', 'Men\'s Wallets', 'Muslim Fashion', 'Games & Hobbies', 'Computers', 'Sports & Outdoor', 'Men Shoes', 'Cameras', 'Travel & Luggage'];
                  if (selectedCategory != null && !catList.contains(selectedCategory)) catList.add(selectedCategory!);
                  return DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Category', border: OutlineInputBorder()),
                    initialValue: selectedCategory,
                    items: catList.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))).toList(),
                    onChanged: (val) => setState(() => selectedCategory = val),
                  );
                }
              ),
              const SizedBox(height: 15),

              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name', border: OutlineInputBorder())),
              const SizedBox(height: 15),
              
              Row(
                children:[
                  Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base Price (৳)', border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: originalPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Original Price (৳)', border: OutlineInputBorder()))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: stockController, readOnly: hasRealVariants, decoration: InputDecoration(labelText: 'Total Stock', filled: hasRealVariants, fillColor: Colors.grey.shade100, border: const OutlineInputBorder()))),
                ],
              ),
              const SizedBox(height: 20),
              
              if (hasRealVariants) ...[
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
                                enabled: !isFirst,
                                decoration: InputDecoration(labelText: '+ Price', isDense: true, filled: isFirst, border: const OutlineInputBorder()),
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
              ],

              TextField(controller: descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())),
              const SizedBox(height: 40),
              
              SizedBox(
                width: double.infinity, height: 50,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: _updateProduct, 
                  icon: const Icon(Icons.send, color: Colors.white),
                  label: const Text('UPDATE & REQUEST APPROVAL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                ),
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () => setState(() => isStockUpdateOnly = true), 
                  child: const Text('Cancel & Go Back to Quick Stock', style: TextStyle(color: Colors.grey))
                ),
              )
            ]
          ],
        ),
      ),
    );
  }
}


// ==========================================
// সেলার Add Product পেজ (Dynamic Categories & Subcategories)
// ==========================================
class AddProductPage extends StatefulWidget { const AddProductPage({super.key}); @override State<AddProductPage> createState() => _AddProductPageState(); }
class _AddProductPageState extends State<AddProductPage> {
  final nameController = TextEditingController(); 
  final priceController = TextEditingController(); 
  final originalPriceController = TextEditingController(); 
  final stockController = TextEditingController(text: '0'); 
  final descController = TextEditingController(); 
  final tagInput = TextEditingController(); 
  
  //[NEW LOGIC] ডাইনামিক ক্যাটাগরির জন্য ভেরিয়েবল
  String? selectedCategory; 
  String? selectedSubcategory; 
  List<Map<String, dynamic>> allCategoriesData =[]; 
  List<String> availableSubcategories =[]; 

  List<XFile> selectedImages =[]; 
  List<String> searchTags =[]; 
  final ImagePicker _picker = ImagePicker();

  bool hasColorVariants = false; 
  bool hasSizeVariants = false; 

  final unitController = TextEditingController(text: 'Piece'); 
  List<Map<String, dynamic>> selectedColors =[]; 
  List<String> selectedSizes =[]; 
  List<Map<String, dynamic>> variantMatrix =[]; 

  final TextEditingController colorInputCtrl = TextEditingController();
  final TextEditingController sizeInputCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchCategoriesFromFirebase(); 
  }

  Future<void> _fetchCategoriesFromFirebase() async {
    try {
      var snap = await FirebaseFirestore.instance.collection('categories').get();
      if (mounted) {
        setState(() {
          allCategoriesData = snap.docs.map((doc) => doc.data()).toList();
        });
      }
    } catch (e) {
      print("Error fetching categories: $e");
    }
  }

  Future<void> _pickColorImage(int index) async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) setState(() => selectedColors[index]['image'] = image);
  }

  void _generateVariantMatrix() {
    Map<String, Map<String, dynamic>> existingData = {};
    for (var item in variantMatrix) {
      existingData['${item['color']}_${item['size']}'] = item;
    }
    variantMatrix.clear();

    if (!hasColorVariants && !hasSizeVariants) {
      _calculateTotalStock();
      return;
    }

    List<Map<String, dynamic>> tempColors = (hasColorVariants && selectedColors.isNotEmpty) ? selectedColors :[{'name': 'Default', 'image': null}];
    List<String> tempSizes = (hasSizeVariants && selectedSizes.isNotEmpty) ? selectedSizes :['Default'];

    if (hasColorVariants && selectedColors.isEmpty && !hasSizeVariants) return;
    if (hasSizeVariants && selectedSizes.isEmpty && !hasColorVariants) return;

    for (var c in tempColors) {
      for (var s in tempSizes) {
        String key = '${c['name']}_$s';
        variantMatrix.add({
          'color': c['name'], 'size': s,
          'price': existingData[key]?['price'] ?? 0, 'stock': existingData[key]?['stock'] ?? 0,
        });
      }
    }
    _calculateTotalStock();
  }

  void _calculateTotalStock() {
    if (!hasColorVariants && !hasSizeVariants) return; 
    int total = 0;
    for (var item in variantMatrix) { total += (item['stock'] ?? 0) as int; }
    setState(() => stockController.text = total.toString());
  }

  Future<void> pickImages() async {
    final List<XFile> images = await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1080);
    if (images.isNotEmpty) setState(() => selectedImages.addAll(images));
  }

  void uploadProduct() async {
    String pName = nameController.text.trim();
    String pPrice = priceController.text.trim();
    String pStock = stockController.text.trim();

    // ১. প্রয়োজনীয় ঘরগুলো খালি আছে কি না চেক করা
    if (pName.isEmpty || pPrice.isEmpty || pStock.isEmpty || selectedCategory == null) { 
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('দয়া করে নাম, দাম, স্টক এবং ক্যাটাগরি সিলেক্ট করুন!'), backgroundColor: Colors.red)
      ); 
      return; 
    }

    // ২. অন্তত একটি ছবি সিলেক্ট করা হয়েছে কি না চেক করা (ছবি ছাড়া প্রোডাক্ট আপলোড হবে না)
    if (selectedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('দয়া করে অন্তত একটি প্রোডাক্টের ছবি দিন!'), backgroundColor: Colors.red)
      );
      return;
    }

    try {
      // লোডিং দেখানো
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));
      
      // ছবিগুলো স্টোরেজে আপলোড করা
      List<String> imageUrls = [];
      for (var image in selectedImages) {
        String fileName = 'prod_${DateTime.now().millisecondsSinceEpoch}_${image.name}';
        Reference ref = FirebaseStorage.instance.ref().child('product_images').child(fileName);
        if (kIsWeb) { 
          Uint8List bytes = await image.readAsBytes(); 
          await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg')); 
        } else { 
          await ref.putFile(File(image.path)); 
        }
        imageUrls.add(await ref.getDownloadURL());
      }

      // সার্চ ট্যাগ তৈরি করা
      if (tagInput.text.trim().isNotEmpty) { 
        var tags = tagInput.text.split(','); 
        for (var t in tags) { if (t.trim().isNotEmpty) searchTags.add(t.trim().toLowerCase()); } 
      }
      List<String> finalTags = searchTags.toSet().toList(); // ডুপ্লিকেট রিমুভ
      finalTags.add(pName.toLowerCase());

      // অটো SKU জেনারেট করা
      String generateSKU = 'DS-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';

      // ভেরিয়েন্ট তৈরি করা
      List<Map<String, dynamic>> finalMatrixToSave = [];
      if (!hasColorVariants && !hasSizeVariants) {
        finalMatrixToSave = [{
          'color': 'Default',
          'size': 'Default',
          'price': 0,
          'stock': int.tryParse(pStock) ?? 0
        }];
      } else {
        // ভেরিয়েন্ট থাকলে তার প্রসেস (আগের লজিক অনুযায়ী)
        for (var v in variantMatrix) {
          finalMatrixToSave.add(Map<String, dynamic>.from(v));
        }
      }

      // ৩. ডাটাবেসে (Firestore) সেভ করা
      await FirebaseFirestore.instance.collection('products').add({
        'product_name': pName, 
        'price': int.tryParse(pPrice) ?? 0, 
        'original_price': int.tryParse(originalPriceController.text.trim()) ?? (int.tryParse(pPrice) ?? 0), 
        'stock': int.tryParse(pStock) ?? 0,
        'category': selectedCategory, 
        'subcategory': selectedSubcategory ?? '',
        'description': descController.text.trim(),
        'search_tags': finalTags, 
        'image_urls': imageUrls, 
        'seller_id': FirebaseAuth.instance.currentUser?.uid, 
        'timestamp': FieldValue.serverTimestamp(), 
        'status': 'pending',
        'sku': generateSKU,
        'is_active': true,
        'variant_unit': hasSizeVariants ? unitController.text.trim() : 'Piece', 
        'variants': finalMatrixToSave,
        'sales_count': 0,
      });

      // অ্যাডমিনকে নোটিফিকেশন পাঠানো
      await FirebaseFirestore.instance.collection('notifications').add({
        'title': 'New Product Pending 📦',
        'message': 'একজন সেলার "$pName" আপলোড করেছেন। এপ্রুভ করুন।',
        'target_role': 'admin',
        'sent_at': FieldValue.serverTimestamp()
      });

      if (!mounted) return;
      Navigator.pop(context); // লোডিং বন্ধ
      Navigator.pop(context); // পেজ থেকে বের হওয়া
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('প্রোডাক্ট সফলভাবে আপলোড হয়েছে এবং এপ্রুভালের জন্য পাঠানো হয়েছে! 🎉'), backgroundColor: Colors.green));
    } catch (e) { 
      Navigator.pop(context); // ভুল হলে লোডিং বন্ধ
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); 
    }
  }

  Widget _buildProVariantSystem() {
    if (!hasColorVariants && !hasSizeVariants) return const SizedBox(); 
    
    return Container(
      padding: const EdgeInsets.all(15), 
      decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.deepOrange.shade200), borderRadius: BorderRadius.circular(10), boxShadow:[BoxShadow(color: Colors.grey.shade100, blurRadius: 5)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children:[
          const Text('Product Variations', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.deepOrange)),
          const SizedBox(height: 5),
          const Text('যে অপশনগুলো অন করেছেন, সেগুলোর ডাটা দিন। নিচে অটোমেটিক লিস্ট তৈরি হবে।', style: TextStyle(fontSize: 11, color: Colors.grey)),
          const Divider(height: 25),

          if (hasColorVariants) ...[
            const Text('1. Colors & Images', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
            const SizedBox(height: 10),
            Row(
              children:[
                Expanded(child: TextField(controller: colorInputCtrl, decoration: const InputDecoration(hintText: 'e.g. Black, Red...', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), onPressed: () { if (colorInputCtrl.text.isNotEmpty) { setState(() { selectedColors.add({'name': colorInputCtrl.text.trim(), 'image': null}); colorInputCtrl.clear(); _generateVariantMatrix(); }); } }, child: const Text('Add', style: TextStyle(color: Colors.white)))
              ],
            ),
            const SizedBox(height: 15),
            if (selectedColors.isNotEmpty)
              Wrap(
                spacing: 12, runSpacing: 12,
                children: selectedColors.asMap().entries.map((entry) {
                  int idx = entry.key; Map<String, dynamic> c = entry.value;
                  return Container(
                    width: 90, padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.teal.shade50, border: Border.all(color: Colors.teal.shade200), borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children:[
                        InkWell(
                          onTap: () => _pickColorImage(idx), 
                          child: Container(
                            width: 60, height: 60, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal)), 
                            child: c['image'] != null ? ClipRRect(borderRadius: BorderRadius.circular(8), child: kIsWeb ? Image.network(c['image'].path, fit: BoxFit.cover) : Image.file(File(c['image'].path), fit: BoxFit.cover)) : Column(mainAxisAlignment: MainAxisAlignment.center, children: const[Icon(Icons.add_a_photo, size: 20, color: Colors.teal), SizedBox(height: 2), Text('Photo', style: TextStyle(fontSize: 10, color: Colors.teal))])
                          )
                        ),
                        const SizedBox(height: 8), 
                        Row(mainAxisAlignment: MainAxisAlignment.center, children:[Expanded(child: Text(c['name'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis)), InkWell(onTap: () => setState(() { selectedColors.removeAt(idx); _generateVariantMatrix(); }), child: const Icon(Icons.cancel, color: Colors.red, size: 18))]),
                      ],
                    ),
                  );
                }).toList(),
              ),
            const Divider(height: 30),
          ],

          if (hasSizeVariants) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children:[
                Text(hasColorVariants ? '2. Sizes / Variations' : '1. Sizes / Variations', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                SizedBox(width: 100, child: TextField(controller: unitController, decoration: const InputDecoration(labelText: 'Unit (e.g. Watt)', isDense: true, border: UnderlineInputBorder()), onChanged: (v) => setState(() {})))
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children:[
                Expanded(child: TextField(controller: sizeInputCtrl, decoration: const InputDecoration(hintText: 'e.g. 120, XL, 32...', isDense: true, border: OutlineInputBorder()))),
                const SizedBox(width: 10),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.blue), onPressed: () { if (sizeInputCtrl.text.isNotEmpty) { setState(() { selectedSizes.add(sizeInputCtrl.text.trim()); sizeInputCtrl.clear(); _generateVariantMatrix(); }); } }, child: const Text('Add', style: TextStyle(color: Colors.white)))
              ],
            ),
            const SizedBox(height: 10),
            if (selectedSizes.isNotEmpty)
              Wrap(spacing: 8, children: selectedSizes.map((s) => Chip(label: Text('$s ${unitController.text}'), deleteIcon: const Icon(Icons.cancel, color: Colors.red, size: 18), onDeleted: () => setState(() { selectedSizes.remove(s); _generateVariantMatrix(); }))).toList()),
            const Divider(height: 30, color: Colors.deepOrange, thickness: 1),
          ],

          Text(hasColorVariants && hasSizeVariants ? '3. Set Stock & Extra Price' : '2. Set Stock & Extra Price', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 10),
          
          if (variantMatrix.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(10.0), child: Text('Add options above to generate list.', style: TextStyle(color: Colors.grey))))
          else
            ListView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: variantMatrix.length,
              itemBuilder: (context, index) {
                var item = variantMatrix[index]; bool isFirst = index == 0; 
                String variantTitle = '';
                if (hasColorVariants && item['color'] != 'Default') variantTitle += item['color'];
                if (hasColorVariants && hasSizeVariants && item['color'] != 'Default' && item['size'] != 'Default') variantTitle += ' - ';
                if (hasSizeVariants && item['size'] != 'Default') variantTitle += '${item['size']} ${unitController.text}';
                if (variantTitle.isEmpty) variantTitle = 'Default Option';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children:[
                      Expanded(flex: 2, child: Text(variantTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))), const SizedBox(width: 10),
                      Expanded(flex: 1, child: TextFormField(initialValue: item['stock'].toString(), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Stock', isDense: true, border: OutlineInputBorder()), onChanged: (val) { variantMatrix[index]['stock'] = int.tryParse(val) ?? 0; _calculateTotalStock(); })), const SizedBox(width: 10),
                      Expanded(flex: 2, child: TextFormField(initialValue: item['price'].toString(), keyboardType: TextInputType.number, readOnly: isFirst, decoration: InputDecoration(labelText: isFirst ? 'Base Price' : '+ Extra ৳', isDense: true, filled: isFirst, fillColor: isFirst ? Colors.grey.shade200 : Colors.white, border: const OutlineInputBorder()), onChanged: (val) { variantMatrix[index]['price'] = int.tryParse(val) ?? 0; })),
                    ],
                  ),
                );
              },
            ),
            if (variantMatrix.isNotEmpty)
              const Padding(padding: EdgeInsets.only(top: 8), child: Text('* প্রথম ভেরিয়েন্টের এক্সট্রা প্রাইজ সবসময় ০ (শূন্য) হবে, যাতে কাস্টমার সঠিক বেস প্রাইজ দেখতে পায়।', style: TextStyle(fontSize: 11, color: Colors.redAccent))),
        ],
      ),
    );
  }

  @override Widget build(BuildContext context) {
    bool hasAnyVariant = hasColorVariants || hasSizeVariants;

    List<DropdownMenuItem<String>> categoryItems = allCategoriesData.map((cat) {
      return DropdownMenuItem<String>(value: cat['name'], child: Text(cat['name']));
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white, appBar: AppBar(title: const Text('ADD NEW PRODUCT'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[
          const Text('Product Images', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 10),
          Row(children:[InkWell(onTap: pickImages, child: Container(height: 90, width: 90, decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.deepOrange, width: 2)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children:[Icon(Icons.add_a_photo, color: Colors.deepOrange), Text('Add')]))), const SizedBox(width: 10), Expanded(child: SizedBox(height: 90, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: selectedImages.length, itemBuilder: (context, index) {return Container(width: 90, margin: const EdgeInsets.only(right: 10), decoration: BoxDecoration(borderRadius: BorderRadius.circular(15), image: DecorationImage(image: kIsWeb ? NetworkImage(selectedImages[index].path) : FileImage(File(selectedImages[index].path)) as ImageProvider, fit: BoxFit.cover)), child: Align(alignment: Alignment.topRight, child: IconButton(icon: const Icon(Icons.cancel, color: Colors.red), onPressed: () => setState(() => selectedImages.removeAt(index)))));})))]),
          const SizedBox(height: 25), 
          
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Select Category', border: OutlineInputBorder()), 
            initialValue: selectedCategory, 
            items: categoryItems.isEmpty ?[const DropdownMenuItem(value: null, child: Text('Loading Categories...'))] : categoryItems, 
            onChanged: (val) {
              if (val == null) return;
              setState(() {
                selectedCategory = val;
                selectedSubcategory = null; 
                
                var match = allCategoriesData.firstWhere((cat) => cat['name'] == val, orElse: () => {});
                if (match.isNotEmpty && match['subcategories'] != null) {
                  List<dynamic> subData = match['subcategories'];
                  availableSubcategories = subData.map((e) => e['name'].toString()).toList();
                } else {
                  availableSubcategories =[];
                }
              });
            }
          ),
          const SizedBox(height: 15),
          
          if (availableSubcategories.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: 'Select Subcategory (Optional)', border: OutlineInputBorder()), 
              initialValue: selectedSubcategory, 
              items: availableSubcategories.map((sub) => DropdownMenuItem(value: sub, child: Text(sub))).toList(), 
              onChanged: (val) => setState(() => selectedSubcategory = val),
            ),
            const SizedBox(height: 20),
          ],

          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Product Name', border: OutlineInputBorder())), const SizedBox(height: 15),
          
          Container(
            decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.teal.shade200)),
            child: Column(
              children:[
                SwitchListTile(title: const Text('Enable Color Variants', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), value: hasColorVariants, activeThumbColor: Colors.teal, onChanged: (val) { setState(() { hasColorVariants = val; if(!val) selectedColors.clear(); _generateVariantMatrix(); }); }),
                const Divider(height: 0),
                SwitchListTile(title: const Text('Enable Size/Option Variants', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), value: hasSizeVariants, activeThumbColor: Colors.teal, onChanged: (val) { setState(() { hasSizeVariants = val; if(!val) selectedSizes.clear(); _generateVariantMatrix(); }); }),
              ],
            ),
          ),
          const SizedBox(height: 15),

          Row(
            children:[
              Expanded(child: TextField(controller: priceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Base Price (৳)', border: OutlineInputBorder()))), 
              const SizedBox(width: 10), 
              Expanded(child: TextField(controller: originalPriceController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Original Price (৳)', border: OutlineInputBorder()))), 
              const SizedBox(width: 10), 
              Expanded(child: TextField(controller: stockController, readOnly: hasAnyVariant, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Total Stock', border: const OutlineInputBorder(), filled: hasAnyVariant, fillColor: hasAnyVariant ? Colors.grey.shade200 : Colors.white))),
            ]
          ),
          const SizedBox(height: 25), 
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children:[TextField(controller: tagInput, decoration: InputDecoration(hintText: 'Paste Tags (Comma separated)', suffixIcon: IconButton(icon: const Icon(Icons.add_circle, color: Colors.teal), onPressed: () { if (tagInput.text.trim().isNotEmpty) { setState(() { var t = tagInput.text.split(','); for(var x in t){if(x.trim().isNotEmpty) searchTags.add(x.trim());} tagInput.clear(); }); } }))), Wrap(spacing: 8, children: searchTags.map((item) => Chip(label: Text(item), onDeleted: () => setState(() => searchTags.remove(item)))).toList())])),
          const SizedBox(height: 25), 
          
          _buildProVariantSystem(), 

          const SizedBox(height: 25), TextField(controller: descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder())), const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: uploadProduct, child: const Text('SUBMIT PRODUCT', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))))
        ]),
      ),
    );
  }
}

// ==========================================
// সেলার অর্ডার ম্যানেজমেন্ট (With Details Modal & Image Zoom)
// ==========================================
class SellerOrderManagement extends StatelessWidget {
  const SellerOrderManagement({super.key});

  Future<void> _sendCustomerNotification(String userId, String orderId, String statusMsg) async {
    await FirebaseFirestore.instance.collection('notifications').add({
      'target_user_id': userId, 'title': 'Order Update 📦', 'message': 'Your order #${orderId.substring(0, 8).toUpperCase()} is $statusMsg.', 'sent_at': FieldValue.serverTimestamp(),
    });
  }

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

  void _showOrderFullDetailsModal(BuildContext context, Map<String, dynamic> data, String orderId, String sellerId) {
    String status = data['status'] ?? 'Pending';
    List<dynamic> allItems = data['items'] ??[];
    List<dynamic> myItems = allItems.where((i) => i['seller_id'] == sellerId).toList();

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
                  _buildTimelineRow('Handed Over to Rider', data['dispatched_at'],['Dispatched', 'In-Transit', 'Delivered'].contains(status)),
                  if (status != 'Delivery Failed')
                    _buildTimelineRow('Delivered to Customer', data['delivered_at'], status == 'Delivered', isLast: true),
                  if (status == 'Delivery Failed')
                    _buildTimelineRow('Delivery Failed (${data['failed_reason']})', data['failed_at'], true, isLast: true, isError: true),
                  
                  const Divider(height: 30),

                  // [NEW] সেলারকেও প্রুফ ছবি দেখানো হচ্ছে (ক্লিক করলে বড় হবে)
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

                  const Text('Items You Need to Pack', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 10),
                  ...myItems.map((item) {
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(width: 50, height: 50, decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: DecorationImage(image: NetworkImage(item['image_url'] ?? ''), fit: BoxFit.cover))),
                      title: Text(item['product_name'], style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (item['selected_size'].toString().isNotEmpty || item['selected_color'].toString().isNotEmpty)
                            Text('Color: ${item['selected_color']} | Size: ${item['selected_size']}', style: const TextStyle(fontSize: 11, color: Colors.black54)),
                          Text('Qty: ${item['quantity']} | Price: ৳${item['price']}', style: const TextStyle(fontSize: 12, color: Colors.deepOrange)),
                        ],
                      ),
                    );
                  }),
                  
                  const Divider(height: 30),
                  
                  const Text('Customer Details', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal)),
                  const SizedBox(height: 10),
                  Row(children:[const Icon(Icons.person, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(data['shipping_name'] ?? 'Unknown')]), 
                  const SizedBox(height: 5),
                  Row(children:[const Icon(Icons.phone, size: 16, color: Colors.grey), const SizedBox(width: 8), Text(data['shipping_phone'] ?? 'N/A')]), 
                  const SizedBox(height: 5),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children:[const Icon(Icons.location_on, size: 16, color: Colors.grey), const SizedBox(width: 8), Expanded(child: Text(data['shipping_address_text'] ?? 'No Address provided'))]),
                  const SizedBox(height: 30),
                ],
              ),
            ),
            
            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: () => Navigator.pop(context), child: const Text('Close Report', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))
          ]
        )
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    User? currentUser = FirebaseAuth.instance.currentUser;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('orders').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return Scaffold(body: Center(child: Text('Error: ${snapshot.error}')));

        var allDocs = snapshot.hasData ? snapshot.data!.docs.toList() : <QueryDocumentSnapshot>[];
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

        var pendingOrders = sellerOrders.where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'Pending').toList();
        var processingOrders = sellerOrders.where((doc) => ['Processing', 'Ready to Ship'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
        var shippedOrders = sellerOrders.where((doc) =>['Dispatched', 'In-Transit'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();
        var completedOrders = sellerOrders.where((doc) =>['Delivered', 'Delivery Failed', 'Cancelled'].contains((doc.data() as Map<String, dynamic>)['status'])).toList();

        return DefaultTabController(
          length: 3, // ৪ থেকে কমিয়ে ৩ করা হলো
          child: Scaffold(
            backgroundColor: Colors.grey.shade100,
            appBar: AppBar(
              backgroundColor: Colors.amber[200], 
              title: const Text('ORDER MANAGEMENT', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)), 
              bottom: TabBar(
                isScrollable: false, 
                labelColor: Colors.black, indicatorColor: Colors.deepOrange, 
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                tabs:[
                  // 'Pending' ট্যাবটি এখান থেকে মুছে ফেলা হয়েছে
                  _buildTabWithBadge('To Pack', processingOrders.length), 
                  _buildTabWithBadge('Shipped', shippedOrders.length), 
                  const Tab(text: 'Done')
                ]
              )
            ),
            body: TabBarView(
              children:[
                // pendingOrders এর লিস্ট ভিউ এখান থেকে মুছে ফেলা হয়েছে
                _buildOrderList(context, processingOrders, currentUser!.uid),
                _buildOrderList(context, shippedOrders, currentUser.uid),
                _buildOrderList(context, completedOrders, currentUser.uid),
              ],
            )
          ),
        );
      }
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
        if (['Processing', 'Ready to Ship'].contains(status)) {
          statusColor = Colors.blue;
        } else if (['Dispatched', 'In-Transit'].contains(status)) statusColor = Colors.purple;
        else if (status == 'Delivered') statusColor = Colors.green;
        else if (['Delivery Failed', 'Cancelled'].contains(status)) statusColor = Colors.red;

        return Container(
          margin: const EdgeInsets.only(bottom: 15), padding: const EdgeInsets.all(15), 
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.grey.shade300)), 
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, 
            children:[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                children:[
                  Text('ID: ${doc.id.substring(0, 8).toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)), 
                  Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3), decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Text(status, style: TextStyle(fontSize: 12, color: statusColor, fontWeight: FontWeight.bold)))
                ]
              ), 
              
              const SizedBox(height: 8),
              Text('Ordered: ${_formatTime(data['order_date'])}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
              if (data['processing_at'] != null) Text('Confirmed: ${_formatTime(data['processing_at'])}', style: const TextStyle(fontSize: 11, color: Colors.blue)),
              if (data['ready_to_ship_at'] != null) Text('Packed: ${_formatTime(data['ready_to_ship_at'])}', style: const TextStyle(fontSize: 11, color: Colors.teal)),
              
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
                  Row(
                    children:[
                      OutlinedButton(
                        onPressed: () => _showOrderFullDetailsModal(context, data, doc.id, sellerId),
                        style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact, side: const BorderSide(color: Colors.teal), padding: const EdgeInsets.symmetric(horizontal: 10)),
                        child: const Text('Details', style: TextStyle(fontSize: 12, color: Colors.teal)),
                      ),
                      const SizedBox(width: 8),
                      _buildSellerActionButton(context, doc.id, customerId, status, data, orders.length),
                    ],
                  )
                ]
              ),
            ]
          )
        );
      }
    );
  }

  Widget _buildSellerActionButton(BuildContext context, String orderId, String customerId, String status, Map<String, dynamic> orderData, int listLength) {
    if (status == 'Pending') {
      return const Text('Awaiting Admin', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 11));
    } 
    else if (status == 'Processing') {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🔴 Seller Cancel Button (No Spinner, Instant Action)
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), visualDensity: VisualDensity.compact),
            onPressed: () {
              // ১. সাথে সাথে ডাটাবেস আপডেট (কোনো লোডিং ছাড়া)
              FirebaseFirestore.instance.collection('orders').doc(orderId).update({'status': 'Cancelled'});
              
              // ২. ব্যাকগ্রাউন্ডে নোটিফিকেশন পাঠানো
              FirebaseFirestore.instance.collection('notifications').add({
                'target_user_id': customerId,
                'title': 'Order Cancelled ❌',
                'message': 'দুঃখিত, স্টক না থাকায় সেলার আপনার অর্ডারটি বাতিল করেছেন।',
                'sent_at': FieldValue.serverTimestamp(),
              });

              FirebaseFirestore.instance.collection('notifications').add({
                'title': 'Order Cancelled by Seller ❌',
                'message': 'সেলার একটি কনফার্ম করা অর্ডার বাতিল করেছেন (#${orderId.substring(0, 8).toUpperCase()})।',
                'topic': 'admins',
                'sent_at': FieldValue.serverTimestamp(),
              });
              
              // ৩. সাথে সাথে মেসেজ দেখানো
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order Cancelled!'), backgroundColor: Colors.red));
            },
            child: const Text('Cancel', style: TextStyle(fontSize: 12))
          ),
          const SizedBox(width: 8),

          // 🟠 Pack Button
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, visualDensity: VisualDensity.compact),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('orders').doc(orderId).update({
                'status': 'Ready to Ship',
                'ready_to_ship_at': FieldValue.serverTimestamp(),
              });

              if (listLength <= 1) {
                DefaultTabController.of(context).animateTo(1); 
              }
              
              await _sendCustomerNotification(customerId, orderId, 'packed and waiting for rider pickup');
              
              await FirebaseFirestore.instance.collection('notifications').add({
                'title': 'New Delivery Available! 🛵',
                'message': 'একটি নতুন পার্সেল ডেলিভারির জন্য প্রস্তুত। দ্রুত অ্যাপে ঢুকে এক্সেপ্ট করুন।',
                'topic': 'riders', 
                'type': 'rider_job',
                'data': {'screen': 'rider_dashboard'},
                'sent_at': FieldValue.serverTimestamp(),
              });
              
              await FirebaseFirestore.instance.collection('notifications').add({
                'title': 'Order Packed 📦',
                'message': 'অর্ডার #${orderId.substring(0, 8).toUpperCase()} সেলার প্যাক করেছেন।',
                'topic': 'admins',
                'sent_at': FieldValue.serverTimestamp(),
              });
              
              if(context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order packed! Notifying nearby riders...')));
            }, 
            icon: const Icon(Icons.check_circle, color: Colors.white, size: 14), 
            label: const Text('Pack', style: TextStyle(color: Colors.white, fontSize: 12))
          )
        ],
      );
    }
    else if (status == 'Ready to Ship' || status == 'Dispatched') {
      String pickupOTP = orderData['pickup_otp'] ?? '0000';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children:[
          Text(status == 'Dispatched' ? 'Rider coming!' : 'Wait for Rider', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 10)),
          const SizedBox(height: 5),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade50, border: Border.all(color: Colors.red), borderRadius: BorderRadius.circular(5)), child: Text('OTP: $pickupOTP', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)))
        ],
      );
    }
    else if (status == 'In-Transit') return const Text('Handed Over 🚚', style: TextStyle(color: Colors.purple, fontWeight: FontWeight.bold, fontSize: 11));
    else if (status == 'Delivered') return const Text('Done ✅', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 11));
    else if (status == 'Delivery Failed') return const Text('Failed ❌', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11));
    return const SizedBox();
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
                  initialValue: selectedMethod,
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
                      onPressed: () {
                        Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => const LoginPage()), (route) => false);
                        Future.microtask(() async {
                          await NotificationService.syncFcmTopics('guest');
                          SharedPreferences prefs = await SharedPreferences.getInstance();
                          await prefs.clear();
                          await FirebaseAuth.instance.signOut();
                        });
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
                // --- ম্যাপ বাটন শুরু ---
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map, color: Colors.deepOrange),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Pin Shop Location on Map',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange),
                        onPressed: () async {
                          // এটি আপনার auth_screens.dart এ থাকা ম্যাপ পেজটি ওপেন করবে
                          final LatLng? result = await Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LocationPickerScreen()),
                          );

                          if (result != null) {
                            // ম্যাপে লোকেশন পিন করলে তা সাথে সাথে ডাটাবেসে সেভ হবে
                            User? user = FirebaseAuth.instance.currentUser;
                            if (user != null) {
                              await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                                'latitude': result.latitude,
                                'longitude': result.longitude,
                              });
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Shop Location Updated on Map! 📍'), backgroundColor: Colors.green),
                                );
                              }
                            }
                          }
                        },
                        child: const Text('Open Map', style: TextStyle(color: Colors.white)),
                      ),
                    ],
                  ),
                ),
                // --- ম্যাপ বাটন শেষ ---
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
