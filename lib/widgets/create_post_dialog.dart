import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../models/post.dart';
import '../models/location.dart';
import '../services/media_service.dart';

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
  final List<File> _selectedImages = [];
  File? _selectedVideo;
  Location? _taggedLocation;
  final List<String> _taggedUsers = [];
  String? _routeId;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

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
    final trimmedContent = _contentController.text.trim();
    if (trimmedContent.isEmpty) return;
    if (trimmedContent.length > _maxPostContentLength) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post must be 500 characters or less.')),
      );
      return;
    }

    final authUser = FirebaseAuth.instance.currentUser;
    final authDisplayName = authUser?.displayName?.trim();
    final authEmail = authUser?.email?.trim();
    final authUid = authUser?.uid.trim();
    final widgetName = widget.currentUserName.trim();
    final firestoreName = await _resolveFirestoreUserName(
      uid: authUid,
      email: authEmail,
    );
    final resolvedUserName = widgetName.isNotEmpty && widgetName != 'User'
        ? widgetName
        : (authDisplayName != null && authDisplayName.isNotEmpty
            ? authDisplayName
            : (firestoreName ?? 'User'));

    final post = Post(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userName: _anonymous ? null : resolvedUserName,
      userEmail: _anonymous ? null : authEmail,
      userId: widget.currentUserId,
      anonymous: _anonymous,
      content: trimmedContent,
      type:
          _selectedVideo != null
              ? PostType.video
              : _selectedImages.isNotEmpty
              ? PostType.image
              : PostType.text,
      category: _selectedCategory,
      timestamp: DateTime.now(),
      imageUrls: _selectedImages.map((file) => file.path).toList(),
      videoUrl: _selectedVideo?.path,
      taggedLocation: _taggedLocation,
      taggedUsers: _taggedUsers,
      routeId: _routeId,
    );

    widget.onPostCreated(post);
    Navigator.of(context).pop();
  }

  Future<String?> _resolveFirestoreUserName({
    String? uid,
    String? email,
  }) async {
    try {
      if (uid != null && uid.isNotEmpty) {
        final byUid = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final name = (byUid.data()?['name'] as String?)?.trim();
        if (name != null && name.isNotEmpty) return name;
      }

      if (email != null && email.isNotEmpty) {
        final byEmail = await FirebaseFirestore.instance
            .collection('users')
            .where('email', isEqualTo: email)
            .limit(1)
            .get();
        if (byEmail.docs.isNotEmpty) {
          final name = (byEmail.docs.first.data()['name'] as String?)?.trim();
          if (name != null && name.isNotEmpty) return name;
        }
      }
    } catch (e) {
      debugPrint('Failed to resolve Firestore user name: $e');
    }

    return null;
  }

  Future<void> _pickImage() async {
    final image = await MediaService.pickImageFromGallery();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
    }
  }

  Future<void> _takePhoto() async {
    final image = await MediaService.takePhoto();
    if (image != null) {
      setState(() {
        _selectedImages.add(image);
      });
    }
  }

  Future<void> _pickVideo() async {
    final video = await MediaService.pickVideoFromGallery();
    if (video != null) {
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  Future<void> _recordVideo() async {
    final video = await MediaService.recordVideo();
    if (video != null) {
      setState(() {
        _selectedVideo = video;
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  void _removeVideo() {
    setState(() {
      _selectedVideo = null;
    });
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
                  color: const Color(0xFF2E7CF6).withOpacity(0.10),
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
                          _buildMediaSection(),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
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
          const Text(
            'New Post',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _surfaceAlt,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.close, color: _textSecondary, size: 18),
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
            style: const TextStyle(
              color: _textPrimary,
              fontSize: 15,
              height: 1.5,
            ),
            decoration: InputDecoration(
              hintText: "What's on your mind?",
              hintStyle: const TextStyle(color: _textSecondary, fontSize: 15),
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

  Widget _buildMediaSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Media'),
        const SizedBox(height: 10),
        // Media action buttons row
        Row(
          children: [
            _mediaChip(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              onTap: _pickImage,
            ),
            const SizedBox(width: 8),
            _mediaChip(
              icon: Icons.camera_alt_outlined,
              label: 'Camera',
              onTap: _takePhoto,
            ),
            const SizedBox(width: 8),
            _mediaChip(
              icon: Icons.video_library_outlined,
              label: 'Video',
              onTap: _pickVideo,
            ),
            const SizedBox(width: 8),
            _mediaChip(
              icon: Icons.videocam_outlined,
              label: 'Record',
              onTap: _recordVideo,
            ),
          ],
        ),

        // Image previews
        if (_selectedImages.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _selectedImages.length,
              itemBuilder: (context, index) {
                return Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                        image: DecorationImage(
                          image: FileImage(_selectedImages[index]),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _danger,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: _danger.withOpacity(0.4),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],

        // Video preview
        if (_selectedVideo != null) ...[
          const SizedBox(height: 12),
          Stack(
            children: [
              Container(
                height: 80,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: const Color(0xFFEAF2FF),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: _accentSoft,
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Icon(
                        Icons.play_arrow,
                        color: _accent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Video attached',
                          style: TextStyle(
                            color: _textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Tap × to remove',
                          style: TextStyle(color: _textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: _removeVideo,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: _danger,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _mediaChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Icon(icon, color: _accent, size: 18),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
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
                        Text(
                          _categoryLabel(cat),
                          style: TextStyle(
                            color: selected ? color : _textSecondary,
                            fontSize: 12,
                            fontWeight:
                                selected ? FontWeight.w600 : FontWeight.w400,
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

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionLabel('Location'),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border),
          ),
          child: TextField(
            style: const TextStyle(color: _textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Tag a route or stop',
              hintStyle: const TextStyle(color: _textSecondary, fontSize: 14),
              prefixIcon: const Icon(
                Icons.location_on_outlined,
                color: _textSecondary,
                size: 18,
              ),
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 12,
              ),
              border: InputBorder.none,
            ),
            onChanged: (value) {
              setState(() {
                _taggedLocation =
                    value.isNotEmpty
                        ? Location(id: value, name: value, type: 'route')
                        : null;
              });
            },
          ),
        ),
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
              Text(
                'Post Anonymously',
                style: TextStyle(
                  color: _anonymous ? _textPrimary : _textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                'Your name won\'t be shown',
                style: const TextStyle(color: _textSecondary, fontSize: 11),
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
              child: const Text(
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
            onTap: _createPost,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A7CE0), Color(0xFF6A9EFF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.send_rounded, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Publish Post',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      letterSpacing: 0.2,
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
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: _textSecondary,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
