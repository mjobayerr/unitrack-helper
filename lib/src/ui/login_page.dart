import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_scope.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

/// One-time sign-in, ideally done at the depot on wifi.
///
/// After this the helper only ever sees the PIN screen, so this is the only
/// place a password is typed on a phone in a bus.
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(SessionController session) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    // Dismiss the keyboard so the error banner is not hidden behind it.
    FocusScope.of(context).unfocus();
    await session.signIn(
      email: _email.text.trim(),
      password: _password.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final theme = Theme.of(context);

    return Scaffold(
      body: Watch(
        listenable: session,
        builder: (context) => PageBody(
          center: true,
          children: [
            Icon(
              Icons.directions_bus_rounded,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 20),
            Text(
              'Helper Portal',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Sign in once. After this you only need your PIN.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            if (session.error != null) ErrorBanner(message: session.error!),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline),
                    ),
                    validator: (v) => (v == null || !v.contains('@'))
                        ? 'Enter your work email'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(session),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        // Typing a long password blind on a phone is the main
                        // reason people mistype it.
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                        tooltip: _obscure ? 'Show password' : 'Hide password',
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter your password' : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: session.busy ? null : () => _submit(session),
              child: session.busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : const Text('SIGN IN'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: session.busy ? null : () => context.push('/register'),
              child: const Text("New helper? Create an account"),
            ),
          ],
        ),
      ),
    );
  }
}
