import 'package:flutter/material.dart';
import 'business_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../auth/presentation/providers/auth_provider.dart';

class FormContent extends StatefulWidget {
  final Future<void> Function(BuildContext, String, String) onLogin;

  const FormContent({super.key, required this.onLogin});

  @override
  State<FormContent> createState() => _FormContentState();
}

class _FormContentState extends State<FormContent> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    final username =
        prefs.getString('remembered_username') ?? prefs.getString('email');

    // Remove credentials stored by the former mock-login implementation.
    await prefs.remove('password');
    await prefs.remove('isLoggedIn');
    if (!mounted || username == null || username.trim().isEmpty) {
      return;
    }

    _usernameController.text = username.trim();
    setState(() => _rememberMe = true);
  }

  Future<void> _saveRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    if (_rememberMe) {
      await prefs.setString(
        'remembered_username',
        _usernameController.text.trim(),
      );
    } else {
      await prefs.remove('remembered_username');
    }
    await prefs.remove('email');
    await prefs.remove('password');
  }

  @override
  Widget build(BuildContext context) {
    watchBusinessLanguage(context);
    final provider = context.watch<AuthProvider>();
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            key: const ValueKey('login_username'),
            controller: _usernameController,
            enabled: !provider.isLoggingIn,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            validator:
                (value) =>
                    value == null || value.trim().isEmpty
                        ? bt(context, 'username_required')
                        : null,
            onChanged: (_) => provider.clearLoginError(),
            decoration: InputDecoration(
              labelText: bt(context, 'login_username_label'),
              prefixIcon: const Icon(Icons.badge_outlined),
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: const ValueKey('login_password'),
            controller: _passwordController,
            enabled: !provider.isLoggingIn,
            autofillHints: const [AutofillHints.password],
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _submit(),
            validator:
                (value) =>
                    value == null || value.isEmpty
                        ? bt(context, 'password_required')
                        : null,
            onChanged: (_) => provider.clearLoginError(),
            obscureText: !_isPasswordVisible,
            decoration: InputDecoration(
              labelText: bt(context, 'Password'),
              errorMaxLines: 3,
              prefixIcon: const Icon(Icons.lock_outline),
              suffixIcon: IconButton(
                tooltip: bt(
                  context,
                  _isPasswordVisible ? 'Hide password' : 'Show password',
                ),
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed:
                    () => setState(
                      () => _isPasswordVisible = !_isPasswordVisible,
                    ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _rememberMe,
            onChanged:
                provider.isLoggingIn
                    ? null
                    : (value) => setState(() => _rememberMe = value ?? false),
            title: Text(bt(context, 'Remember account')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('login_submit'),
            onPressed: provider.isLoggingIn ? null : _submit,
            child:
                provider.isLoggingIn
                    ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(bt(context, 'Sign in')),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (context.read<AuthProvider>().isLoggingIn) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    await _saveRememberMe();
    if (!mounted) return;
    await widget.onLogin(
      context,
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }
}
