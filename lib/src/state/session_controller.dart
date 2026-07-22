import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../data/session_store.dart';


/// Where the app is in the sign-in journey.
///
/// `locked` is the normal state on every launch after the first: the tokens are
/// on the device but the PIN has not been entered yet.
enum SessionState { unknown, signedOut, needsPin, locked, ready }

/// Owns authentication for the whole app.
///
/// The router listens to this and redirects on every change, so no page has to
/// check "am I signed in" for itself — a check that is easy to forget on the
/// one page where it matters.
class SessionController extends ChangeNotifier {
  SessionController({required ApiClient api, SessionStore store = const SessionStore()})
    : _api = api,
      _store = store;

  final ApiClient _api;
  final SessionStore _store;

  SessionState _state = SessionState.unknown;
  String? _displayName;
  String? _error;
  bool _busy = false;

  SessionState get state => _state;
  String? get displayName => _displayName;
  String? get error => _error;
  bool get busy => _busy;

  /// Decides the opening screen. Called once at startup.
  Future<void> bootstrap() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) {
      _set(SessionState.signedOut);
      return;
    }
    _displayName = await _store.readDisplayName();
    _set(await _store.hasPin() ? SessionState.locked : SessionState.needsPin);
  }

  /// Full sign-in. Happens once per device, ideally at the depot on wifi.
  Future<void> signIn({required String email, required String password}) async {
    await _guard(() async {
      final pair = await _api.login(email: email, password: password);
      await _store.writeTokens(
        accessToken: pair.accessToken,
        refreshToken: pair.refreshToken,
      );

      // Fetch the profile now so the dashboard has a name to greet without a
      // round trip, and so a non-helper account fails here rather than later
      // with a confusing 403 on the first trip action.
      final profile = await _api.me();
      _displayName = profile.name;
      await _store.writeDisplayName(profile.name);

      _set(SessionState.needsPin);
    });
  }

  /// Sets the unlock PIN right after signing in.
  Future<void> createPin(String pin) async {
    await _guard(() async {
      await _store.setPin(pin);
      _set(SessionState.ready);
    });
  }

  /// Unlocks an existing session. Wrong PINs never reach the network.
  Future<bool> unlock(String pin) async {
    if (await _store.verifyPin(pin)) {
      _error = null;
      _set(SessionState.ready);
      return true;
    }
    _error = 'Wrong PIN';
    notifyListeners();
    return false;
  }

  /// Wipes the device. Also called by the router when the API reports the
  /// session is unrecoverable.
  Future<void> signOut() async {
    await _store.clear();
    _displayName = null;
    _error = null;
    _set(SessionState.signedOut);
  }

  Future<void> _guard(Future<void> Function() action) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } on SessionExpiredException {
      await signOut();
      _error = 'Session expired. Sign in again.';
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      // Almost always no route to the backend: wrong base URL, or the emulator
      // pointed at localhost instead of 10.0.2.2.
      _error = 'Cannot reach the server. Check your connection.';
      debugPrint('signIn failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void _set(SessionState next) {
    _state = next;
    notifyListeners();
  }
}
