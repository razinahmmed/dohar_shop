import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: ShopeeHome(),
  ));
}

class ShopeeHome extends StatelessWidget {
  const ShopeeHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.orange[800],
        title: Container(
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(5),
          ),
          child: const TextField(
            decoration: InputDecoration(
              hintText: 'Search in dohar_shop',
              prefixIcon: Icon(Icons.search, color: Colors.grey),
              border: InputBorder.none,
            ),
          ),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.shopping_cart_outlined), onPressed: () {}),
          IconButton(icon: const Icon(Icons.chat_outlined), onPressed: () {}),
        ],
      ),
      body: ListView(
        children: [
          // Banner Section - একটি সুন্দর ব্যানার ডিজাইন
          Container(
            height: 180,
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange[100],
              borderRadius: BorderRadius.circular(10),
              image: const DecorationImage(
                image: NetworkImage('https://via.placeholder.com/600x200'), // পরে আপনার আসল ব্যানার লিঙ্ক দিবেন
                fit: BoxFit.cover,
              ),
            ),
          ),

          // Category Section - ইংরেজি ভাষায় ক্যাটাগরি লিস্ট
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Text('Categories', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildCategoryItem(Icons.phone_android, 'Mobile'),
                _buildCategoryItem(Icons.laptop, 'Laptop'),
                _buildCategoryItem(Icons.watch, 'Watch'),
                _buildCategoryItem(Icons.checkroom, 'Fashion'),
                _buildCategoryItem(Icons.home, 'Home'),
              ],
            ),
          ),

          // Product Section - পন্যের তালিকা
          const Padding(
            padding: EdgeInsets.all(10),
            child: Text('Best Deals', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
          ),
          
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
            ),
            itemCount: 4,
            itemBuilder: (context, index) {
              return Card(
                child: Column(
                  children: [
                    Expanded(
                      child: Container(
                        color: Colors.grey[200],
                        width: double.infinity,
                        child: const Icon(Icons.image, size: 50, color: Colors.grey),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text('Product Name', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8.0),
                      child: Text('৳ 500', style: TextStyle(color: Colors.orange, fontSize: 16)),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
  // এই ফাংশনটি ক্যাটাগরি আইকন ও টেক্সট তৈরি করবে
  Widget _buildCategoryItem(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: Colors.orange[50],
            child: Icon(icon, color: Colors.orange[900]),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}