import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import 'email_verification_screen.dart';
import 'onboarding_screen.dart';
import 'legal_consent_screen.dart';
import '../models/lockout.dart';
import '../services/account_deletion_service.dart';
import '../services/launch_splash.dart';
import '../services/lockout_service.dart';
import '../theme/app_colors.dart';

class AuthGate extends StatelessWidget {
  final String? quickRouteToken;

  const AuthGate({super.key, this.quickRouteToken});

  // Raised when routes moved to Supabase, so riders see the policy again.
  static const _privacyPolicyVersion = '2026-11-09';
  static const _termsVersion = '2026-10-19';

  // Color tokens
  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;
  static const _danger = Color(0xFFE05C6A);
  static const _maxRestrictionDuration = Duration(days: 7);

  // Shared loading scaffold
  static Widget _loadingScaffold() {
    return Scaffold(
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

  // Every screen but the loading one takes the launch splash down.
  static Widget _ready(Widget screen) {
    LaunchSplash.release();
    return screen;
  }

  static bool _hasAcceptedLatestLegalDocuments(Map<String, dynamic> data) {
    final raw = data['legalAcceptance'];
    if (raw is! Map) return false;
    final legal = raw.cast<String, dynamic>();

    final privacyAccepted = legal['privacyPolicyAccepted'] == true;
    final termsAccepted = legal['termsAccepted'] == true;
    final privacyVersion = legal['privacyPolicyVersion'] as String?;
    final termsVersion = legal['termsVersion'] as String?;

    return privacyAccepted &&
        termsAccepted &&
        privacyVersion == _privacyPolicyVersion &&
        termsVersion == _termsVersion;
  }

  static DateTime? _parseFirestoreDate(dynamic rawValue) {
    if (rawValue is Timestamp) return rawValue.toDate();
    if (rawValue is String) {
      try {
        return DateTime.parse(rawValue);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static DateTime? _restrictionEndsAt(Map<String, dynamic> data) {
    final explicitUntil = _parseFirestoreDate(data['restrictedUntil']);
    if (explicitUntil != null) return explicitUntil.toUtc();

    final status = ((data['status'] as String?) ?? '').trim().toLowerCase();
    if (status != 'restricted') return null;

    final restrictedAt = _parseFirestoreDate(data['restrictedAt']);
    if (restrictedAt != null) {
      return restrictedAt.toUtc().add(_maxRestrictionDuration);
    }

    return DateTime.now().toUtc().add(_maxRestrictionDuration);
  }

  static bool _isRestrictionActive(Map<String, dynamic> data) {
    // A ban wins over any restriction date. An old, ended restriction
    // date left on a banned account must not let it back in.
    final status = ((data['status'] as String?) ?? '').trim().toLowerCase();
    if ((data['isBanned'] as bool? ?? false) || status == 'banned') {
      return true;
    }

    final restrictionEndsAt = _restrictionEndsAt(data);
    return restrictionEndsAt != null &&
        restrictionEndsAt.isAfter(DateTime.now().toUtc());
  }

  static bool _isAdminRole(Map<String, dynamic> data) {
    final role = ((data['role'] as String?) ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    return role == 'moderator' || role == 'superadmin' || role == 'super_admin';
  }

  // Accounts the server has confirmed past consent / onboarding this run.
  // A write the phone shows before the server refuses it can briefly drop
  // those fields. Without this the screen flickered between consent and
  // Home and the rider couldn't use the app.
  static final Set<String> _confirmedLegal = {};
  static final Set<String> _confirmedTutorial = {};

  static Widget _buildAuthedDestination({
    required User user,
    required DocumentSnapshot snapshot,
    required String? quickRouteToken,
    required bool enforceEmailVerification,
  }) {
    final data = (snapshot.data() as Map<String, dynamic>?) ?? {};
    final confirmed =
        !snapshot.metadata.hasPendingWrites && !snapshot.metadata.isFromCache;
    if (confirmed && _hasAcceptedLatestLegalDocuments(data)) {
      _confirmedLegal.add(user.uid);
    }
    if (confirmed && data['hasSeenTutorial'] == true) {
      _confirmedTutorial.add(user.uid);
    }

    final isAdmin = _isAdminRole(data);
    final restrictionEndsAt = _restrictionEndsAt(data);
    final isRestricted = _isRestrictionActive(data);
    final hasSeenTutorial =
        data['hasSeenTutorial'] == true ||
        _confirmedTutorial.contains(user.uid);
    final hasAcceptedLegal =
        _hasAcceptedLatestLegalDocuments(data) ||
        _confirmedLegal.contains(user.uid);

    // Closed from the dashboard: signed out with its own message.
    final status = ((data['status'] as String?) ?? '').trim().toLowerCase();
    if (status == 'closed') {
      return const _RestrictedAccountHandler(closed: true);
    }

    if (isRestricted) {
      // A ban has no end date. Before, it fell into the "restricted"
      // wording, so banned riders were told they were only restricted.
      final isBan = (data['isBanned'] as bool? ?? false) || status == 'banned';
      return _RestrictedAccountHandler(
        restrictedUntil: isBan ? null : restrictionEndsAt,
        isBan: isBan,
      );
    }

    // Email first, then the Privacy Policy and Terms. Admins and Google
    // sign-ins skip the email step like before.
    if (enforceEmailVerification && !isAdmin) {
      final isGoogleUser = user.providerData.any(
        (provider) => provider.providerId == 'google.com',
      );
      if (!user.emailVerified && !isGoogleUser) {
        return EmailVerificationScreen(user: user);
      }
    }

    if (!hasAcceptedLegal) {
      return LegalConsentScreen(
        user: user,
        privacyPolicyVersion: _privacyPolicyVersion,
        termsVersion: _termsVersion,
      );
    }

    if (isAdmin) {
      return MainScreen(isAdmin: true, quickRouteToken: quickRouteToken);
    }

    return hasSeenTutorial
        ? MainScreen(isAdmin: false, quickRouteToken: quickRouteToken)
        : OnboardingScreen(user: user);
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

          // Keep user role/restriction state live so moderation applies immediately
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream:
                FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
            builder: (context, userSnapshot) {
              if (userSnapshot.connectionState == ConnectionState.waiting &&
                  !userSnapshot.hasData) {
                return _loadingScaffold();
              }

              if (userSnapshot.hasError) {
                FirebaseAuth.instance.signOut();
                return _ready(const LoginScreen());
              }

              if (userSnapshot.hasData && userSnapshot.data!.exists) {
                return _ready(
                  _buildAuthedDestination(
                    user: user,
                    snapshot: userSnapshot.data!,
                    quickRouteToken: quickRouteToken,
                    enforceEmailVerification: true,
                  ),
                );
              } else {
                // Deleting the account removes the profile just before the
                // sign-in account. Signing out here would stop that.
                if (AccountDeletionService.inProgress) {
                  return _loadingScaffold();
                }
                // Document may not exist yet. Race between auth event and
                // Firestore write completing. Wait 2 s then retry once.
                return FutureBuilder<DocumentSnapshot>(
                  future: Future.delayed(const Duration(seconds: 2)).then(
                    (_) =>
                        FirebaseFirestore.instance
                            .collection('users')
                            .doc(user.uid)
                            .get(),
                  ),
                  builder: (context, retrySnapshot) {
                    if (retrySnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return _loadingScaffold();
                    }

                    if (retrySnapshot.hasData && retrySnapshot.data!.exists) {
                      return _ready(
                        _buildAuthedDestination(
                          user: user,
                          snapshot: retrySnapshot.data!,
                          quickRouteToken: quickRouteToken,
                          enforceEmailVerification: false,
                        ),
                      );
                    }

                    // Still no document after retry. Sign out
                    if (AccountDeletionService.inProgress) {
                      return _loadingScaffold();
                    }
                    FirebaseAuth.instance.signOut();
                    return _ready(const LoginScreen());
                  },
                );
              }
            },
          );
        } else {
          // User is not signed in
          return _ready(const LoginScreen());
        }
      },
    );
  }
}

class _RestrictedAccountHandler extends StatefulWidget {
  final DateTime? restrictedUntil;

  /// Banned for good (no end date), not restricted for a time.
  final bool isBan;

  /// Closed for good (dashboard "Close account"), not restricted for a time.
  final bool closed;

  const _RestrictedAccountHandler({
    this.restrictedUntil,
    this.isBan = false,
    this.closed = false,
  });

  @override
  State<_RestrictedAccountHandler> createState() =>
      _RestrictedAccountHandlerState();
}

class _RestrictedAccountHandlerState extends State<_RestrictedAccountHandler> {
  bool _dialogShown = false;

  // The open popup, so it can be closed if the gate moves on without it.
  BuildContext? _dialogContext;

  // On sign-in the phone first reads its saved copy of the profile, which
  // can still say "restricted" after the dashboard lifted it. Ask the server
  // once before showing the popup. Offline, trust the saved copy.
  // Gives back the profile while the rider is still locked out, else null.
  Future<Map<String, dynamic>?> _stillBlocked() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const {};
    final users = FirebaseFirestore.instance.collection('users');
    try {
      final fresh = await users
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      final data = fresh.data() ?? {};
      final status = ((data['status'] as String?) ?? '').trim().toLowerCase();
      final blocked = status == 'closed' || AuthGate._isRestrictionActive(data);
      return blocked ? data : null;
    } catch (_) {
      try {
        final cached = await users
            .doc(uid)
            .get(const GetOptions(source: Source.cache));
        return cached.data() ?? const {};
      } catch (_) {
        return const {};
      }
    }
  }

  @override
  void dispose() {
    // The restriction was lifted while the popup was up: close it, or it
    // stays on top of Home.
    final dialogContext = _dialogContext;
    if (dialogContext != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!dialogContext.mounted) return;
        final route = ModalRoute.of(dialogContext);
        if (route != null && route.isActive) {
          Navigator.of(dialogContext).removeRoute(route);
        }
      });
    }
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dialogShown) return;
    _dialogShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Lifted already: the live profile update takes the gate to Home.
      final userData = await _stillBlocked();
      if (userData == null || !mounted) return;

      // The reason and any appeal. A closed account has neither.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      LockoutDetails? details;
      if (!widget.closed && uid != null) {
        details = await LockoutService.loadDetails(uid, userData);
      }
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          _dialogContext = ctx;
          return _LockoutDialog(
            closed: widget.closed,
            isBan: details?.isBan ?? widget.isBan,
            restrictedUntil: widget.restrictedUntil,
            details: details,
            userData: userData,
          );
        },
      );
      _dialogContext = null;

      if (!mounted) return;
      await FirebaseAuth.instance.signOut();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuthGate._loadingScaffold();
  }
}

/// The popup a banned, restricted or closed account sees before it's
/// signed out. It says what happened and why, and lets the rider appeal
/// once per ban or restriction.
class _LockoutDialog extends StatefulWidget {
  final bool closed;
  final bool isBan;
  final DateTime? restrictedUntil;
  final LockoutDetails? details;
  final Map<String, dynamic> userData;

  const _LockoutDialog({
    required this.closed,
    required this.isBan,
    required this.restrictedUntil,
    required this.details,
    required this.userData,
  });

  @override
  State<_LockoutDialog> createState() => _LockoutDialogState();
}

class _LockoutDialogState extends State<_LockoutDialog> {
  late LockoutDetails? _details = widget.details;

  static String _formatDateTime(DateTime when) {
    final local = when.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$month/$day/${local.year} at $hour:$minute $period';
  }

  String get _title {
    if (widget.closed) return 'Account Closed';
    return widget.isBan ? 'Account Banned' : 'Account Restricted';
  }

  String get _message {
    if (widget.closed) {
      return 'This TransitPH account has been closed. Contact support if you think this was a mistake.';
    }
    if (widget.isBan) {
      return 'Your TransitPH account has been banned for breaking the Terms. You can\'t sign in with it anymore.';
    }
    final until = widget.restrictedUntil;
    if (until == null) {
      return 'Your TransitPH account is restricted for a while. You can sign in again once it ends.';
    }
    return 'Your TransitPH account is restricted until ${_formatDateTime(until)}. You can sign in again after that.';
  }

  // One appeal per ban or restriction, and none for a closed account.
  bool get _canAppeal =>
      !widget.closed && _details != null && _details!.appeal == null;

  Future<void> _openAppeal() async {
    final details = _details;
    if (details == null) return;
    final appeal = await showDialog<Appeal>(
      context: context,
      barrierDismissible: false,
      builder:
          (_) => _AppealDialog(details: details, userData: widget.userData),
    );
    if (appeal == null || !mounted) return;
    setState(() => _details = details.withAppeal(appeal));
  }

  @override
  Widget build(BuildContext context) {
    final record = _details?.record;
    final appeal = _details?.appeal;

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        decoration: BoxDecoration(
          color: AuthGate._surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuthGate._border),
          boxShadow: [
            BoxShadow(
              color: AppColors.accentSoft,
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: SingleChildScrollView(
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
                      color: AuthGate._danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.isBan || widget.closed
                          ? Icons.block_rounded
                          : Icons.gpp_bad_rounded,
                      color: AuthGate._danger,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _title,
                      style: TextStyle(
                        color: AuthGate._textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _message,
                style: TextStyle(
                  color: AuthGate._textSecondary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
              if (record != null) ...[
                const SizedBox(height: 14),
                _ReasonBox(record: record),
              ],
              if (appeal != null) ...[
                const SizedBox(height: 14),
                _AppealStatusBox(appeal: appeal),
              ] else if (_canAppeal) ...[
                const SizedBox(height: 12),
                Text(
                  'If you think this was a mistake, you can appeal once.',
                  style: TextStyle(
                    color: AuthGate._textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (_canAppeal) ...[
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AuthGate._accent,
                        side: const BorderSide(color: AuthGate._accent),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: _openAppeal,
                      child: const Text(
                        'Appeal',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  FilledButton(
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      'OK',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Why the account was locked: the reason staff picked, the rule in the
/// Terms it breaks, and staff's own note.
class _ReasonBox extends StatelessWidget {
  final LockoutRecord record;

  const _ReasonBox({required this.record});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AuthGate._danger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuthGate._danger.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Reason',
            style: TextStyle(
              color: AuthGate._textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            record.reasonLabel,
            style: TextStyle(
              color: AuthGate._textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (record.termsSection.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Against the ${record.termsSection}',
              style: TextStyle(color: AuthGate._textSecondary, fontSize: 12),
            ),
          ],
          if (record.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              record.note,
              style: TextStyle(
                color: AuthGate._textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the rider's appeal stands: still waiting, or reviewed with the
/// decision kept (plus staff's reply, if they wrote one).
class _AppealStatusBox extends StatelessWidget {
  final Appeal appeal;

  const _AppealStatusBox({required this.appeal});

  @override
  Widget build(BuildContext context) {
    final upheld = appeal.status == AppealStatus.upheld;
    final title = upheld ? 'Appeal reviewed' : 'Appeal sent';
    final body =
        upheld
            ? 'We looked at your appeal and the decision stands.'
            : 'We\'ll review it. The decision will show here the next time you open TransitPH.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AuthGate._border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: AuthGate._textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              color: AuthGate._textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (upheld && appeal.reply.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'From the TransitPH team: ${appeal.reply}',
              style: TextStyle(
                color: AuthGate._textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where the rider writes their appeal. Closes with the sent appeal, or
/// with nothing when they cancel.
class _AppealDialog extends StatefulWidget {
  final LockoutDetails details;
  final Map<String, dynamic> userData;

  const _AppealDialog({required this.details, required this.userData});

  @override
  State<_AppealDialog> createState() => _AppealDialogState();
}

class _AppealDialogState extends State<_AppealDialog> {
  final _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  // "It wasn't me" is too little to review. Ask for a real sentence.
  static const _minLength = 10;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final text = _controller.text.trim();
    if (text.length < _minLength) {
      setState(() => _error = 'Please explain a little more.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final appeal = await LockoutService.sendAppeal(
        userData: widget.userData,
        details: widget.details,
        message: text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(appeal);
    } catch (e) {
      debugPrint('[Lockout] appeal send failed: $e');
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error =
            'Couldn\'t send your appeal. Check your connection and try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        decoration: BoxDecoration(
          color: AuthGate._surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AuthGate._border),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Appeal',
                style: TextStyle(
                  color: AuthGate._textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tell us why you think this decision should change. You can only send one appeal, so include everything you want us to know.',
                style: TextStyle(
                  color: AuthGate._textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                enabled: !_sending,
                minLines: 4,
                maxLines: 8,
                maxLength: LockoutService.maxAppealLength,
                style: TextStyle(color: AuthGate._textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Your message',
                  hintStyle: TextStyle(color: AuthGate._textSecondary),
                  filled: true,
                  fillColor: AuthGate._bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AuthGate._border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AuthGate._border),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(color: AuthGate._danger, fontSize: 13),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed:
                        _sending ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: AuthGate._textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AuthGate._accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _sending ? null : _send,
                    child:
                        _sending
                            ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Text(
                              'Send appeal',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
