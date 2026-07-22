import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_scope.dart';
import '../state/session_controller.dart';
import 'widgets.dart';

/// Creates the unlock PIN, or unlocks with it.
///
/// One page, two modes, because the layout and the keypad are identical and a
/// second near-duplicate screen would drift.
///
/// The PIN is a *local* key: it decides whether this device may use the refresh
/// token already stored on it. It is never sent to the server, which is what
/// makes four digits acceptable — see data/session_store.dart.
class PinPage extends StatefulWidget {
  const PinPage({super.key});

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  static const int _pinLength = 4;

  String _entry = '';
  String? _firstEntry; // Set while confirming a new PIN.
  String? _localError;

  bool get _isCreating =>
      AppScope.of(context).session.state == SessionState.needsPin;

  Future<void> _onDigit(String digit) async {
    if (_entry.length >= _pinLength) return;
    setState(() {
      _entry += digit;
      _localError = null;
    });
    if (_entry.length == _pinLength) {
      // Let the last dot paint before the screen changes under the user.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (mounted) await _complete();
    }
  }

  void _onBackspace() {
    if (_entry.isEmpty) return;
    setState(() => _entry = _entry.substring(0, _entry.length - 1));
  }

  Future<void> _complete() async {
    final session = AppScope.of(context).session;

    if (!_isCreating) {
      final ok = await session.unlock(_entry);
      if (!ok && mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _entry = '';
          _localError = 'Wrong PIN. Try again.';
        });
      }
      return;
    }

    if (_firstEntry == null) {
      setState(() {
        _firstEntry = _entry;
        _entry = '';
      });
      return;
    }

    if (_firstEntry != _entry) {
      HapticFeedback.heavyImpact();
      setState(() {
        _firstEntry = null;
        _entry = '';
        _localError = 'The PINs did not match. Start again.';
      });
      return;
    }
    await session.createPin(_entry);
  }

  String get _title {
    if (!_isCreating) return 'Enter your PIN';
    return _firstEntry == null ? 'Choose a PIN' : 'Confirm your PIN';
  }

  String get _subtitle {
    if (!_isCreating) return 'Unlock to start your shift';
    return _firstEntry == null
        ? 'Four digits. You will use this every shift.'
        : 'Enter the same four digits again.';
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
            Icon(Icons.lock_outline, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 18),
            Text(
              _title,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            _PinDots(filled: _entry.length, total: _pinLength),
            const SizedBox(height: 20),
            if (_localError != null)
              Text(
                _localError!,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 20),
            _Keypad(onDigit: _onDigit, onBackspace: _onBackspace),
            const SizedBox(height: 12),
            TextButton(
              onPressed: session.signOut,
              child: const Text('Sign in as someone else'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled, required this.total});

  final int filled;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final isFilled = i < filled;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          height: isFilled ? 20 : 16,
          width: isFilled ? 20 : 16,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isFilled ? scheme.primary : scheme.surfaceContainerHighest,
          ),
        );
      }),
    );
  }
}

/// A custom keypad rather than the system numeric keyboard.
///
/// The keys are far larger than a soft-keyboard's, which matters when the user
/// is standing in a moving bus, and it keeps the layout from jumping as the
/// keyboard opens and closes.
class _Keypad extends StatelessWidget {
  const _Keypad({required this.onDigit, required this.onBackspace});

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '', '0', '<'];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // Slightly wider than tall keeps all four rows on a short screen.
        childAspectRatio: 1.6,
        children: [
          for (final key in keys)
            if (key.isEmpty)
              const SizedBox.shrink()
            else if (key == '<')
              _KeypadButton(
                onPressed: onBackspace,
                child: const Icon(Icons.backspace_outlined),
              )
            else
              _KeypadButton(
                onPressed: () => onDigit(key),
                child: Text(
                  key,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.onPressed, required this.child});

  final VoidCallback onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onPressed();
        },
        child: Center(child: child),
      ),
    );
  }
}
