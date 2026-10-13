import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Whether the signed-in rider gets the student fare discount, from their
/// profile's category. Shared so every screen shows the same fares.
class FareProfileService {
  static Future<bool> isStudent() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return false;
      final snapshot =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final category =
          (snapshot.data()?['userCategory'] as String?)?.toLowerCase().trim() ??
          '';
      return category.replaceAll('_', ' ') == 'student';
    } catch (_) {
      return false;
    }
  }
}
