import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/localization/app_localizations.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
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
      AppLocalizations.of(context, 'settings'),
    ];
    const icons = [
      Icons.home_outlined,
      Icons.bookmark_border_rounded,
      Icons.settings_outlined,
    ];
    const activeIcons = [
      Icons.home_rounded,
      Icons.bookmark_rounded,
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
          statusBarIconBrightness:
              colors.dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: colors.dark ? Brightness.dark : Brightness.light,
          systemNavigationBarColor: colors.surface,
          systemNavigationBarIconBrightness:
              colors.dark ? Brightness.light : Brightness.dark,
          systemNavigationBarContrastEnforced: false,
        ),
        child: Scaffold(
          backgroundColor: colors.background,
          bottomNavigationBar:
              compact
                  ? DashboardTheme(
                    child: Material(
                      color: colors.surface,
                      child: SafeArea(
                        top: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < labels.length; i++)
                                Expanded(
                                  child: Semantics(
                                    selected: selectedIndex == i,
                                    button: true,
                                    child: InkWell(
                                      key: ValueKey('navigation-tab-$i'),
                                      onTap: () => select(i),
                                      borderRadius: BorderRadius.circular(28),
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4,
                                          horizontal: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              selectedIndex == i
                                                  ? colors.tint
                                                  : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            28,
                                          ),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              selectedIndex == i
                                                  ? activeIcons[i]
                                                  : icons[i],
                                              color:
                                                  selectedIndex == i
                                                      ? colors.accent
                                                      : colors.muted,
                                              size: 26,
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              labels[i],
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                height: 1.2,
                                                color:
                                                    selectedIndex == i
                                                        ? colors.accent
                                                        : colors.muted,
                                                fontWeight:
                                                    selectedIndex == i
                                                        ? FontWeight.w600
                                                        : FontWeight.w400,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
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
                                  MediaQuery.textScalerOf(context).scale(14) <
                                      21
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
                      unselectedLabelTextStyle: TextStyle(color: colors.muted),
                      destinations: [
                        for (var i = 0; i < labels.length; i++)
                          NavigationRailDestination(
                            icon: Icon(icons[i]),
                            selectedIcon: Icon(activeIcons[i]),
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
                    SettingsPage(onLogout: () => _logout(context)),
                  ],
                ),
              ),
            ],
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
