import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../models/post.dart';
import '../models/location.dart';
import '../models/route.dart' as route_model;
import '../services/route_service.dart';
import 'translated_text.dart';
import '../theme/app_colors.dart';

class CreatePostDialog extends StatefulWidget {
  final Function(Post) onPostCreated;
  final String currentUserName;
  final String currentUserId;

  const CreatePostDialog({
    super.key,
    required this.onPostCreated,
    required this.currentUserName,
    required this.currentUserId,
  });

  @override
  State<CreatePostDialog> createState() => _CreatePostDialogState();
}

class _CreatePostDialogState extends State<CreatePostDialog>
    with SingleTickerProviderStateMixin {
  static const int _maxPostContentLength = 500;
  final TextEditingController _contentController = TextEditingController();
  PostCategory _selectedCategory = PostCategory.discussion;
  bool _anonymous = false;
  Location? _taggedLocation;
  final List<String> _taggedUsers = [];
  String? _routeId;
  bool _isPublishing = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  // ─── Color tokens ──────────────────────────────────────────────────────────
  static Color get _bg => AppColors.bg;
  static Color get _surface => AppColors.surface;
  static Color get _surfaceAlt => AppColors.surfaceAlt;
  static const _accent = Color(0xFF0B8FD6);
  static Color get _accentSoft => AppColors.accentSoft;
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  // ─── All original functions unchanged ──────────────────────────────────────

  Future<void> _createPost() async {
    if (_isPublishing) return;
    final trimmedContent = _contentController.text.trim();
    if (trimmedContent.isEmpty) return;
    if (trimmedContent.length > _maxPostContentLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TranslatedText('Post must be 500 characters or less.'),
        ),
      );
      return;
    }

    setState(() => _isPublishing = true);

    try {
      final authUser = FirebaseAuth.instance.currentUser;
      final authDisplayName = authUser?.displayName?.trim();
      final authEmail = authUser?.email?.trim();
      final authUid = authUser?.uid.trim();
      final widgetName = widget.currentUserName.trim();
      final firestoreProfile = await _resolveFirestoreUserProfile(
        uid: authUid,
        email: authEmail,
      );
      // Prefer live sources (Firebase Auth, then Firestore) over the
      // widget-provided name, which can be stale if the profile was
      // edited since this dialog's ancestor last rebuilt.
      final resolvedUserName =
          (authDisplayName != null && authDisplayName.isNotEmpty)
              ? authDisplayName
              : (firestoreProfile.name ??
                  (widgetName.isNotEmpty ? widgetName : 'User'));
      final resolvedPhotoUrl = authUser?.photoURL ?? firestoreProfile.photoUrl;

      final postId = DateTime.now().millisecondsSinceEpoch.toString();

      final post = Post(
        id: postId,
        userName: _anonymous ? null : resolvedUserName,
        userEmail: _anonymous ? null : authEmail,
        userId: widget.currentUserId,
        userPhotoUrl: _anonymous ? null : resolvedPhotoUrl,
        anonymous: _anonymous,
        content: trimmedContent,
        type: PostType.text,
        category: _selectedCategory,
        timestamp: DateTime.now(),
        taggedLocation: _taggedLocation,
        taggedUsers: _taggedUsers,
        routeId: _routeId,
      );

      widget.onPostCreated(post);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      debugPrint('Failed to create post: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: TranslatedText('Failed to publish post. Try again.'),
          ),
        );
        setState(() => _isPublishing = false);
      }
    }
  }

  Future<({String? name, String? photoUrl})> _resolveFirestoreUserProfile({
    String? uid,
    String? email,
  }) async {
    try {
      if (uid != null && uid.isNotEmpty) {
        final byUid =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = byUid.data();
        final name = (data?['name'] as String?)?.trim();
        final photoUrl = (data?['photoUrl'] as String?)?.trim();
        if ((name != null && name.isNotEmpty) ||
            (photoUrl != null && photoUrl.isNotEmpty)) {
          return (
            name: name != null && name.isNotEmpty ? name : null,
            photoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
          );
        }
      }

      if (email != null && email.isNotEmpty) {
        final byEmail =
            await FirebaseFirestore.instance
                .collection('users')
                .where('email', isEqualTo: email)
                .limit(1)
                .get();
        if (byEmail.docs.isNotEmpty) {
          final data = byEmail.docs.first.data();
          final name = (data['name'] as String?)?.trim();
          final photoUrl = (data['photoUrl'] as String?)?.trim();
          return (
            name: name != null && name.isNotEmpty ? name : null,
            photoUrl: photoUrl != null && photoUrl.isNotEmpty ? photoUrl : null,
          );
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve Firestore user profile: $e');
    }

    return (name: null, photoUrl: null);
  }

  // ─── UI Helpers ────────────────────────────────────────────────────────────

  String _categoryLabel(PostCategory cat) => switch (cat) {
    PostCategory.discussion => 'Discussion',
    PostCategory.live => 'Questions',
    PostCategory.underReview => 'Tips',
    PostCategory.routeUpdate => 'Route Update',
    PostCategory.delayReport => 'Delay Report',
    PostCategory.safetyAlert => 'Safety Alert',
    PostCategory.recommendation => 'Recommendation',
  };

  IconData _categoryIcon(PostCategory cat) => switch (cat) {
    PostCategory.discussion => Icons.forum_outlined,
    PostCategory.live => Icons.help_outline,
    PostCategory.underReview => Icons.lightbulb_outline,
    PostCategory.routeUpdate => Icons.alt_route,
    PostCategory.delayReport => Icons.schedule,
    PostCategory.safetyAlert => Icons.warning_amber_outlined,
    PostCategory.recommendation => Icons.thumb_up_outlined,
  };

  Color _categoryColor(PostCategory cat) => switch (cat) {
    PostCategory.safetyAlert => const Color(0xFFE05C6A),
    PostCategory.delayReport => const Color(0xFFE89A3C),
    PostCategory.live => const Color(0xFF5ECC8B),
    PostCategory.recommendation => const Color(0xFF9B7FE8),
    PostCategory.routeUpdate => const Color(0xFF3EC9D6),
    _ => _accent,
  };

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 32,
          ),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 500),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _border, width: 1),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF0B8FD6).withOpacity(0.10),
                  blurRadius: 40,
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHeader(),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTextInput(),
                          const SizedBox(height: 20),
                          _buildCategorySection(),
                          const SizedBox(height: 20),
                          _buildLocationField(),
                          const SizedBox(height: 20),
                          _buildAnonymousToggle(),
                          const SizedBox(height: 24),
                          _buildActions(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(bottom: BorderSide(color: _border, width: 1.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.edit_outlined, color: _accent, size: 18),
          ),
          const SizedBox(width: 12),
          // Expanded, not Flexible + Spacer: those split the free space,
          // leaving the title's unused share as a gap after the X.
          Expanded(
            child: TranslatedText(
              'New Post',
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                color: _textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
          ),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            // Same size and corners as the pencil badge, so the header
            // reads as one even row.
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.close, color: _textSecondary, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: TextField(
            controller: _contentController,
            inputFormatters: [
              LengthLimitingTextInputFormatter(_maxPostContentLength),
            ],
            style: TextStyle(color: _textPrimary, fontSize: 15, height: 1.5),
            decoration: InputDecoration(
              hintText: "What's on your mind?",
              hintStyle: TextStyle(color: _textSecondary, fontSize: 15),
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
            ),
            maxLines: 4,
            minLines: 3,
            maxLength: _maxPostContentLength,
          ),
        ),
      ],
    );
  }

  Widget _buildCategorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Category'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              PostCategory.values.map((cat) {
                final selected = _selectedCategory == cat;
                final color = _categoryColor(cat);
                return GestureDetector(
                  onTap: () => setState(() => _selectedCategory = cat),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? color.withOpacity(0.15) : _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? color.withOpacity(0.7) : _border,
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _categoryIcon(cat),
                          size: 13,
                          color: selected ? color : _textSecondary,
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: TranslatedText(
                            _categoryLabel(cat),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              color: selected ? color : _textSecondary,
                              fontSize: 12,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
        ),
      ],
    );
  }

  Future<void> _showRoutePicker() async {
    final picked = await showModalBottomSheet<route_model.Route>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RoutePickerSheet(),
    );
    if (picked != null && mounted) {
      setState(() {
        _routeId = picked.id;
        _taggedLocation = Location(
          id: picked.id,
          name: '${picked.startLocation} → ${picked.endLocation}',
          type: 'route',
        );
      });
    }
  }

  void _clearTaggedRoute() {
    setState(() {
      _routeId = null;
      _taggedLocation = null;
    });
  }

  Widget _buildLocationField() {
    final hasTag = _taggedLocation != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Location'),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _showRoutePicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: hasTag ? _accent.withOpacity(0.5) : _border,
                width: hasTag ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: hasTag ? _accentSoft : _surfaceAlt,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    hasTag
                        ? Icons.alt_route_rounded
                        : Icons.location_on_outlined,
                    color: hasTag ? _accent : _textSecondary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TranslatedText(
                    hasTag ? _taggedLocation!.name : 'Tag a route or stop',
                    style: TextStyle(
                      color: hasTag ? _textPrimary : _textSecondary,
                      fontSize: 14,
                      fontWeight: hasTag ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasTag)
                  GestureDetector(
                    onTap: _clearTaggedRoute,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: _surfaceAlt,
                        shape: BoxShape.circle,
                        border: Border.all(color: _border),
                      ),
                      child: Icon(Icons.close, size: 13, color: _textSecondary),
                    ),
                  )
                else
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: _textSecondary,
                  ),
              ],
            ),
          ),
        ),
        if (hasTag) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _accent.withOpacity(0.25)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline, size: 13, color: _accent),
                SizedBox(width: 5),
                Flexible(
                  child: TranslatedText(
                    'Route tagged — shown on your post',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                    style: TextStyle(
                      fontSize: 11,
                      color: _accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAnonymousToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _anonymous ? _accent.withOpacity(0.4) : _border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _anonymous ? _accentSoft : _surfaceAlt,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _anonymous ? Icons.visibility_off_outlined : Icons.person_outline,
              color: _anonymous ? _accent : _textSecondary,
              size: 17,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TranslatedText(
                'Post Anonymously',
                style: TextStyle(
                  color: _anonymous ? _textPrimary : _textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              TranslatedText(
                'Your name won\'t be shown',
                style: TextStyle(color: _textSecondary, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          Switch(
            value: _anonymous,
            onChanged: (value) {
              setState(() {
                _anonymous = value;
              });
            },
            activeThumbColor: Colors.white,
            activeTrackColor: _accent,
            inactiveThumbColor: Colors.white,
            inactiveTrackColor: _border,
          ),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              alignment: Alignment.center,
              child: TranslatedText(
                'Cancel',
                style: TextStyle(
                  color: _textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: _isPublishing ? null : _createPost,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient:
                    _isPublishing
                        ? null
                        : const LinearGradient(
                          colors: [Color(0xFF0B8FD6), Color(0xFF2BB5F0)],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                color: _isPublishing ? _border : null,
                borderRadius: BorderRadius.circular(12),
                boxShadow:
                    _isPublishing
                        ? null
                        : [
                          BoxShadow(
                            color: _accent.withOpacity(0.35),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
              ),
              alignment: Alignment.center,
              child:
                  _isPublishing
                      ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: TranslatedText(
                              'Publishing…',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      )
                      : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Flexible(
                            child: TranslatedText(
                              'Publish Post',
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                        ],
                      ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(String label) {
    return TranslatedText(
      label.toUpperCase(),
      style: TextStyle(
        color: _textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

/// Bottom-sheet route picker for tagging a post with an approved route.
class _RoutePickerSheet extends StatefulWidget {
  @override
  State<_RoutePickerSheet> createState() => _RoutePickerSheetState();
}

class _RoutePickerSheetState extends State<_RoutePickerSheet> {
  static const _accent = Color(0xFF0B8FD6);
  static Color get _accentSoft => AppColors.accentSoft;
  static Color get _textPrimary => AppColors.textPrimary;
  static Color get _textSecondary => AppColors.textSecondary;
  static Color get _border => AppColors.border;
  static Color get _surface => AppColors.surface;
  static Color get _bg => AppColors.bg;

  late Future<List<route_model.Route>> _routesFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _routesFuture = RouteService.getAllRoutes();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _accentSoft,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    color: _accent,
                    size: 17,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TranslatedText(
                        'Tag a route',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                      TranslatedText(
                        'Choose an approved route to attach',
                        style: TextStyle(fontSize: 12, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _border),
                    ),
                    child: Icon(Icons.close, size: 16, color: _textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search routes…',
                  hintStyle: TextStyle(color: _textSecondary, fontSize: 14),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: _textSecondary,
                    size: 18,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
                style: TextStyle(color: _textPrimary, fontSize: 14),
                onChanged:
                    (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
          ),
          Flexible(
            child: FutureBuilder<List<route_model.Route>>(
              future: _routesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(
                      color: _accent,
                      strokeWidth: 2,
                    ),
                  );
                }
                final all = snapshot.data ?? [];
                final filtered =
                    _query.isEmpty
                        ? all
                        : all.where((r) {
                          final hay =
                              '${r.startLocation} ${r.endLocation} ${r.shortDescription}'
                                  .toLowerCase();
                          return hay.contains(_query);
                        }).toList();
                if (filtered.isEmpty) {
                  return Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.route_outlined,
                          size: 32,
                          color: _textSecondary,
                        ),
                        SizedBox(height: 10),
                        TranslatedText(
                          'No routes found',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: _textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        TranslatedText(
                          'Try a different search.',
                          style: TextStyle(fontSize: 12, color: _textSecondary),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final route = filtered[i];
                    return GestureDetector(
                      onTap: () => Navigator.of(context).pop(route),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: _accentSoft,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: const Icon(
                                Icons.alt_route,
                                color: _accent,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  TranslatedText(
                                    route.shortDescription.isNotEmpty
                                        ? route.shortDescription
                                        : '${route.startLocation} → ${route.endLocation}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: _textPrimary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  TranslatedText(
                                    '${route.startLocation} → ${route.endLocation}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _textSecondary,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 14,
                              color: _textSecondary,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
