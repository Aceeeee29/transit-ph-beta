import 'package:flutter/material.dart';

enum LoginType { user, admin }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  LoginType _loginType = LoginType.user;
  final TextEditingController _userEmailController = TextEditingController();
  final TextEditingController _userPasswordController = TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _adminPasswordController =
      TextEditingController();

  String? _errorMessage;

  void _login() {
    setState(() {
      _errorMessage = null;
    });

    if (_loginType == LoginType.admin) {
      if (_adminEmailController.text == 'admin@example.com' &&
          _adminPasswordController.text == 'admin') {
        Navigator.pushReplacementNamed(
          context,
          '/main',
          arguments: true,
        ); // true for admin
      } else {
        setState(() {
          _errorMessage = 'Invalid admin credentials';
        });
      }
    } else {
      // User login validation (simple example)
      if (_userEmailController.text.isEmpty ||
          _userPasswordController.text.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter email and password';
        });
        return;
      }
      // Proceed with user login
      Navigator.pushReplacementNamed(
        context,
        '/main',
        arguments: false,
      ); // false for user
    }
  }

  @override
  void dispose() {
    _userEmailController.dispose();
    _userPasswordController.dispose();
    _adminEmailController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  // Removed _buildGoogleSignInButton and _buildDivider methods as part of removing the "or" part

  Widget _buildUserLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Email'),
        const SizedBox(height: 4),
        TextField(
          controller: _userEmailController,
          decoration: const InputDecoration(
            hintText: 'you@example.com',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        const Text('Password'),
        const SizedBox(height: 4),
        TextField(
          controller: _userPasswordController,
          decoration: const InputDecoration(
            hintText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _login,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Sign in',
                style: TextStyle(fontSize: 16, color: Colors.white),
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: () {
              // TODO: Implement forgot password
            },
            child: const Text('Forgot password?'),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Need an account? '),
            TextButton(
              onPressed: () {
                // TODO: Implement sign up
              },
              child: const Text('Sign up'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAdminLoginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Email'),
        const SizedBox(height: 4),
        TextField(
          controller: _adminEmailController,
          decoration: const InputDecoration(
            hintText: 'admin@example.com',
            prefixIcon: Icon(Icons.email_outlined),
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 12),
        const Text('Password'),
        const SizedBox(height: 4),
        TextField(
          controller: _adminPasswordController,
          decoration: const InputDecoration(
            hintText: 'Password',
            prefixIcon: Icon(Icons.lock_outline),
            border: OutlineInputBorder(),
          ),
          obscureText: true,
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _login,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Sign in', style: TextStyle(fontSize: 16, color: Colors.white)),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                      Image.asset(
                        'assets/transitph_logo.png',
                        height: 64,
                        width: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Welcome to TransitPH',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Sign in to continue',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 24),

                      ToggleButtons(
                        isSelected: [
                          _loginType == LoginType.user,
                          _loginType == LoginType.admin,
                        ],
                        onPressed: (index) {
                          setState(() {
                            _loginType = LoginType.values[index];
                            _errorMessage = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        selectedColor: Colors.white,
                        fillColor: Colors.blue,
                        color: Colors.black87,
                        constraints: const BoxConstraints(
                          minHeight: 40,
                          minWidth: 120,
                        ),
                        children: const [Text('User'), Text('Admin')],
                      ),
                      const SizedBox(height: 24),
                      if (_errorMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      _loginType == LoginType.user
                          ? _buildUserLoginForm()
                          : _buildAdminLoginForm(),
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
