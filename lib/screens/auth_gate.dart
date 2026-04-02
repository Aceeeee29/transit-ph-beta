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
  static const _surface = Color(0xFFFFFFFF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

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

          // ── Keep user role/ban state live so moderation applies immediately ─
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid)
                .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting &&
                  !userSnapshot.hasData) {
                return _loadingScaffold();
              }

              if (userSnapshot.hasError) {
                print('Error fetching user document: ${userSnapshot.error}');
                FirebaseAuth.instance.signOut();
                return const LoginScreen();
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                final data = userSnapshot.data!.data() ?? <String, dynamic>{};
                final role = ((data['role'] as String?) ?? '')
                  .trim()
                  .toLowerCase()
                  .replaceAll('-', '_')
                  .replaceAll(' ', '_');
                final isAdmin = role == 'moderator' ||
                  role == 'admin' ||
                  role == 'superadmin' ||
                  role == 'super_admin';
                final isBanned = (data['isBanned'] as bool? ?? false) ||
                    (data['status'] as String? ?? '') == 'banned';
                final hasSeenTutorial =
                    data['hasSeenTutorial'] as bool? ?? false;

                if (isBanned) {
                  return const _BannedAccountHandler();
                }

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
                        final role = ((data['role'] as String?) ?? '')
                          .trim()
                          .toLowerCase()
                          .replaceAll('-', '_')
                          .replaceAll(' ', '_');
                        final isAdmin = role == 'moderator' ||
                          role == 'admin' ||
                          role == 'superadmin' ||
                          role == 'super_admin';
                      final isBanned = (data['isBanned'] as bool? ?? false) ||
                        (data['status'] as String? ?? '') == 'banned';
                      final hasSeenTutorial =
                          data['hasSeenTutorial'] as bool? ?? false;

                      if (isBanned) return const _BannedAccountHandler();

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

class _BannedAccountHandler extends StatefulWidget {
  const _BannedAccountHandler();

  @override
  State<_BannedAccountHandler> createState() => _BannedAccountHandlerState();
}

class _BannedAccountHandlerState extends State<_BannedAccountHandler> {
  bool _dialogShown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dialogShown) return;
    _dialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
            decoration: BoxDecoration(
              color: AuthGate._surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AuthGate._border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x1A2E7CF6),
                  blurRadius: 24,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AuthGate._danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.gpp_bad_rounded,
                        color: AuthGate._danger,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Account Banned',
                        style: TextStyle(
                          color: AuthGate._textPrimary,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your TransitPH account has been banned. Please contact support if you think this was a mistake.',
                  style: TextStyle(
                    color: AuthGate._textSecondary,
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AuthGate._accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(ctx).pop();
                    },
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthGate._loadingScaffold();
  }
}