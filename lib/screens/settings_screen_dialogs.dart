part of 'settings_screen.dart';

extension _SettingsScreenSections on _SettingsScreenState {
  static const _bg = _SettingsScreenState._bg;
  static const _surface = _SettingsScreenState._surface;
  static const _accent = _SettingsScreenState._accent;
  static const _accentSoft = _SettingsScreenState._accentSoft;
  static const _textPrimary = _SettingsScreenState._textPrimary;
  static const _textSecondary = _SettingsScreenState._textSecondary;
  static const _border = _SettingsScreenState._border;

  Future<void> _clearGeneratedRouteCacheSection() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder:
          (dialogContext) => AlertDialog(
            title: const TranslatedText('Clear Auto-Generated Route Cache?'),
            content: const TranslatedText(
              'This will remove locally cached auto-generated routes for your account. They can be generated again later.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const TranslatedText('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const TranslatedText('Clear Cache'),
              ),
            ],
          ),
    );

    if (shouldClear != true || !mounted) return;

    _setRouteCacheClearing(true);

    try {
      final deleted = await RouteCacheRepository.clearAll();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cleared $deleted cached route(s).')),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to clear cached routes. Please try again.'),
        ),
      );
    } finally {
      if (!mounted) return;
      _setRouteCacheClearing(false);
    }
  }

  Future<void> _changeProfilePhotoSection() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (sheetContext) => Container(
            decoration: const BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 10),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TranslatedText(
                        'Change Profile Photo',
                        style: TextStyle(
                          color: _textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.photo_library_outlined,
                      color: _accent,
                    ),
                    title: const TranslatedText('Choose from Gallery'),
                    onTap: () => Navigator.of(sheetContext).pop('gallery'),
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.camera_alt_outlined,
                      color: _accent,
                    ),
                    title: const TranslatedText('Take Photo'),
                    onTap: () => Navigator.of(sheetContext).pop('camera'),
                  ),
                  if (_photoUrl != null && _photoUrl!.isNotEmpty)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFD14343),
                      ),
                      title: const TranslatedText(
                        'Remove Photo',
                        style: TextStyle(color: Color(0xFFD14343)),
                      ),
                      onTap: () => Navigator.of(sheetContext).pop('remove'),
                    ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
    );

    if (action == null || !mounted) return;

    if (action == 'remove') {
      await _saveProfilePhotoUrl(null);
      return;
    }

    final file =
        action == 'camera'
            ? await MediaService.takePhoto()
            : await MediaService.pickImageFromGallery();
    if (file == null || !mounted) return;

    _setUploadingPhoto(true);
    try {
      final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        throw const MediaUploadException(
          'You must be signed in to change your photo.',
        );
      }
      final url = await MediaService.uploadProfilePhoto(file, uid);
      await _saveProfilePhotoUrl(url);
    } on MediaUploadException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to update photo: $e')));
    } finally {
      if (mounted) _setUploadingPhoto(false);
    }
  }

  Future<void> _saveProfilePhotoUrl(String? url) async {
    try {
      final user = await GamificationService.loadUser();
      user.photoUrl = url;
      await GamificationService.saveUser(user);

      final authUser = firebase_auth.FirebaseAuth.instance.currentUser;
      if (authUser != null) {
        await authUser.updatePhotoURL(url);
      }

      if (!mounted) return;
      _setPhotoUrl(url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            url == null ? 'Photo removed.' : 'Profile photo updated.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save photo: $e')));
    }
  }

  Future<void> _showEditProfileDialogSection() async {
    final controller = TextEditingController(text: _displayName);

    await showDialog<void>(
      context: context,
      builder:
          (dialogContext) => Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accent.withOpacity(0.08),
                    blurRadius: 32,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 18, 16, 16),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                      border: Border(bottom: BorderSide(color: _border)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _accentSoft,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            Icons.edit_outlined,
                            color: _accent,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const TranslatedText(
                          'Edit Profile Name',
                          style: TextStyle(
                            color: _textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: _surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _border),
                      ),
                      child: TextField(
                        controller: controller,
                        autofocus: true,
                        textInputAction: TextInputAction.done,
                        style: const TextStyle(
                          color: _textPrimary,
                          fontSize: 14,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: _textSecondary),
                          prefixIcon: Icon(
                            Icons.person_outline,
                            color: _accent,
                            size: 18,
                          ),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                            vertical: 13,
                            horizontal: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.of(dialogContext).pop(),
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                color: _surface,
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(color: _border),
                              ),
                              alignment: Alignment.center,
                              child: const TranslatedText(
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
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: GestureDetector(
                            onTap: () async {
                              final updatedName = controller.text.trim();
                              if (updatedName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Name cannot be empty.'),
                                  ),
                                );
                                return;
                              }

                              try {
                                final user =
                                    await GamificationService.loadUser();
                                user.name = updatedName;
                                await GamificationService.saveUser(user);

                                final authUser =
                                    firebase_auth
                                        .FirebaseAuth
                                        .instance
                                        .currentUser;
                                if (authUser != null) {
                                  await authUser.updateDisplayName(updatedName);
                                }

                                if (!mounted) return;
                                _setDisplayName(updatedName);

                                Navigator.of(dialogContext).pop();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Profile updated successfully.',
                                    ),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Failed to update profile: $e',
                                    ),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              height: 44,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4A7CE0),
                                    Color(0xFF6A9EFF),
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(11),
                                boxShadow: [
                                  BoxShadow(
                                    color: _accent.withOpacity(0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const TranslatedText(
                                'Save',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
    );
  }
}
