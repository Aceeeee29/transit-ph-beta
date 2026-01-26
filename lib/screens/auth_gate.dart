import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasData) {
          // User is signed in, check role
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(snapshot.data!.uid).get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (userSnapshot.hasError) {
                // Handle error, perhaps show error message or sign out
                print('Error fetching user document: ${userSnapshot.error}');
                FirebaseAuth.instance.signOut();
                return const LoginScreen();
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final data = userSnapshot.data!.data() as Map<String, dynamic>;
                final role = data['role'] as String?;
                final isAdmin = role == 'moderator';
                return MainScreen(isAdmin: isAdmin);
              } else {
                // User document doesn't exist, sign out
                print('User document does not exist for UID: ${snapshot.data!.uid}');
                FirebaseAuth.instance.signOut();
                return const LoginScreen();
              }
            },
          );
        } else {
          // User is not signed in
          return const LoginScreen();
        }
      },
    );
  }
}
