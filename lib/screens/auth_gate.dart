import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'email_verification_screen.dart';
import 'onboarding_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _accent = Color(0xFF2E7CF6);

  // ─── Shared loading scaffold ───────────────────────────────────────────────
  static Widget _loadingScaffold() {
    return const Scaffold(
      backgroundColor: _bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                color: _accent,
                strokeWidth: 2.5,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'TransitPH',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _accent,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _loadingScaffold();
        }

        if (snapshot.hasData) {
          final user = snapshot.data!;
          print('User signed in: ${user.uid}, email: ${user.email}, emailVerified: ${user.emailVerified}');

          // ── Fetch role FIRST before any other checks ───────────────────────
          return FutureBuilder<DocumentSnapshot>(
            future: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .get(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting) {
                return _loadingScaffold();
              }

              if (userSnapshot.hasError) {
                print('Error fetching user document: ${userSnapshot.error}');
                FirebaseAuth.instance.signOut();
                return const LoginScreen();
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final data =
                    userSnapshot.data!.data() as Map<String, dynamic>;
                final role = data['role'] as String?;
                final isAdmin =
                    role == 'moderator' || role == 'admin';
                final hasSeenTutorial =
                    data['hasSeenTutorial'] as bool? ?? false;

                // ── Moderators/admins skip email verification & onboarding ──
                if (isAdmin) {
                  print('Moderator/admin detected — skipping verification and onboarding');
                  return MainScreen(isAdmin: true);
                }

                // ── Regular users: check email verification ─────────────────
                final isGoogleUser = user.providerData
                    .any((p) => p.providerId == 'google.com');
                print('Is Google user: $isGoogleUser');

                if (!user.emailVerified && !isGoogleUser) {
                  print('Redirecting to email verification');
                  return EmailVerificationScreen(user: user);
                }

                // ── Check onboarding ────────────────────────────────────────
                if (!hasSeenTutorial) {
                  return OnboardingScreen(user: user);
                }

                return MainScreen(isAdmin: false);

              } else {
                // Document may not exist yet — race between auth event and
                // Firestore write completing. Wait 2 s then retry once.
                print(
                    'User document not found for UID: ${user.uid} — retrying...');
                return FutureBuilder<DocumentSnapshot>(
                  future: Future.delayed(const Duration(seconds: 2)).then(
                    (_) => FirebaseFirestore.instance
                        .collection('users')
                        .doc(user.uid)
                        .get(),
                  ),
                  builder: (context, retrySnapshot) {
                    if (retrySnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return _loadingScaffold();
                    }

                    if (retrySnapshot.hasData &&
                        retrySnapshot.data!.exists) {
                      final data = retrySnapshot.data!.data()
                          as Map<String, dynamic>;
                      final role = data['role'] as String?;
                      final isAdmin =
                          role == 'moderator' || role == 'admin';
                      final hasSeenTutorial =
                          data['hasSeenTutorial'] as bool? ?? false;

                      // Moderators skip verification & onboarding on retry too
                      if (isAdmin) return MainScreen(isAdmin: true);

                      return hasSeenTutorial
                          ? MainScreen(isAdmin: false)
                          : OnboardingScreen(user: user);
                    }

                    // Still no document after retry — sign out
                    print(
                        'User document still not found after retry — signing out');
                    FirebaseAuth.instance.signOut();
                    return const LoginScreen();
                  },
                );
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