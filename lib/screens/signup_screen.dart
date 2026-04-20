import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/user_profile_bootstrap_service.dart';
import '../widgets/auth/auth_text_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  String? _errorMessage;
  bool _isLoading = false;
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _accentSoft = Color(0x1A2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  // Common passwords to block
  final List<String> _commonPasswords = [
    'password',
    '123456',
    '123456789',
    'qwerty',
    'abc123',
    'password123',
    'admin',
    'letmein',
    'welcome',
    'monkey',
    '1234567890',
    'iloveyou',
    'princess',
    'rockyou',
    '1234567',
    '12345678',
    'password1',
    '123123',
    'football',
    'baseball',
  ];

  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    if (_commonPasswords.contains(password.toLowerCase())) return false;

    bool hasUpper = password.contains(RegExp(r'[A-Z]'));
    bool hasLower = password.contains(RegExp(r'[a-z]'));
    bool hasNumber = password.contains(RegExp(r'[0-9]'));
    bool hasSymbol = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    int categories = 0;
    if (hasUpper) categories++;
    if (hasLower) categories++;
    if (hasNumber) categories++;
    if (hasSymbol) categories++;

    return categories >= 2;
  }

  Future<void> _signup() async {
    if (_passwordController.text != _confirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match';
      });
      return;
    }

    if (!_isStrongPassword(_passwordController.text)) {
      setState(() {
        _errorMessage =
            'Password must be at least 8-16 characters long and contain at least 2 of the following: uppercase letters, lowercase letters, numbers, symbols. Common passwords are not allowed.';
      });
      return;
    }

    setState(() {
      _errorMessage = null;
      _isLoading = true;
    });

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );

      // Send email verification
      try {
        await userCredential.user!.sendEmailVerification();
      } catch (_) {
        // Continue anyway, as user can resend later
      }

      // Create user document in Firestore
      try {
        await UserProfileBootstrapService.createUserProfile(
          user: userCredential.user!,
          email: _emailController.text.trim(),
        );
      } catch (_) {
        // Delete the auth user if document creation fails
        await userCredential.user!.delete();
        throw Exception('Failed to create user profile');
      }

      // Sign out to require manual login
      await FirebaseAuth.instance.signOut();

      // Navigate back to login
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = _getErrorMessage(e.code);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'An error occurred during signup. Please try again.';
      });
      // Sign out if signed in
      if (FirebaseAuth.instance.currentUser != null) {
        await FirebaseAuth.instance.signOut();
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'weak-password':
        return 'The password provided is too weak.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'invalid-email':
        return 'The email address is not valid.';
      default:
        return 'An error occurred. Please try again.';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  // ─── Visibility toggle helper ──────────────────────────────────────────────
  Widget _visibilityToggle({
    required bool visible,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(
          visible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
          color: _textSecondary,
          size: 18,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            margin: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _border),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new,
              size: 15,
              color: _textSecondary,
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: _accentSoft,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.person_add_outlined,
                color: _accent,
                size: 16,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'Create Account',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              children: [
                // ── Header ────────────────────────────────────────────────
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.person_add_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Join TransitPH',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Create an account to get started',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 28),

                // ── Form card ─────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _border),
                    boxShadow: [
                      BoxShadow(
                        color: _accent.withOpacity(0.07),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Email
                      AuthTextField(
                        label: 'Email',
                        controller: _emailController,
                        hint: 'you@example.com',
                        prefixIcon: Icons.email_outlined,
                        accent: _accent,
                        border: _border,
                        surfaceAlt: _surfaceAlt,
                        textPrimary: _textPrimary,
                        textSecondary: _textSecondary,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),

                      // Password
                      AuthTextField(
                        label: 'Password',
                        controller: _passwordController,
                        hint: 'Create a strong password',
                        prefixIcon: Icons.lock_outline_rounded,
                        accent: _accent,
                        border: _border,
                        surfaceAlt: _surfaceAlt,
                        textPrimary: _textPrimary,
                        textSecondary: _textSecondary,
                        obscure: !_isPasswordVisible,
                        suffix: _visibilityToggle(
                          visible: _isPasswordVisible,
                          onTap: () => setState(
                              () => _isPasswordVisible = !_isPasswordVisible),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Confirm password
                      AuthTextField(
                        label: 'Confirm Password',
                        controller: _confirmPasswordController,
                        hint: 'Re-enter your password',
                        prefixIcon: Icons.lock_outline_rounded,
                        accent: _accent,
                        border: _border,
                        surfaceAlt: _surfaceAlt,
                        textPrimary: _textPrimary,
                        textSecondary: _textSecondary,
                        obscure: !_isConfirmPasswordVisible,
                        suffix: _visibilityToggle(
                          visible: _isConfirmPasswordVisible,
                          onTap: () => setState(
                            () => _isConfirmPasswordVisible =
                                !_isConfirmPasswordVisible,
                          ),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Password hint
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              size: 14,
                              color: _textSecondary,
                            ),
                            const SizedBox(width: 7),
                            const Expanded(
                              child: Text(
                                'At least 8 characters with 2 of: uppercase, lowercase, numbers, symbols.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Error message
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: _danger.withOpacity(0.07),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: _danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.error_outline_rounded,
                                size: 15,
                                color: _danger,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: _danger,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Sign up button
                      GestureDetector(
                        onTap: _isLoading ? null : _signup,
                        child: Container(
                          width: double.infinity,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: _isLoading
                                ? null
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFF4A7CE0),
                                      Color(0xFF6A9EFF),
                                    ],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                            color: _isLoading ? _border : null,
                            borderRadius: BorderRadius.circular(13),
                            boxShadow: _isLoading
                                ? null
                                : [
                                    BoxShadow(
                                      color: _accent.withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          alignment: Alignment.center,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.person_add_rounded,
                                      color: Colors.white,
                                      size: 17,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Create Account',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Sign in link ───────────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      'Already have an account? ',
                      style: TextStyle(fontSize: 13, color: _textSecondary),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _accent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}