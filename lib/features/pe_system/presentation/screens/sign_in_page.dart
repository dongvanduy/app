import 'package:flutter/material.dart';
import '../widgets/business_widgets.dart';
import '../widgets/dashboard_theme.dart';
import '../widgets/dashboard_widgets.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/form_content.dart';
import 'navigation_rail_page.dart';

class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  Future<void> _login(
    BuildContext context,
    String username,
    String password,
  ) async {
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(username, password);
    if (!context.mounted) {
      return;
    }

    if (success && authProvider.isLoggedIn) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const NavigationRailPage()),
        (Route<dynamic> route) => false,
      );
      return;
    }

    final message = authProvider.loginError;
    if (message != null) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    return DashboardTheme(
      child: Builder(
        builder:
            (context) => Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/logo/logo.png',
                            width: 100,
                            height: 100,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'FindBoard',
                            style: TextStyle(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            bt(context, 'signin_hint'),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: DashboardColors.of(context).muted,
                            ),
                          ),
                          const SizedBox(height: 28),
                          DashboardCard(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: FormContent(onLogin: _login),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
      ),
    );
  }
}
