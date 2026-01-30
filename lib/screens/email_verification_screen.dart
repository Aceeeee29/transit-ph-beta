import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class EmailVerificationScreen extends StatefulWidget {
  final User user;

  const EmailVerificationScreen({super.key, required this.user});

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isLoading = false;
  String? _message;

  Future<void> _resendVerificationEmail() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await widget.user.sendEmailVerification();
      setState(() {
        _message = 'Verification email sent. Check your inbox or spam.';
      });
    } catch (e) {
      setState(() {
        _message = 'Failed to send verification email. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _checkVerification() async {
    setState(() {
      _isLoading = true;
      _message = null;
    });

    try {
      await widget.user.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      if (updatedUser != null && updatedUser.emailVerified) {
        // Email is verified, navigate to main screen
        if (mounted) {
          setState(() {
            _message = 'Email verified successfully! Redirecting...';
          });
          // Small delay to show the message
          await Future.delayed(const Duration(seconds: 1));

          // Navigate to main screen after verification
          if (mounted) {
            // Check user role and navigate accordingly
            final userDoc = await FirebaseFirestore.instance.collection('users').doc(updatedUser.uid).get();
            if (userDoc.exists) {
              final data = userDoc.data() as Map<String, dynamic>;
              final role = data['role'] as String?;
              final isAdmin = role == 'moderator';

              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => MainScreen(isAdmin: isAdmin)),
                (route) => false,
              );
            } else {
              // Fallback to regular user
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const MainScreen(isAdmin: false)),
                (route) => false,
              );
            }
          }
        }
      } else {
        setState(() {
          _message = 'Email not yet verified. Please check your email and click the verification link.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Failed to check verification status. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await FirebaseAuth.instance.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify Your Email'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 12,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.email_outlined,
                        size: 64,
                        color: Colors.blue,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Check Your Email',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We sent a verification link to ${widget.user.email}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),
                      if (_message != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _message!,
                            style: TextStyle(
                              color: _message!.contains('Failed') ? Colors.red : Colors.green,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _checkVerification,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : const Text(
                                    'I\'ve Verified My Email',
                                    style: TextStyle(fontSize: 16, color: Colors.white),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _isLoading ? null : _resendVerificationEmail,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: _isLoading
                                ? const CircularProgressIndicator()
                                : const Text(
                                    'Resend Verification Email',
                                    style: TextStyle(fontSize: 16),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _signOut,
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
