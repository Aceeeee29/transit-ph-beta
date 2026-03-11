import 'package:flutter/material.dart';
import '../../models/post.dart';
import 'feed_colors.dart';

Color postCategoryColor(PostCategory cat) => switch (cat) {
  PostCategory.safetyAlert => const Color(0xFFE05C6A),
  PostCategory.delayReport => const Color(0xFFE89A3C),
  PostCategory.live => const Color(0xFF3EC97A),
  PostCategory.recommendation => const Color(0xFF9B7FE8),
  PostCategory.routeUpdate => const Color(0xFF3EC9D6),
  _ => FeedColors.accent,
};

String postCategoryLabel(PostCategory cat) => switch (cat) {
  PostCategory.discussion => 'Discussion',
  PostCategory.live => 'Questions',
  PostCategory.underReview => 'Tips',
  PostCategory.routeUpdate => 'Route Update',
  PostCategory.delayReport => 'Delay Report',
  PostCategory.safetyAlert => 'Safety Alert',
  PostCategory.recommendation => 'Recommendation',
  _ => 'Unknown',
};

IconData postCategoryIcon(PostCategory cat) => switch (cat) {
  PostCategory.discussion => Icons.forum_outlined,
  PostCategory.live => Icons.help_outline,
  PostCategory.underReview => Icons.lightbulb_outline,
  PostCategory.routeUpdate => Icons.alt_route,
  PostCategory.delayReport => Icons.schedule,
  PostCategory.safetyAlert => Icons.warning_amber_outlined,
  PostCategory.recommendation => Icons.thumb_up_outlined,
  _ => Icons.label_outline,
};
