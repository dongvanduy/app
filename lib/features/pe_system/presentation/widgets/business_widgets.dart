import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../../../../core/localization/language_converter.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/widgets/app_wave_background.dart';
import 'dashboard_theme.dart';
import 'dashboard_widgets.dart';

class BusinessPage extends StatelessWidget {
  const BusinessPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.maxWidth = 1100,
    this.waveBackground = false,
  });
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final double maxWidth;
  final bool waveBackground;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final page = Scaffold(
      backgroundColor: waveBackground ? Colors.transparent : null,
      appBar: AppBar(
        backgroundColor: waveBackground ? Colors.transparent : null,
        title: Text(title, maxLines: 2),
        toolbarHeight: 64 * scale.clamp(1, 2),
        actions: actions,
      ),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: body,
          ),
        ),
      ),
    );
    return waveBackground ? AppWaveBackground(child: page) : page;
  }
}

class BusinessSection extends StatelessWidget {
  const BusinessSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });
  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DashboardCard(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 21,
                    color: DashboardColors.of(context).accent,
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
}

class BusinessEmptyState extends StatelessWidget {
  const BusinessEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.onRetry,
    this.error = false,
  });
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DashboardIcon(
              icon: icon,
              size: 64,
              iconSize: 32,
              circular: true,
              color: error ? colors.danger : null,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: error ? colors.danger : colors.muted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(AppLocalizations.of(context, 'retry')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Event handlers can translate without subscribing outside a build.
String bt(BuildContext context, String key) =>
    LanguageConverter.translate(key, context.read<LanguageProvider>().locale);

/// Screens subscribe once; helpers and asynchronous callbacks use [bt].
void watchBusinessLanguage(BuildContext context) {
  context.watch<LanguageProvider>();
}
