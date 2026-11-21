import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../../core/widgets/app_wave_background.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../../chat/presentation/widgets/chat_unread_badge.dart';
import '../../../chat/presentation/screens/chat_list_screen.dart';
import '../providers/code_provider.dart';
import '../widgets/dashboard_theme.dart';
import '../../../repair_lookup/presentation/screens/repair_lookup_screen.dart';
import 'home_page.dart';
import 'settings_page.dart';
import 'sign_in_page.dart';

class NavigationRailPage extends StatefulWidget {
  const NavigationRailPage({super.key});

  @override
  State<NavigationRailPage> createState() => _NavigationRailPageState();
}

class _NavigationRailPageState extends State<NavigationRailPage> {
  @override
  Widget build(BuildContext context) {
    final selectedIndex = context.select<CodeProvider, int>(
      (p) => p.selectedIndex,
    );
    final colors = DashboardColors.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 900;
    final labels = [
      AppLocalizations.of(context, 'home'),
      AppLocalizations.of(context, 'detail'),
      AppLocalizations.of(context, 'chatTitle'),
      AppLocalizations.of(context, 'settings'),
    ];
    const icons = [
      Icons.home_outlined,
      Icons.bookmark_border_rounded,
      Icons.chat_bubble_outline_rounded,
      Icons.settings_outlined,
    ];
    const activeIcons = [
      Icons.home_rounded,
      Icons.bookmark_rounded,
      Icons.chat_bubble_rounded,
      Icons.settings_rounded,
    ];
    void select(int index) =>
        context.read<CodeProvider>().setSelectedIndex(index);

    return PopScope(
      canPop: selectedIndex != 1,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selectedIndex == 1) select(0);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: colors.dark
              ? Brightness.light
              : Brightness.dark,
          statusBarBrightness: colors.dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: colors.dark
              ? Brightness.light
              : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: AppWaveBackground(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            bottomNavigationBar: compact
                ? SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.dark
                            ? const Color(0xE9232E4A)
                            : const Color(0xEDF7FAFF),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(
                          color: colors.dark
                              ? const Color(0xFF354368)
                              : Colors.white,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF264D92,
                            ).withValues(alpha: colors.dark ? .28 : .16),
                            blurRadius: 18,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Material(
                        type: MaterialType.transparency,
                        child: Padding(
                          padding: const EdgeInsets.all(5),
                          child: Row(
                            children: [
                              for (var i = 0; i < labels.length; i++)
                                Expanded(
                                  child: _NavigationTab(
                                    index: i,
                                    label: labels[i],
                                    icon: selectedIndex == i
                                        ? activeIcons[i]
                                        : icons[i],
                                    selected: selectedIndex == i,
                                    onTap: () => select(i),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : null,
            body: Row(
              children: [
                if (!compact)
                  DashboardTheme(
                    child: SafeArea(
                      right: false,
                      child: NavigationRail(
                        key: const ValueKey('dashboard-rail'),
                        backgroundColor: colors.surface,
                        selectedIndex: selectedIndex,
                        onDestinationSelected: select,
                        extended:
                            width >= 1100 &&
                            MediaQuery.textScalerOf(context).scale(14) < 21,
                        labelType:
                            width >= 1100 &&
                                MediaQuery.textScalerOf(context).scale(14) < 21
                            ? NavigationRailLabelType.none
                            : NavigationRailLabelType.all,
                        useIndicator: true,
                        indicatorColor: colors.tint,
                        selectedIconTheme: IconThemeData(color: colors.accent),
                        unselectedIconTheme: IconThemeData(color: colors.muted),
                        selectedLabelTextStyle: TextStyle(
                          color: colors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                        unselectedLabelTextStyle: TextStyle(
                          color: colors.muted,
                        ),
                        destinations: [
                          for (var i = 0; i < labels.length; i++)
                            NavigationRailDestination(
                              icon: _ChatNavigationIcon(
                                index: i,
                                child: Icon(icons[i]),
                              ),
                              selectedIcon: _ChatNavigationIcon(
                                index: i,
                                child: Icon(activeIcons[i]),
                              ),
                              label: Text(labels[i]),
                            ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: IndexedStack(
                    index: selectedIndex,
                    children: [
                      const HomePage(),
                      RepairLookupScreen(onBack: () => select(0)),
                      const ChatListScreen(embedded: true),
                      SettingsPage(onLogout: () => _logout(context)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final authLogout = context.read<AuthProvider>().logout();
    context.read<CodeProvider>().resetSessionState();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const SignInPage()),
      (route) => false,
    );
    await authLogout;
  }
}

class _ChatNavigationIcon extends StatelessWidget {
  const _ChatNavigationIcon({required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (index != 2) return child;
    return ChatUnreadBadge(child: child);
  }
}

class _NavigationTab extends StatelessWidget {
  const _NavigationTab({
    required this.index,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = selected
        ? Colors.white
        : dark
        ? const Color(0xFFBECBE6)
        : const Color(0xFF414D64);
    final radius = BorderRadius.circular(22);
    return Semantics(
      selected: selected,
      button: true,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: dark
                      ? const [Color(0xFF385FD0), Color(0xFF213A80)]
                      : const [Color(0xFF4B9CF0), Color(0xFF245EE0)],
                )
              : null,
        ),
        child: InkWell(
          key: ValueKey('navigation-tab-$index'),
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ChatNavigationIcon(
                  index: index,
                  child: Icon(icon, size: 23, color: foreground),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.1,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
