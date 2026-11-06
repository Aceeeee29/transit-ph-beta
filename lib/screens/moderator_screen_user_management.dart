part of 'moderator_screen.dart';

extension _ModeratorScreenManagementSections on _ModeratorScreenState {
  static Color get _surface => _ModeratorScreenState._surface;
  static Color get _surfaceAlt => _ModeratorScreenState._surfaceAlt;
  static const _accent = _ModeratorScreenState._accent;
  static Color get _accentSoft => _ModeratorScreenState._accentSoft;
  static Color get _textPrimary => _ModeratorScreenState._textPrimary;
  static Color get _textSecondary => _ModeratorScreenState._textSecondary;
  static Color get _border => _ModeratorScreenState._border;
  static const _danger = _ModeratorScreenState._danger;
  static const _success = _ModeratorScreenState._success;
  static const _warning = _ModeratorScreenState._warning;

  Widget _buildUsersTabSection() {
    final users =
        ModerationService.getUsers()
            .where((u) => u.role == UserRole.user)
            .toList()
          ..sort((a, b) {
            final aName =
                (a.name.trim().isNotEmpty ? a.name : a.email).toLowerCase();
            final bName =
                (b.name.trim().isNotEmpty ? b.name : b.email).toLowerCase();
            return aName.compareTo(bName);
          });

    final query = _userSearchQuery.trim().toLowerCase();
    final filteredUsers =
        users.where((u) {
          if (query.isEmpty) return true;
          return u.name.toLowerCase().contains(query) ||
              u.email.toLowerCase().contains(query);
        }).toList();

    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: (filteredUsers.isEmpty ? 2 : filteredUsers.length + 1),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _userSearchController,
                  onChanged: _setUserSearchQuery,
                  style: TextStyle(
                    color: _textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search users by name or email',
                    hintStyle: TextStyle(color: _textSecondary, fontSize: 13),
                    border: InputBorder.none,
                    icon: Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _textSecondary,
                    ),
                    suffixIcon:
                        _userSearchQuery.isNotEmpty
                            ? IconButton(
                              onPressed: _clearUserSearchQuery,
                              icon: Icon(
                                Icons.close_rounded,
                                size: 18,
                                color: _textSecondary,
                              ),
                            )
                            : null,
                  ),
                ),
              ),
            );
          }

          if (filteredUsers.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  'No users found',
                  style: TextStyle(
                    color: _textSecondary.withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }

          final user = filteredUsers[index - 1];
          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _accentSoft,
                        child: Text(
                          (user.name.isNotEmpty ? user.name[0] : '?')
                              .toUpperCase(),
                          style: const TextStyle(
                            color: _accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              user.email,
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Only restricted users get a tag. Everyone listed here is
                  // a regular user, so a role tag would say nothing.
                  if (user.hasActiveRestriction) ...[
                    const SizedBox(height: 10),
                    _metaChip(
                      Icons.block_outlined,
                      _buildRestrictionLabel(user),
                      _danger,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _actionButton(
                        label:
                            user.hasActiveRestriction
                                ? 'Lift Restriction'
                                : 'Restrict',
                        color: user.hasActiveRestriction ? _success : _danger,
                        filled: user.hasActiveRestriction,
                        lockItem: 'user:${user.uid}',
                        onTap: () async {
                          if (user.uid == null) return;
                          if (user.role != UserRole.user) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Moderator accounts cannot be restricted.',
                                ),
                              ),
                            );
                            return;
                          }
                          final bool saved;
                          if (user.hasActiveRestriction) {
                            saved = await ModerationService.liftUserRestriction(
                              user.uid!,
                            );
                          } else {
                            final choice = await _confirmRestrictUser(user);
                            if (choice == null) return;
                            saved = await ModerationService.restrictUser(
                              user.uid!,
                              days: choice.days,
                              reason: choice.reason,
                              note: choice.note,
                            );
                          }
                          if (!saved && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Couldn\'t save that. Check your connection and try again.',
                                ),
                              ),
                            );
                          }
                          _refreshModeratorState();
                        },
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

  /// Status filter at the top of the Feedback tab, like the dashboard's.
  Widget _feedbackFilterRow() {
    const options = <feedback_model.FeedbackStatus?, String>{
      null: 'All statuses',
      feedback_model.FeedbackStatus.pending: 'Pending',
      feedback_model.FeedbackStatus.resolved: 'Resolved',
      feedback_model.FeedbackStatus.dismissed: 'Dismissed',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<feedback_model.FeedbackStatus?>(
            value: _feedbackFilter,
            isExpanded: true,
            dropdownColor: _surface,
            borderRadius: BorderRadius.circular(12),
            icon: Icon(Icons.expand_more_rounded, color: _textSecondary),
            style: TextStyle(
              color: _textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            items: [
              for (final entry in options.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Row(
                    children: [
                      Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: _textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Text(entry.value),
                    ],
                  ),
                ),
            ],
            onChanged: _setFeedbackFilter,
          ),
        ),
      ),
    );
  }

  Widget _buildFeedbacksTabSection() {
    final filter = _feedbackFilter;
    final feedbacks =
        ModerationService.getFeedbacks()
            .where((f) => f.type == feedback_model.FeedbackType.feedback)
            .where((f) => filter == null || f.status == filter)
            .toList();
    // Appeals come first: a locked-out rider is waiting on them.
    final appealRows = _appealRows(filter);
    // Row 0 is the filter. Then appeals, then feedback (or a note when the
    // filter leaves no feedback).
    final feedbackRows = feedbacks.isEmpty ? 1 : feedbacks.length;
    return RefreshIndicator(
      color: _accent,
      onRefresh: _refreshModeratorPanel,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: 1 + appealRows.length + feedbackRows,
        itemBuilder: (context, index) {
          if (index == 0) return _feedbackFilterRow();
          if (index <= appealRows.length) return appealRows[index - 1];
          if (feedbacks.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Text(
                  filter == null
                      ? 'No feedback yet'
                      : 'No ${filter.name} feedback',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          }
          final feedback = feedbacks[index - 1 - appealRows.length];
          final statusColor =
              feedback.status == feedback_model.FeedbackStatus.pending
                  ? _warning
                  : feedback.status == feedback_model.FeedbackStatus.resolved
                  ? _success
                  : _textSecondary;

          return _panelCard(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: _accentSoft,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.feedback_outlined,
                              size: 16,
                              color: _accent,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            feedback.type.name.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _textPrimary,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: statusColor.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          feedback.status.name,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _surfaceAlt,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      feedback.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: _textPrimary,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    // No sender shown: riders send feedback anonymously.
                    children: [
                      _metaChip(
                        Icons.schedule_outlined,
                        _formatDate(feedback.timestamp),
                        _textSecondary,
                      ),
                      if (feedback.targetId != null)
                        _metaChip(
                          Icons.gps_fixed_outlined,
                          '${feedback.targetType?.name ?? 'unknown'} • ${feedback.targetId}',
                          _success,
                        ),
                    ],
                  ),
                  if (feedback.status ==
                      feedback_model.FeedbackStatus.pending) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          label: 'Resolve',
                          color: _success,
                          lockItem: 'feedback:${feedback.id}',
                          filled: true,
                          onTap: () async {
                            await ModerationService.updateFeedbackStatus(
                              feedback.id,
                              feedback_model.FeedbackStatus.resolved,
                            );
                            _refreshModeratorState();
                          },
                        ),
                        const SizedBox(width: 8),
                        _actionButton(
                          label: 'Dismiss',
                          color: _textSecondary,
                          lockItem: 'feedback:${feedback.id}',
                          // Dismiss keeps the feedback, marked dismissed,
                          // so it still shows under the Dismissed filter.
                          onTap: () async {
                            await ModerationService.updateFeedbackStatus(
                              feedback.id,
                              feedback_model.FeedbackStatus.dismissed,
                            );
                            _refreshModeratorState();
                          },
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _actionButton(
                          label: 'Delete',
                          color: _danger,
                          lockItem: 'feedback:${feedback.id}',
                          onTap: () async {
                            await _deleteFeedbackWithConfirmation(feedback);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
