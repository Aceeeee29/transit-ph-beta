import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import '../../models/route.dart' as route_model;
import '../../services/route_service.dart';
import 'profile_colors.dart';
import 'route_contribution_card.dart';

class ContributionsTab extends StatelessWidget {
  final String userEmail;
  final String distanceUnit;

  const ContributionsTab({
    super.key,
    required this.userEmail,
    required this.distanceUnit,
  });

  @override
  Widget build(BuildContext context) {
    final uid = firebase_auth.FirebaseAuth.instance.currentUser?.uid ?? userEmail;

    return FutureBuilder<List<route_model.Route>>(
      future: RouteService.getRoutesByUser(uid, userEmail: userEmail),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(
              color: ProfileColors.accent,
              strokeWidth: 2,
            ),
          );
        }
        if (snapshot.hasError) {
          return _ErrorState(error: snapshot.error);
        }
        final routes = snapshot.data ?? [];
        if (routes.isEmpty) {
          return const _EmptyState();
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: routes.length,
          itemBuilder: (context, index) => RouteContributionCard(
            route: routes[index],
            userEmail: userEmail,
            distanceUnit: distanceUnit,
          ),
        );
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  final Object? error;
  const _ErrorState({this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: ProfileColors.danger.withOpacity(0.08),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.error_outline_rounded,
              size: 32,
              color: ProfileColors.danger,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Error loading contributions',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: ProfileColors.textPrimary,
            ),
          ),
          Text(
            '$error',
            style: const TextStyle(fontSize: 12, color: ProfileColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: ProfileColors.surfaceAlt,
                borderRadius: BorderRadius.all(Radius.circular(20)),
              ),
              child: Icon(
                Icons.alt_route,
                size: 36,
                color: ProfileColors.textSecondary,
              ),
            ),
          ),
          SizedBox(height: 16),
          Text(
            'No contributions yet',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: ProfileColors.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Start contributing routes to the community!',
            style: TextStyle(fontSize: 13, color: ProfileColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
