import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'email_verification_screen.dart';
import 'onboarding_screen.dart';

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
          final user = snapshot.data!;
          print('User signed in: ${user.uid}, email: ${user.email}, emailVerified: ${user.emailVerified}');
          // Check if email is verified (skip for Google sign-in users)
          final isGoogleUser = user.providerData.any((provider) => provider.providerId == 'google.com');
          print('Is Google user: $isGoogleUser');
          if (!user.emailVerified && !isGoogleUser) {
            print('Redirecting to email verification');
            return EmailVerificationScreen(user: user);
          }
          print('Email verified or Google user, proceeding to role check');

          // User is signed in and verified, check role and onboarding status
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
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
                final hasSeenTutorial = data['hasSeenTutorial'] as bool? ?? false;

                if (!hasSeenTutorial) {
                  // Show onboarding if not seen
                  return OnboardingScreen(user: user);
                } else {
                  // Proceed to main screen
                  return MainScreen(isAdmin: isAdmin);
                }
              } else {
                // User document doesn't exist, sign out
                print('User document does not exist for UID: ${user.uid}');
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
