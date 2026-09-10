import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../auth/domain/entities/auth_user.dart';
import 'dashboard_theme.dart';

void showDashboardProfile(BuildContext context, AuthUser user) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: DashboardColors.of(context).surface,
    constraints: const BoxConstraints(maxWidth: 760),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder:
        (context) => DashboardTheme(
          child: Builder(
            builder: (context) {
              final colors = DashboardColors.of(context);
              final fields = [
                ('fullName', user.displayName),
                ('username', user.username),
                ('chineseName', user.chineseName),
                ('email', user.email),
                ('role', user.role),
                ('department', user.department),
                ('cft', user.cft),
              ].where((field) => field.$2.trim().isNotEmpty);
              return SafeArea(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .85,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                AppLocalizations.of(context, 'profile'),
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('close-profile'),
                              tooltip: AppLocalizations.of(context, 'close'),
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final field in fields)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                            field.$1,
                                          ),
                                          style: TextStyle(
                                            color: colors.muted,
                                            fontSize: 13,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        SelectableText(
                                          field.$2,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
  );
}

void showDashboardAppInfo(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const DashboardTheme(child: _AppInfoDialog()),
  );
}

class _AppInfoDialog extends StatefulWidget {
  const _AppInfoDialog();

  @override
  State<_AppInfoDialog> createState() => _AppInfoDialogState();
}

class _AppInfoDialogState extends State<_AppInfoDialog> {
  late final Future<PackageInfo?> _info = _loadInfo();

  Future<PackageInfo?> _loadInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = DashboardColors.of(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      scrollable: true,
      title: Text(AppLocalizations.of(context, 'appInfo')),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Image.asset('assets/logo/logo.png', width: 64, height: 64),
          ),
          const SizedBox(height: 12),
          const Text(
            'FindBoard',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          FutureBuilder<PackageInfo?>(
            future: _info,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      semanticsLabel: AppLocalizations.of(context, 'loading'),
                    ),
                  ),
                );
              }
              final info = snapshot.data;
              final unknown = AppLocalizations.of(context, 'unknownVersion');
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${AppLocalizations.of(context, 'version')}: ${info?.version.isNotEmpty == true ? info!.version : unknown}',
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppLocalizations.of(context, 'buildNumber')}: ${info?.buildNumber.isNotEmpty == true ? info!.buildNumber : unknown}',
                  ),
                ],
              );
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('close-app-info'),
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context, 'close')),
        ),
      ],
    );
  }
}
