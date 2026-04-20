import 'package:flutter/material.dart';

class AuthTextField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final Color accent;
  final Color border;
  final Color surfaceAlt;
  final Color textPrimary;
  final Color textSecondary;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboardType;

  const AuthTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    required this.accent,
    required this.border,
    required this.surfaceAlt,
    required this.textPrimary,
    required this.textSecondary,
    this.obscure = false,
    this.suffix,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: textPrimary,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          decoration: BoxDecoration(
            color: surfaceAlt,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscure,
            keyboardType: keyboardType,
            style: TextStyle(color: textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: textSecondary, fontSize: 14),
              prefixIcon: Icon(prefixIcon, color: accent, size: 18),
              suffixIcon: suffix,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: 4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}