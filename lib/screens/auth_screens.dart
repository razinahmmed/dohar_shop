import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';

// আপনার অন্যান্য স্ক্রিনগুলোর ইমপোর্ট (প্রয়োজন অনুযায়ী ফোল্ডার পাথ ঠিক করে নিতে পারেন)
import 'customer_screens.dart';
import 'seller_screens.dart';
import 'rider_screens.dart';
import 'admin_screens.dart';
import 'package:flutter/foundation.dart';

// ==========================================
// ১. প্রফেশনাল Login Screen (Only Phone + Password)
// ==========================================
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;
  bool isPasswordVisible = false;

  Future<void> login() async {
    if (phoneController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ফোন নম্বর এবং পাসওয়ার্ড দিন!')));
      return;
    }

    setState(() => isLoading = true);
    String phoneNumber = phoneController.text.trim();
    if (!phoneNumber.startsWith('+88')) phoneNumber = '+88$phoneNumber';

    try {
      // ১. ফোন নাম্বার দিয়ে ইমেইল বের করা (আমাদের কাস্টম লজিক)
      String dummyEmail = '${phoneNumber.replaceAll('+', '')}@dshop.com';
      
      // ২. ফায়ারবেস লগিন
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: dummyEmail,
        password: passwordController.text.trim(),
      );

      User? user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (mounted) {
          if (doc.exists) {
            String role = (doc.data() as Map<String, dynamic>)['role'] ?? 'customer';
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
             Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      setState(() => isLoading = false);
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ভুল ফোন নম্বর বা পাসওয়ার্ড!')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.pop(context))),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children:[
              const Icon(Icons.shopping_bag_outlined, size: 80, color: Colors.deepOrange),
              const SizedBox(height: 20),
              const Text('Welcome Back!', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 10),
              const Text('আপনার মোবাইল নম্বর এবং পাসওয়ার্ড দিয়ে লগিন করুন', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 40),

              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  prefixText: '+88 ',
                  prefixIcon: const Icon(Icons.phone),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 15),
              
              TextField(
                controller: passwordController,
                obscureText: !isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey),
                    onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible),
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isLoading ? null : login,
                  child: isLoading 
                      ? const CircularProgressIndicator(color: Colors.white) 
                      : const Text('LOGIN', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 20),
              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children:[
                  const Text("Don't have an account? ", style: TextStyle(color: Colors.grey)),
                  InkWell(
                    onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SignupPage())),
                    child: const Text("Sign Up", style: TextStyle(color: Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 16)),
                  )
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// ২. প্রফেশনাল Sign Up Screen (Phone OTP + Password + Name)
// ==========================================
class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final TextEditingController firstNameCtrl = TextEditingController();
  final TextEditingController lastNameCtrl = TextEditingController();
  final TextEditingController phoneCtrl = TextEditingController();
  final TextEditingController emailCtrl = TextEditingController(); // ঐচ্ছিক
  final TextEditingController passwordCtrl = TextEditingController();
  final TextEditingController otpCtrl = TextEditingController();

  bool isOtpSent = false;
  bool isLoading = false;
  bool isPasswordVisible = false;
  String verificationIdSaved = '';

  // ১. একাউন্ট খোলার প্রথম ধাপ: OTP পাঠানো
  Future<void> requestOTP() async {
    if (firstNameCtrl.text.isEmpty || lastNameCtrl.text.isEmpty || phoneCtrl.text.isEmpty || passwordCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সবগুলো প্রয়োজনীয় ঘর পূরণ করুন!')));
      return;
    }
    if (passwordCtrl.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('পাসওয়ার্ড অন্তত ৬ অক্ষরের হতে হবে!')));
      return;
    }

    setState(() => isLoading = true);
    String phoneNumber = phoneCtrl.text.trim();
    if (!phoneNumber.startsWith('+88')) phoneNumber = '+88$phoneNumber';

    try {
      if (kIsWeb) {
        // [WEB LOGIC]
        ConfirmationResult result = await FirebaseAuth.instance.signInWithPhoneNumber(phoneNumber);
        setState(() {
          isLoading = false;
          isOtpSent = true;
          // ওয়েবের জন্য একটি গ্লোবাল ভেরিয়েবল বা প্রোপার্টিতে result সেভ করে রাখতে পারেন
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('OTP পাঠানো হয়েছে!')));
      } else {
        // [MOBILE LOGIC]
        await FirebaseAuth.instance.verifyPhoneNumber(
          phoneNumber: phoneNumber,
          verificationCompleted: (PhoneAuthCredential credential) async {
            // অটো ভেরিফাই হলে
            _createAccountAndLogin(credential);
          },
          verificationFailed: (FirebaseAuthException e) {
            setState(() => isLoading = false);
            if (e.code == 'invalid-phone-number') {
               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ফোন নম্বরটি সঠিক নয়।')));
            } else {
               ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: ${e.message}')));
            }
          },
          codeSent: (String verificationId, int? resendToken) {
            setState(() {
              isLoading = false;
              isOtpSent = true;
              verificationIdSaved = verificationId;
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আপনার ফোনে OTP পাঠানো হয়েছে! 📩')));
          },
          codeAutoRetrievalTimeout: (String verificationId) {},
        );
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  // ২. OTP ম্যানুয়ালি দিয়ে একাউন্ট তৈরি
  Future<void> verifyAndCreateAccount() async {
    if (otpCtrl.text.trim().isEmpty) return;
    setState(() => isLoading = true);

    try {
      if (kIsWeb) {
        // ওয়েবের ক্ষেত্রে ConfirmationResult.confirm() কল করতে হবে
        // এই উদাহরণের জন্য আমি মোবাইল ফোকাসড রাখছি, ওয়েবের জন্য state-এ result সেভ রাখতে হবে
      } else {
        PhoneAuthCredential credential = PhoneAuthProvider.credential(
          verificationId: verificationIdSaved,
          smsCode: otpCtrl.text.trim(),
        );
        await _createAccountAndLogin(credential);
      }
    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ভুল OTP! আবার চেষ্টা করুন।')));
    }
  }

  // ৩. ফায়ারবেস অথ এবং ডাটাবেসে সেভ (ম্যাজিক ট্রিক)
  Future<void> _createAccountAndLogin(PhoneAuthCredential credential) async {
    try {
      // ১. ফোন নাম্বার দিয়ে লগিন করা (যাতে ফোন ভেরিফাই হয়)
      UserCredential phoneUser = await FirebaseAuth.instance.signInWithCredential(credential);
      
      // ২.[MAGIC] যেহেতু আমরা পাসওয়ার্ড দিয়ে লগিন করতে চাই, তাই ফোন নাম্বারের উপর ভিত্তি করে একটি "Dummy Email" তৈরি করে পাসওয়ার্ড সেট করব।
      String phoneNumber = phoneCtrl.text.trim();
      if (!phoneNumber.startsWith('+88')) phoneNumber = '+88$phoneNumber';
      String dummyEmail = '${phoneNumber.replaceAll('+', '')}@dshop.com';
      
      // ফোন একাউন্টের সাথে ইমেইল লিংক করা
      AuthCredential emailCred = EmailAuthProvider.credential(email: dummyEmail, password: passwordCtrl.text.trim());
      
      try {
         await phoneUser.user!.linkWithCredential(emailCred);
      } catch (e) {
         // যদি আগেই লিংক করা থাকে
      }

      // ৩. ডাটাবেসে ইউজার সেভ করা (ডিফল্ট: Customer)
      await FirebaseFirestore.instance.collection('users').doc(phoneUser.user!.uid).set({
        'name': '${firstNameCtrl.text.trim()} ${lastNameCtrl.text.trim()}',
        'phone': phoneNumber,
        'email': emailCtrl.text.trim(), // কাস্টমারের দেওয়া আসল ইমেইল
        'role': 'customer', // সবাই ডিফল্টভাবে কাস্টমার
        'd_coins': 0,
        'created_at': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Created Successfully! 🎉'), backgroundColor: Colors.green));
      
      // সরাসরি হোম পেজে চলে যাবে
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));

    } catch (e) {
      setState(() => isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0, leading: IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.black), onPressed: () => Navigator.pop(context))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children:[
            const Text('Create Account', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Colors.black87)),
            const SizedBox(height: 5),
            const Text('Sign up to start shopping', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),

            if (!isOtpSent) ...[
              // নাম
              Row(
                children:[
                  Expanded(child: TextField(controller: firstNameCtrl, decoration: InputDecoration(labelText: 'First Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: lastNameCtrl, decoration: InputDecoration(labelText: 'Last Name', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))))),
                ],
              ),
              const SizedBox(height: 15),
              
              // ফোন
              TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: 'Mobile Number', prefixText: '+88 ', prefixIcon: const Icon(Icons.phone), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 15),

              // ইমেইল (ঐচ্ছিক)
              TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: 'Email Address (Optional)', prefixIcon: const Icon(Icons.email), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 15),

              // পাসওয়ার্ড
              TextField(
                controller: passwordCtrl,
                obscureText: !isPasswordVisible,
                decoration: InputDecoration(
                  labelText: 'Create Password',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(icon: Icon(isPasswordVisible ? Icons.visibility : Icons.visibility_off, color: Colors.grey), onPressed: () => setState(() => isPasswordVisible = !isPasswordVisible)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 30),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isLoading ? null : requestOTP,
                  child: isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('SEND OTP', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ] else ...[
              // OTP বক্স
              Text('Enter the 6-digit OTP sent to ${phoneCtrl.text}', style: const TextStyle(color: Colors.teal, fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              TextField(
                controller: otpCtrl, keyboardType: TextInputType.number, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold),
                decoration: InputDecoration(hintText: '------', border: OutlineInputBorder(borderRadius: BorderRadius.circular(10))),
              ),
              const SizedBox(height: 25),

              SizedBox(
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepOrange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                  onPressed: isLoading ? null : verifyAndCreateAccount,
                  child: isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text('VERIFY & SIGN UP', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 10),
              TextButton(onPressed: () => setState(() => isOtpSent = false), child: const Text('Edit Details', style: TextStyle(color: Colors.grey))),
            ],
            
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children:[
                const Text("Already have an account? ", style: TextStyle(color: Colors.grey)),
                InkWell(
                  onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginPage())),
                  child: const Text("Login", style: TextStyle(color: Colors.teal, fontWeight: FontWeight.bold, fontSize: 16)),
                )
              ],
            )
          ]
        )
      )
    );
  }
}

// ==========================================
// ২. Profile Completion Screen (নতুন ইউজারের জন্য)
// ==========================================
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final TextEditingController nameController = TextEditingController(); 
  final TextEditingController shopNameController = TextEditingController(); 
  
  String selectedRole = 'customer'; 
  LatLng? vendorLocation; 

  void saveProfile() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আপনার নাম দিন!')));
      return;
    }
    if (selectedRole == 'seller' && shopNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('সেলার হিসেবে আপনার শপের নাম দেওয়া বাধ্যতামূলক!')));
      return;
    }
    if (selectedRole != 'customer' && vendorLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ম্যাপে লোকেশন সেট করা বাধ্যতামূলক! 📍')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      Map<String, dynamic> userData = {
        'name': nameController.text.trim(), 
        'phone': user.phoneNumber, // ফায়ারবেস অথ থেকে অরিজিনাল নাম্বার নেওয়া হলো
        'role': selectedRole, 
        'd_coins': 0, // নতুন ইউজারের কয়েন
        'created_at': FieldValue.serverTimestamp()
      };

      if (selectedRole != 'customer') {
        userData['latitude'] = vendorLocation!.latitude;
        userData['longitude'] = vendorLocation!.longitude;
        userData['status'] = 'pending'; 
      }
      if (selectedRole == 'seller') {
        userData['shop_name'] = shopNameController.text.trim();
      }

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData);
      
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Setup Complete! 🎉', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      
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
    User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('Complete Profile', style: TextStyle(fontWeight: FontWeight.bold)), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white, elevation: 0),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0), 
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children:[
            Text('Verified Number: ${user?.phoneNumber ?? ''}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),

            const Text('Account Type', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
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

            if (selectedRole == 'seller') ...[
              TextField(
                controller: shopNameController, 
                decoration: InputDecoration(labelText: 'Shop Name', prefixIcon: const Icon(Icons.store), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))
              ),
              const SizedBox(height: 15),
            ],

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

            SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), onPressed: saveProfile, child: const Text('FINISH & GO TO DASHBOARD', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)))),
          ]
        )
      )
    );
  }

  Widget _buildRoleOption(String title, String role, IconData icon) {
    bool isSelected = selectedRole == role;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() { selectedRole = role; vendorLocation = null; }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(color: isSelected ? Colors.deepOrange : Colors.transparent, borderRadius: BorderRadius.circular(8), boxShadow: isSelected ?[const BoxShadow(color: Colors.black12, blurRadius: 5)] :[]),
          child: Column(children:[Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20), const SizedBox(height: 5), Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: FontWeight.bold, fontSize: 12))]),
        ),
      ),
    );
  }
}

// ==========================================
// ৩. ম্যাপ থেকে লোকেশন পিক করার স্ক্রিন (সেলার/রাইডারের জন্য)
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
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      Position position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
    } catch (e) {
      debugPrint("Error getting location: $e");
    }
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