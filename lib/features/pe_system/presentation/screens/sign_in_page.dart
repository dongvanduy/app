import 'package:flutter/material.dart';
import 'package:mobile_app/core/constants/colors.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../widgets/logo.dart';
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
    return Scaffold(
        body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.background, AppColors.buttonBlue],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: MediaQuery.of(context).size.width < 600
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Logo(),
                      FormContent(onLogin: _login),
                    ],
                  )
                : Container(
                    padding: const EdgeInsets.all(32.0),
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: Row(
                      children: [
                        const Expanded(child: Logo()),
                        Expanded(
                          child: FormContent(onLogin: _login),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ));
  }
}
