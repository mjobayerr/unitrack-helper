import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../state/app_scope.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

/// New-helper sign-up.
///
/// A registered helper is `pending_approval` and cannot log in until an admin
/// approves them, so this does not sign anyone in — on success it shows a
/// "waiting for approval" screen and sends them back to login. Setting a
/// password here but a PIN only after the first real sign-in keeps the
/// one-device-one-PIN model intact.
class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _submitted = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(SessionController session) async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();

    final ok = await session.register(
      name: _name.text.trim(),
      email: _email.text.trim(),
      password: _password.text,
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
    );
    if (ok && mounted) setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Watch(
        listenable: session,
        builder: (context) =>
            _submitted ? _PendingApproval() : _form(context, session),
      ),
    );
  }

  Widget _form(BuildContext context, SessionController session) {
    final theme = Theme.of(context);

    return PageBody(
      children: [
        Text(
          'Register as a bus helper',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'An admin approves new helpers before the first sign-in.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (session.error != null) ErrorBanner(message: session.error!),
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter your name' : null,
              ),
              const SizedBox(height: 14),
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
                    ? 'Enter a valid email'
                    : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Phone (optional)',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(session),
                decoration: InputDecoration(
                  labelText: 'Password',
                  helperText: 'At least 8 characters',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                  ),
                ),
                // Mirrors the backend's min_length=8, so the user gets the error
                // inline instead of a round trip and a 422.
                validator: (v) => (v == null || v.length < 8)
                    ? 'Use at least 8 characters'
                    : null,
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
              : const Text('CREATE ACCOUNT'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.go('/login'),
          child: const Text('I already have an account'),
        ),
      ],
    );
  }
}

/// Shown after a successful registration. There is nothing more the helper can
/// do until an admin acts, so this is a dead end by design — back to login.
class _PendingApproval extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageBody(
      center: true,
      children: [
        Icon(
          Icons.mark_email_read_outlined,
          size: 64,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 20),
        Text(
          'Account created',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'An admin needs to approve your account before you can sign in. '
          'You will be able to log in once they do.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: () => context.go('/login'),
          child: const Text('BACK TO SIGN IN'),
        ),
      ],
    );
  }
}
