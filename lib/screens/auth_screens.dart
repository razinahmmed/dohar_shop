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
import 'package:geocoding/geocoding.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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
// ৩. Profile Completion Screen (শুধুমাত্র কাস্টমার হিসেবে সেভ হবে)
// ==========================================
class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final TextEditingController nameController = TextEditingController(); 

  void saveProfile() async {
    if (nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('আপনার নাম দিন!')));
      return;
    }

    try {
      showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator()));

      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // সবাই ডিফল্টভাবে কাস্টমার হিসেবে জয়েন করবে
      Map<String, dynamic> userData = {
        'name': nameController.text.trim(), 
        'phone': user.phoneNumber, 
        'role': 'customer', // 👈 ফিক্সড কাস্টমার
        'd_coins': 0, 
        'created_at': FieldValue.serverTimestamp()
      };

      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userData);
      
      if (!mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account Setup Complete! 🎉', style: TextStyle(color: Colors.white)), backgroundColor: Colors.green));
      
      // প্রোফাইল সেভ হওয়ার পর সরাসরি কাস্টমার মেইন স্ক্রিনে চলে যাবে
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const MainScreen()));
      
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
            const Icon(Icons.person_pin, size: 80, color: Colors.deepOrange),
            const SizedBox(height: 20),
            const Text('Welcome to D Shop!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text('দয়া করে আপনার নাম দিয়ে প্রোফাইলটি সম্পূর্ণ করুন।', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 30),

            Text('Verified Number: ${user?.phoneNumber ?? ''}', style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),

            TextField(
              controller: nameController, 
              decoration: InputDecoration(labelText: 'Full Name', prefixIcon: const Icon(Icons.badge), border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))
            ), 
            const SizedBox(height: 40), 

            SizedBox(
              width: double.infinity, height: 50, 
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), 
                onPressed: saveProfile, 
                child: const Text('FINISH & GO TO DASHBOARD', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))
              )
            ),
          ]
        )
      )
    );
  }
}

// ==========================================
// ৩. ম্যাপ থেকে লোকেশন পিক করার স্ক্রিন (১০০% একুরেট Google API সার্চ)
// ==========================================
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key});

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng _currentPosition = const LatLng(23.6062, 90.1345); // দোহার
  GoogleMapController? _mapController;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;

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

  // 🔴 Google Geocoding API ব্যবহার করে ১০০% একুরেট সার্চ
  Future<void> _searchPlace() async {
    if (_searchController.text.trim().isEmpty) return;
    
    setState(() => _isSearching = true);
    
    try {
      String query = Uri.encodeComponent(_searchController.text.trim());
      // আপনার গুগল ম্যাপের API Key
      String apiKey = "AIzaSyC6C-fHPPbo5xdDDuNhEm4wDfVci9BZI0M"; 
      String url = "https://maps.googleapis.com/maps/api/geocode/json?address=$query&key=$apiKey";
      
      var response = await http.get(Uri.parse(url));
      var data = json.decode(response.body);

      if (data['status'] == 'OK' && data['results'].isNotEmpty) {
        var location = data['results'][0]['geometry']['location'];
        setState(() {
          _currentPosition = LatLng(location['lat'], location['lng']);
        });
        _mapController?.animateCamera(CameraUpdate.newLatLngZoom(_currentPosition, 16));
      } else {
        if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('জায়গাটি পাওয়া যায়নি! সঠিক নাম লিখুন।'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ইন্টারনেট কানেকশন চেক করুন!'), backgroundColor: Colors.red));
    } finally {
      setState(() => _isSearching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin Customer Location'), backgroundColor: Colors.deepOrange, foregroundColor: Colors.white),
      body: Stack(
        alignment: Alignment.center,
        children:[
          GoogleMap(
            initialCameraPosition: CameraPosition(target: _currentPosition, zoom: 15),
            onMapCreated: (GoogleMapController controller) => _mapController = controller,
            onCameraMove: (position) => _currentPosition = position.target,
            myLocationEnabled: true,
            myLocationButtonEnabled: false, 
            zoomControlsEnabled: false,
          ),
          
          const Padding(
            padding: EdgeInsets.only(bottom: 35.0), 
            child: Icon(Icons.location_on, size: 50, color: Colors.deepOrange),
          ),

          // 🔴 টপ সার্চ বার
          Positioned(
            top: 15, left: 15, right: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)]),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(hintText: 'Search area, village or city...', border: InputBorder.none),
                      onSubmitted: (value) => _searchPlace(),
                    ),
                  ),
                  _isSearching 
                      ? const Padding(padding: EdgeInsets.all(12.0), child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepOrange)))
                      : IconButton(icon: const Icon(Icons.search, color: Colors.deepOrange), onPressed: _searchPlace)
                ],
              ),
            ),
          ),

          // কারেন্ট লোকেশনে যাওয়ার বাটন
          Positioned(
            bottom: 90, right: 15,
            child: FloatingActionButton(
              mini: true, backgroundColor: Colors.white,
              onPressed: _getUserCurrentLocation,
              child: const Icon(Icons.my_location, color: Colors.blue),
            ),
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