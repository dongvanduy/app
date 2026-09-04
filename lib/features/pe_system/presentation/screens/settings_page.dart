import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../auth/domain/entities/auth_user.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../providers/language_provider.dart';
import '../providers/theme_provider.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final languageProvider = context.watch<LanguageProvider>();
    final user = context.watch<AuthProvider>().user;
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context, 'settings')),
        actions: <Widget>[
          IconButton(
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
            tooltip: AppLocalizations.of(context, 'logout'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            _OperatorCard(user: user),
            const SizedBox(height: 16),
            _SelectorCard(
              icon: Icons.dark_mode_outlined,
              label: AppLocalizations.of(context, 'darkMode'),
              selector: DropdownButton<ThemeMode>(
                value: themeProvider.themeMode,
                dropdownColor: dark ? Colors.grey[700] : Colors.white,
                underline: const SizedBox(),
                items: <DropdownMenuItem<ThemeMode>>[
                  DropdownMenuItem(
                    value: ThemeMode.system,
                    child: Text(AppLocalizations.of(context, 'system')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.light,
                    child: Text(AppLocalizations.of(context, 'light')),
                  ),
                  DropdownMenuItem(
                    value: ThemeMode.dark,
                    child: Text(AppLocalizations.of(context, 'dark')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) themeProvider.setThemeMode(value);
                },
              ),
            ),
            const SizedBox(height: 16),
            _SelectorCard(
              icon: Icons.language,
              label: AppLocalizations.of(context, 'language'),
              selector: DropdownButton<Locale>(
                value: languageProvider.locale,
                dropdownColor: dark ? Colors.grey[700] : Colors.white,
                underline: const SizedBox(),
                items: <DropdownMenuItem<Locale>>[
                  DropdownMenuItem(
                    value: const Locale('vi'),
                    child: Text(AppLocalizations.of(context, 'vietnamese')),
                  ),
                  DropdownMenuItem(
                    value: const Locale('en'),
                    child: Text(AppLocalizations.of(context, 'english')),
                  ),
                  DropdownMenuItem(
                    value: const Locale('zh'),
                    child: Text(AppLocalizations.of(context, 'chinese')),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) languageProvider.setLocale(value);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final currentUser = user;
    final authenticated = currentUser != null;
    final displayText = currentUser == null
        ? 'Chưa xác định được người nhập kho'
        : currentUser.fullName.trim().isEmpty
            ? currentUser.username
            : '${currentUser.fullName} (${currentUser.username})';

    return Card(
      color: authenticated
          ? Colors.blue.withValues(alpha: 0.08)
          : Colors.red.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              authenticated
                  ? Icons.verified_user_outlined
                  : Icons.warning_amber,
              color: authenticated ? Colors.blue.shade700 : Colors.red.shade700,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Người nhập kho'),
                  const SizedBox(height: 2),
                  Text(displayText),
                  if (currentUser?.department.trim().isNotEmpty == true) ...[
                    const SizedBox(height: 4),
                    Text(
                      currentUser!.department,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectorCard extends StatelessWidget {
  const _SelectorCard({
    required this.icon,
    required this.label,
    required this.selector,
  });

  final IconData icon;
  final String label;
  final Widget selector;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final labelWidget = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon),
        const SizedBox(width: 8),
        Flexible(child: Text(label, style: const TextStyle(fontSize: 16))),
      ],
    );
    final selectorWidget = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dark ? Colors.white70 : Colors.black54),
      ),
      child: selector,
    );

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: dark ? Colors.grey[800] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 380) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  labelWidget,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: selectorWidget),
                ],
              );
            }
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Flexible(child: labelWidget),
                const SizedBox(width: 12),
                selectorWidget,
              ],
            );
          },
        ),
      ),
    );
  }
}
