import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sizer/sizer.dart';
import '../controller/shared_pref_helper.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String? id;
  double overallTotal = 0.0;

  String? userId;
  String? userName;
  String? userContact;

  bool isPlacingOrder = false; // Added for loading state

  String _getSpiceLabel(dynamic level) {
    if (level == null) return "Medium";
    switch (level) {
      case 1:
        return "Mild";
      case 2:
        return "Medium";
      case 3:
        return "Hot";
      case 4:
        return "Extra Hot";
      case 5:
        return "Inferno";
      default:
        return "Medium";
    }
  }

  String _getOilLabel(dynamic level) {
    if (level == null) return "Medium Oil";
    switch (level) {
      case 1:
        return "No Oil";
      case 2:
        return "Low Oil";
      case 3:
        return "Medium Oil";
      case 4:
        return "High Oil";
      case 5:
        return "Extra Oil";
      default:
        return "Medium Oil";
    }
  }

  @override
  void initState() {
    super.initState();
    getShareId();
  }

  /// Fetch User ID from Shared Preferences
  Future<void> getShareId() async {
    userId = await SharedPrefHelper().getUserId();
    userName = await SharedPrefHelper().getUserName();
    userContact = await SharedPrefHelper().getUserContact();
    setState(() {});
  }

  /// Delete Cart Item
  Future<void> deleteCartItem(String cartItemId) async {
    try {
      await FirebaseFirestore.instance.collection('cart').doc(cartItemId).delete();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item removed from cart successfully', style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to remove item: $e')),
      );
    }
  }

  /// Calculate Total Price
  double calculateTotal(List<QueryDocumentSnapshot> cartItems) {
    double total = 0.0;
    for (var item in cartItems) {
      final data = item.data() as Map<String, dynamic>;
      total += (data['totalPrice'] as num).toDouble();
    }
    return total;
  }

  /// Get Current Location
  Future<Position?> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Location permissions are permanently denied')),
        );
        return null;
      }

      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to get location: $e')),
      );
      return null;
    }
  }

  /// Place Order
  Future<void> placeOrder(List<QueryDocumentSnapshot> cartItems) async {
    if (cartItems.isEmpty) return;

    setState(() {
      isPlacingOrder = true; // Start loading
    });

    try {
      final location = await _getCurrentLocation();

      if (location == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to fetch location. Please try again.')),
        );
        return;
      }

      final orderItems = cartItems.map((item) {
        final data = item.data() as Map<String, dynamic>;
        return {
          'itemName': data['itemName'],
          'quantity': data['quantity'],
          'totalPrice': data['totalPrice'],
          'image': data['image'],
          'spiceLevel': data['spiceLevel'],
          'oilLevel': data['oilLevel'],
        };
      }).toList();

      await FirebaseFirestore.instance.collection('orders').add({
        'userId': userId,
        'items': orderItems,
        'overallTotal': overallTotal,
        'userName': userName,
        'userContact': userContact,
        'location': {
          'latitude': location.latitude,
          'longitude': location.longitude,
        },
        'status': 'Pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      final batch = FirebaseFirestore.instance.batch();
      for (var item in cartItems) {
        batch.delete(item.reference);
      }
      await batch.commit();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.green,
          content: Text(
            'Order placed successfully! Your cart is now empty.',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to place order: $e')),
      );
    } finally {
      setState(() {
        isPlacingOrder = false; // Stop loading
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Cart', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.amber,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('cart')
            .where('id', isEqualTo: id)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('Your cart is empty!'));
          }

          final cartItems = snapshot.data!.docs;
          overallTotal = calculateTotal(cartItems);

          return Column(
            children: [
              Expanded(
                child: ListView.builder(
                  itemCount: cartItems.length,
                  itemBuilder: (context, index) {
                    final item = cartItems[index].data() as Map<String, dynamic>;

                    return Card(
                      color: Colors.amberAccent,
                      margin: EdgeInsets.symmetric(horizontal: 3.w, vertical: 1.h),
                      elevation: 3,
                      child: ListTile(
                        leading: Image.network(
                          item['image'],
                          width: 15.w,
                          height: 15.w,
                          fit: BoxFit.cover,
                        ),
                        title: Text(
                          item['itemName'],
                          style: TextStyle(fontSize: 12.sp, color: Colors.black),
                        ),
                        subtitle: Text(
                          'Quantity: ${item['quantity']}\nPrice: ${item['totalPrice']} PKR${item['spiceLevel'] != null && item['oilLevel'] != null ? '\nSpice: ${_getSpiceLabel(item['spiceLevel'])} | Oil: ${_getOilLabel(item['oilLevel'])}' : ''}',
                          style: const TextStyle(color: Colors.black, height: 1.3),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.black),
                          onPressed: () => deleteCartItem(cartItems[index].id),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text("Total :",style: TextStyle(fontSize: 14.sp,fontWeight: FontWeight.bold),),
                  Text("${overallTotal} Pkr",style: TextStyle(fontSize: 14.sp,fontWeight: FontWeight.bold))
                ],
              ),
              const Divider(),
              Padding(
                padding: EdgeInsets.all(3.w),
                child: ElevatedButton(
                  onPressed: isPlacingOrder ? null : () => placeOrder(cartItems),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    disabledBackgroundColor: Colors.amberAccent,
                  ),
                  child: isPlacingOrder
                      ? const CircularProgressIndicator(color: Colors.black)
                      : Text('Place Order', style: TextStyle(fontSize: 14.sp, color: Colors.black)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
