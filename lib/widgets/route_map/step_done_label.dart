import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// Marks a step the traveler has already finished while following a route.
class StepDoneLabel extends StatelessWidget {
  const StepDoneLabel({super.key});

  /// The struck-through look of a finished step's text.
  static TextStyle strike(TextStyle style) => style.copyWith(
    decoration: TextDecoration.lineThrough,
    decorationColor: style.color,
  );

  @override
  Widget build(BuildContext context) {
    final green = AppColors.tintText(Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tint(Colors.green),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_rounded, size: 12, color: green),
          const SizedBox(width: 3),
          Text(
            'Done',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: green,
            ),
          ),
        ],
      ),
    );
  }
}
