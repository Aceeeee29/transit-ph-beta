import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'legal_documents_screen.dart';

class LegalConsentScreen extends StatefulWidget {
  final User user;
  final String privacyPolicyVersion;
  final String termsVersion;

  const LegalConsentScreen({
    super.key,
    required this.user,
    required this.privacyPolicyVersion,
    required this.termsVersion,
  });

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  static const _bg = Color(0xFFF4F8FF);
  static const _surface = Color(0xFFFFFFFF);
  static const _surfaceAlt = Color(0xFFEAF2FF);
  static const _accent = Color(0xFF2E7CF6);
  static const _textPrimary = Color(0xFF0F1D35);
  static const _textSecondary = Color(0xFF7A92B2);
  static const _border = Color(0xFFD4E4F7);
  static const _danger = Color(0xFFE05C6A);

  bool _acceptPrivacy = false;
  bool _acceptTerms = false;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _acceptAndContinue() async {
    if (_isSubmitting) return;
    if (!_acceptPrivacy || !_acceptTerms) {
      setState(() {
        _error = 'You must accept both documents to continue.';
      });
      return;
    }

    setState(() {
      _error = null;
      _isSubmitting = true;
    });

    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).set({
        'legalAcceptance': {
          'privacyPolicyAccepted': true,
          'termsAccepted': true,
          'privacyPolicyVersion': widget.privacyPolicyVersion,
          'termsVersion': widget.termsVersion,
          'acceptedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save your acceptance. Please try again.';
        _isSubmitting = false;
      });
    }
  }

  Future<void> _declineAndExit() async {
    await FirebaseAuth.instance.signOut();
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          foregroundColor: _textPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          automaticallyImplyLeading: false,
          title: const Text(
            'Required Consent',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _border),
          ),
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'To use TransitPH, you must review and accept both documents below.',
                      style: TextStyle(
                        color: _textSecondary,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _docRow(
                      title: 'Privacy Policy',
                      subtitle: 'Version ${widget.privacyPolicyVersion}',
                      accepted: _acceptPrivacy,
                      onAccepted: (v) => setState(() => _acceptPrivacy = v),
                      onOpen: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalDocumentsScreen(
                              type: LegalDocumentType.privacyPolicy,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    _docRow(
                      title: 'Terms and Conditions',
                      subtitle: 'Version ${widget.termsVersion}',
                      accepted: _acceptTerms,
                      onAccepted: (v) => setState(() => _acceptTerms = v),
                      onOpen: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalDocumentsScreen(
                              type: LegalDocumentType.termsAndConditions,
                            ),
                          ),
                        );
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(
                          color: _danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isSubmitting ? null : _acceptAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _accent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: _isSubmitting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Accept and Continue',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: _isSubmitting ? null : _declineAndExit,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _danger,
                          side: const BorderSide(color: _danger),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Decline and Exit App',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _docRow({
    required String title,
    required String subtitle,
    required bool accepted,
    required ValueChanged<bool> onAccepted,
    required VoidCallback onOpen,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onOpen,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Read document'),
                ),
              ],
            ),
          ),
          Checkbox(
            value: accepted,
            onChanged: (v) => onAccepted(v ?? false),
            activeColor: _accent,
          ),
        ],
      ),
    );
  }
}