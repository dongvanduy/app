import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/dashboard_features.dart';
import '../widgets/dashboard_theme.dart';
import '../widgets/dashboard_widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DashboardPage(
      scrollKey: 'home-scroll',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WelcomeCard(),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth + 32;
              final largeText =
                  MediaQuery.textScalerOf(context).scale(16) >= 24;
              final columns = width < 320 || (width < 600 && largeText)
                  ? 1
                  : width < 600
                  ? 2
                  : width < 1000
                  ? 3
                  : 4;
              final features = DashboardFeature.homeOrder;
              return Column(
                children: [
                  for (
                    var start = 0;
                    start < features.length;
                    start += columns
                  ) ...[
                    if (start > 0) const SizedBox(height: 10),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var offset = 0; offset < columns; offset++) ...[
                            if (offset > 0) const SizedBox(width: 10),
                            Expanded(
                              child: start + offset < features.length
                                  ? _FunctionCard(
                                      feature: features[start + offset],
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final colors = DashboardColors.of(context);
    final name = user == null
        ? AppLocalizations.of(context, 'unknownUser')
        : user.fullName.trim().isEmpty
        ? user.username
        : '${user.displayName} (${user.username})';
    return DashboardCard(
      gradient: true,
      waves: true,
      color: colors.dark ? const Color(0xFF172441) : const Color(0xFFF8FAFF),
      tint: colors.dark ? const Color(0xFF203C60) : const Color(0xFFCFE5FC),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            const DashboardIcon(
              icon: Icons.person_rounded,
              size: 55,
              iconSize: 31,
              circular: true,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppLocalizations.of(context, 'greeting'),
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppLocalizations.of(context, 'welcomeMessage'),
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FunctionCard extends StatelessWidget {
  const _FunctionCard({required this.feature});
  final DashboardFeature feature;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final surface = colors.dark
        ? const Color(0xFF18213A)
        : const Color(0xFFFAFCFF);
    final tint = Color.alphaBlend(
      feature.color.withValues(alpha: colors.dark ? .19 : .13),
      surface,
    );
    return DashboardCard(
      key: ValueKey('home-feature-${feature.name}'),
      onTap: () => feature.open(context),
      gradient: true,
      color: Color.lerp(surface, tint, .45),
      tint: tint,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: DashboardIcon(
                icon: feature.icon,
                color: feature.color,
                size: 58,
                iconSize: 33,
                circular: true,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    AppLocalizations.of(context, feature.titleKey),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.accent,
                  size: 19,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              AppLocalizations.of(context, feature.homeDescriptionKey),
              style: TextStyle(
                fontSize: 12.5,
                color: colors.muted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
