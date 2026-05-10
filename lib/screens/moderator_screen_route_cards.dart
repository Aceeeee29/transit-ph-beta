part of 'moderator_screen.dart';

extension _ModeratorScreenSections on _ModeratorScreenState {
  static const _surface = _ModeratorScreenState._surface;
  static const _surfaceAlt = _ModeratorScreenState._surfaceAlt;
  static const _accent = _ModeratorScreenState._accent;
  static const _textPrimary = _ModeratorScreenState._textPrimary;
  static const _textSecondary = _ModeratorScreenState._textSecondary;
  static const _border = _ModeratorScreenState._border;
  static const _danger = _ModeratorScreenState._danger;
  static const _success = _ModeratorScreenState._success;
  static const _warning = _ModeratorScreenState._warning;

  Widget _buildRouteReviewCardSection(route_model.Route route) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _warning.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(bottom: BorderSide(color: _warning.withOpacity(0.2))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _warning.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _warning.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.pending_rounded, size: 12, color: _warning),
                      const SizedBox(width: 4),
                      Text(
                        'PENDING REVIEW',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: _warning,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                if (route.isEdited) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _accent.withOpacity(0.35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit_rounded, size: 12, color: _accent),
                        SizedBox(width: 4),
                        Text(
                          'EDITED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: _accent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Spacer(),
                if (route.createdAt != null)
                  Text(
                    _formatDate(route.createdAt!),
                    style: const TextStyle(fontSize: 11, color: _textSecondary),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.trip_origin, size: 14, color: _success),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        route.startLocation,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    width: 2,
                    height: 14,
                    color: _border,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, size: 14, color: _danger),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        route.endLocation,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  route.shortDescription,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (route.eta != null)
                      _metaChip(Icons.timer_outlined, route.eta!, _accent),
                    if (route.price != null)
                      _metaChip(Icons.payments_outlined, route.price!, _success),
                    if (route.distance != null)
                      _metaChip(Icons.straighten_rounded, route.distance!, _textSecondary),
                    _metaChip(Icons.directions_rounded, '${route.steps.length} steps', _textSecondary),
                  ],
                ),
                if (route.audienceTags.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'SUBMITTED TAGS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: route.audienceTags
                        .map((tag) => _metaChip(Icons.sell_outlined, tag, _accent))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 12),
                if (route.steps.isNotEmpty) ...[
                  const Text(
                    'STEPS PREVIEW',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _textSecondary,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...route.steps.take(3).map(
                        (step) => Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _accentFor(step.mode),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  step.mode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  step.instruction,
                                  style: const TextStyle(fontSize: 12, color: _textPrimary),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (route.steps.length > 3)
                    Text(
                      '+ ${route.steps.length - 3} more steps',
                      style: const TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _surfaceAlt,
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              border: Border(top: BorderSide(color: _border)),
            ),
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _openRoutePreview(route),
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: _accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _accent.withOpacity(0.3)),
                    ),
                    alignment: Alignment.center,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.map_outlined, size: 16, color: _accent),
                        SizedBox(width: 6),
                        Text(
                          'Preview Route',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await ModerationService.rejectRoute(route.id);
                          await widget.onRoutesModerated?.call();
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: _danger.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _danger.withOpacity(0.3)),
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.close_rounded, size: 16, color: _danger),
                              SizedBox(width: 6),
                              Text(
                                'Reject',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: _danger,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () async {
                          await ModerationService.approveRoute(route.id);
                          await widget.onRoutesModerated?.call();
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_success.withOpacity(0.9), _success],
                            ),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _success.withOpacity(0.25),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Icon(Icons.verified_rounded, size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Approve',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteFeedbackWithConfirmationSection(
    feedback_model.Feedback feedback, {
    required bool fromDismiss,
  }) async {
    final title = fromDismiss ? 'Dismiss Feedback' : 'Delete Feedback';
    final message = fromDismiss
        ? 'This will dismiss and permanently delete this feedback. Continue?'
        : 'This will permanently delete this resolved feedback. Continue?';

    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        backgroundColor: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: _accent.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _danger.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.warning_amber_rounded,
                        color: _danger,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(false),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: _surfaceAlt,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Cancel',
                            style: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(true),
                        child: Container(
                          height: 40,
                          decoration: BoxDecoration(
                            color: _danger,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: _danger.withOpacity(0.28),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            'Delete',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
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

    if (confirmed != true) return;

    await ModerationService.deleteFeedback(feedback.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fromDismiss
              ? 'Feedback dismissed and deleted'
              : 'Feedback deleted',
        ),
      ),
    );
    _refreshModeratorState();
  }

  Future<int?> _confirmRestrictUserSection(User user) async {
    var typedKeyword = '';
    var selectedDays = ModerationService.maxRestrictionDays;

    final selectedRestrictionDays = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canRestrict = typedKeyword.trim().toUpperCase() == 'RESTRICT';

            return Dialog(
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              backgroundColor: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _danger.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.gpp_bad_rounded,
                              color: _danger,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text(
                              'Confirm User Restriction',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'You are about to restrict ${user.name} for up to 7 days. Type RESTRICT to confirm this action.',
                        style: const TextStyle(
                          fontSize: 13,
                          color: _textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedDays,
                            isExpanded: true,
                            dropdownColor: _surface,
                            style: const TextStyle(
                              color: _textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                            items: List.generate(
                              ModerationService.maxRestrictionDays,
                              (index) => index + 1,
                            ).map((days) {
                              final label = days == 1 ? '1 day' : '$days days';
                              return DropdownMenuItem<int>(
                                value: days,
                                child: Text(label),
                              );
                            }).toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              selectedDays = value;
                              setDialogState(() {});
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: _surfaceAlt,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border),
                        ),
                        child: TextField(
                          onChanged: (value) {
                            typedKeyword = value;
                            setDialogState(() {});
                          },
                          style: const TextStyle(
                            color: _textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: const InputDecoration(
                            hintText: 'Type RESTRICT',
                            hintStyle: TextStyle(
                              color: _textSecondary,
                              fontSize: 13,
                            ),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: _surfaceAlt,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _border),
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Cancel',
                                  style: TextStyle(
                                    color: _textSecondary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: canRestrict
                                  ? () => Navigator.of(context).pop(selectedDays)
                                  : null,
                              child: Container(
                                height: 40,
                                decoration: BoxDecoration(
                                  color: canRestrict
                                      ? _danger
                                      : _danger.withOpacity(0.35),
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: canRestrict
                                      ? [
                                          BoxShadow(
                                            color: _danger.withOpacity(0.28),
                                            blurRadius: 10,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : null,
                                ),
                                alignment: Alignment.center,
                                child: const Text(
                                  'Restrict User',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    return selectedRestrictionDays;
  }

  Widget _buildPendingPostsTabSection() {
    final pendingPosts = _getReportedPendingPosts();
    if (pendingPosts.isEmpty) {
      return _refreshableEmptyState(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                  color: _surfaceAlt,
                  borderRadius: BorderRadius.circular(18)),
              child: const Icon(Icons.check_circle_outline_rounded,
                  size: 32, color: _textSecondary),
            ),
            const SizedBox(height: 14),
            const Text('No reported posts',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: _textPrimary)),
            const SizedBox(height: 6),
            const Text('All clear!',
                style: TextStyle(fontSize: 13, color: _textSecondary)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: pendingPosts.length,
        itemBuilder: (context, index) {
          final post = pendingPosts[index];
          final reportReasons = ModerationService.getFeedbacks()
              .where((f) =>
                  f.type == feedback_model.FeedbackType.report &&
                f.status == feedback_model.FeedbackStatus.pending &&
                  f.targetId == post.id)
              .map((f) => f.content)
              .toList();
          final authorName = post.userName?.trim();
          final authorEmail = post.userEmail?.trim();
          final displayAuthor = (authorName != null && authorName.isNotEmpty)
              ? authorName
              : ((authorEmail != null && authorEmail.isNotEmpty)
                  ? authorEmail
                  : 'Anonymous');
          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.report_problem_outlined,
                            size: 16, color: _danger),
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Reported Post',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    post.content,
                    style: const TextStyle(
                      fontSize: 14,
                      color: _textPrimary,
                      height: 1.4,
                    ),
                  ),
                  if (post.imageUrls.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 90,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: post.imageUrls.length,
                        itemBuilder: (context, index) => Container(
                          width: 90,
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.network(
                            post.imageUrls[index],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image,
                                    color: _textSecondary),
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _metaChip(
                        Icons.person_outline,
                        displayAuthor,
                        _accent,
                      ),
                      if (post.taggedLocation != null)
                        _metaChip(
                          Icons.location_on_outlined,
                          post.taggedLocation!.name,
                          _success,
                        ),
                    ],
                  ),
                  if (reportReasons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _danger.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _danger.withOpacity(0.2)),
                      ),
                      child: Text(
                        'Reported for: ${reportReasons.join(', ')}',
                        style: const TextStyle(
                          color: _danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionButton(
                        label: 'Remove',
                        color: _danger,
                        onTap: () async {
                          await ModerationService.removePostPermanently(post.id);
                          _refreshModeratorState();
                        },
                      ),
                      const SizedBox(width: 8),
                      _actionButton(
                        label: 'Dismiss',
                        color: _success,
                        onTap: () async {
                          await ModerationService.dismissReportedPost(post.id);
                          _refreshModeratorState();
                        },
                        filled: true,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

}
