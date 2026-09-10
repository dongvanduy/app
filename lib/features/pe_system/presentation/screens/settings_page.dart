import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';
import '../widgets/dashboard_features.dart';
import '../widgets/dashboard_theme.dart';
import '../widgets/dashboard_widgets.dart';
import '../widgets/settings_dialogs.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final user = context.watch<AuthProvider>().user;

    return DashboardPage(
      title: AppLocalizations.of(context, 'settings'),
      scrollKey: 'settings-scroll',
      maxWidth: 760,
      trailing: IconButton(
        key: const ValueKey('logout-header'),
        onPressed: onLogout,
        icon: const Icon(Icons.logout_rounded, size: 26),
        tooltip: AppLocalizations.of(context, 'logout'),
      ),
      child: Builder(
        builder: (context) {
          final colors = DashboardColors.of(context);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _OperatorCard(user: user),
              const SizedBox(height: 16),
              SettingsSection(
                title: AppLocalizations.of(context, 'appearance'),
                children: [
                  SettingsRow(
                    icon: Icons.dark_mode_rounded,
                    title: AppLocalizations.of(context, 'darkMode'),
                    subtitle: AppLocalizations.of(context, 'themeDescription'),
                    selector: _SettingsSelector<ThemeMode>(
                      selectorKey: const ValueKey('theme-selector'),
                      label: AppLocalizations.of(context, 'darkMode'),
                      value: themeProvider.themeMode,
                      items: [
                        for (final item in [
                          (ThemeMode.system, 'system'),
                          (ThemeMode.light, 'light'),
                          (ThemeMode.dark, 'dark'),
                        ])
                          DropdownMenuItem(
                            value: item.$1,
                            child: Text(AppLocalizations.of(context, item.$2)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) themeProvider.setThemeMode(value);
                      },
                    ),
                  ),
                  SettingsRow(
                    icon: Icons.language_rounded,
                    title: AppLocalizations.of(context, 'language'),
                    subtitle: AppLocalizations.of(
                      context,
                      'languageDescription',
                    ),
                    selector: _SettingsSelector<Locale>(
                      selectorKey: const ValueKey('language-selector'),
                      label: AppLocalizations.of(context, 'language'),
                      value: languageProvider.locale,
                      items: [
                        for (final item in [
                          ('vi', 'vietnamese'),
                          ('en', 'english'),
                          ('zh', 'chinese'),
                        ])
                          DropdownMenuItem(
                            value: Locale(item.$1),
                            child: Text(AppLocalizations.of(context, item.$2)),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) languageProvider.setLocale(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SettingsSection(
                title: AppLocalizations.of(context, 'functions'),
                children: [
                  for (final feature in DashboardFeature.settingsOrder)
                    SettingsRow(
                      key: ValueKey('settings-feature-${feature.name}'),
                      icon: feature.icon,
                      color: feature.color,
                      title: AppLocalizations.of(context, feature.titleKey),
                      subtitle: AppLocalizations.of(
                        context,
                        feature.settingsDescriptionKey,
                      ),
                      onTap: () => feature.open(context),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              SettingsSection(
                title: AppLocalizations.of(context, 'other'),
                children: [
                  SettingsRow(
                    key: const ValueKey('app-info'),
                    icon: Icons.info_rounded,
                    color: const Color(0xFF64717D),
                    title: AppLocalizations.of(context, 'appInfo'),
                    subtitle: AppLocalizations.of(
                      context,
                      'appInfoDescription',
                    ),
                    onTap: () => showDashboardAppInfo(context),
                  ),
                  SettingsRow(
                    key: const ValueKey('logout-row'),
                    icon: Icons.logout_rounded,
                    color: colors.danger,
                    title: AppLocalizations.of(context, 'logout'),
                    subtitle: AppLocalizations.of(context, 'logoutDescription'),
                    showChevron: false,
                    onTap: onLogout,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.user});
  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final currentUser = user;
    final parts = currentUser?.displayName.trim().split(RegExp(r'\s+')) ?? [];
    final initials =
        parts.isEmpty
            ? ''
            : [
              parts.first.characters.first,
              if (parts.length > 1) parts.last.characters.first,
            ].join().toUpperCase();

    return DashboardCard(
      key: const ValueKey('operator-card'),
      gradient: true,
      waves: true,
      onTap:
          currentUser == null
              ? null
              : () => showDashboardProfile(context, currentUser),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [DashboardColors.pressed, DashboardColors.blue],
                ),
              ),
              alignment: Alignment.center,
              child:
                  initials.isEmpty
                      ? const Icon(
                        Icons.person_rounded,
                        color: Colors.white,
                        size: 32,
                      )
                      : Text(
                        initials,
                        textScaler: TextScaler.noScaling,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                        ),
                      ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentUser?.displayName ??
                        AppLocalizations.of(context, 'unknownUser'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.25,
                    ),
                  ),
                  if (currentUser != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      currentUser.username,
                      style: TextStyle(
                        fontSize: 15,
                        height: 1.2,
                        color: colors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    AppLocalizations.of(context, 'inventoryOperator'),
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.2,
                      color: colors.muted,
                    ),
                  ),
                  if (currentUser != null &&
                      currentUser.department.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.accent.withValues(alpha: .13),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        currentUser.department,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.2,
                          color: colors.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (currentUser != null) ...[
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right_rounded),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingsSelector<T> extends StatelessWidget {
  const _SettingsSelector({
    required this.selectorKey,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final Key selectorKey;
  final String label;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: (152 * scale).clamp(0, constraints.maxWidth),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.tint,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Semantics(
            label: label,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: selectorKey,
                value: value,
                isExpanded: true,
                itemHeight: null,
                style: TextStyle(color: colors.text, fontSize: 14),
                icon: Icon(
                  Icons.expand_more_rounded,
                  color: colors.muted,
                  size: 20,
                ),
                dropdownColor: colors.surface,
                borderRadius: BorderRadius.circular(14),
                items: items,
                onChanged: onChanged,
              ),
            ),
          ),
        );
      },
    );
  }
}
