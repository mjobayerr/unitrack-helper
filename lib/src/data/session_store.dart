import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Everything that survives an app restart and must not leak.
///
/// The security model, in one paragraph: the helper signs in **once** with
/// email and password. The long-lived refresh token is then kept in
/// Keystore-backed secure storage, and a 4-digit PIN unlocks it locally on
/// every later launch. The PIN is never sent anywhere — so its tiny keyspace
/// (10,000 values) is not an online attack surface, and an attacker needs
/// physical possession of an unlocked device plus the PIN plus the ability to
/// read the Keystore. A 4-digit PIN authenticating against a public endpoint,
/// which is the obvious reading of the design, would be brute-forced in
/// minutes.
class SessionStore {
  const SessionStore();

  static const _accessTokenKey = 'unitrack.access_token';
  static const _refreshTokenKey = 'unitrack.refresh_token';
  static const _pinSaltKey = 'unitrack.pin_salt';
  static const _pinHashKey = 'unitrack.pin_hash';
  static const _displayNameKey = 'unitrack.display_name';

  static const FlutterSecureStorage _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // --- tokens ---

  Future<String?> readAccessToken() => _secure.read(key: _accessTokenKey);
  Future<String?> readRefreshToken() => _secure.read(key: _refreshTokenKey);

  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _secure.write(key: _accessTokenKey, value: accessToken);
    await _secure.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> writeAccessToken(String accessToken) =>
      _secure.write(key: _accessTokenKey, value: accessToken);

  Future<String?> readDisplayName() => _secure.read(key: _displayNameKey);

  Future<void> writeDisplayName(String name) =>
      _secure.write(key: _displayNameKey, value: name);

  /// Wipes the device. Called on sign-out and whenever the refresh token is
  /// rejected — a session we cannot renew is worse than no session, because the
  /// app would otherwise sit in a permanent silent-failure loop.
  Future<void> clear() async {
    await _secure.delete(key: _accessTokenKey);
    await _secure.delete(key: _refreshTokenKey);
    await _secure.delete(key: _pinSaltKey);
    await _secure.delete(key: _pinHashKey);
    await _secure.delete(key: _displayNameKey);
  }

  // --- PIN ---

  Future<bool> hasPin() async => (await _secure.read(key: _pinHashKey)) != null;

  /// Stores a *verifier*, never the PIN. A random salt makes the 10,000
  /// possible hashes distinct per install, so a stolen store cannot be matched
  /// against a precomputed table.
  Future<void> setPin(String pin) async {
    final salt = _randomSalt();
    final hash = _derive(pin, salt);
    await _secure.write(key: _pinSaltKey, value: base64Encode(salt));
    await _secure.write(key: _pinHashKey, value: base64Encode(hash));
  }

  Future<bool> verifyPin(String pin) async {
    final saltB64 = await _secure.read(key: _pinSaltKey);
    final hashB64 = await _secure.read(key: _pinHashKey);
    if (saltB64 == null || hashB64 == null) return false;

    final expected = base64Decode(hashB64);
    final actual = _derive(pin, base64Decode(saltB64));
    return _constantTimeEquals(expected, actual);
  }

  static Uint8List _randomSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  /// PBKDF2-HMAC-SHA256. The iteration count is what makes a 4-digit PIN
  /// non-trivial to grind offline: without it, all 10,000 candidates fall in
  /// microseconds against a stolen store.
  static Uint8List _derive(String pin, Uint8List salt, {int iterations = 120000}) {
    final hmac = Hmac(sha256, utf8.encode(pin));
    // Single output block (32 bytes) is all we need, so this is PBKDF2 with
    // dkLen == hLen: block index 1, big-endian, appended to the salt.
    var block = Uint8List.fromList(hmac.convert([...salt, 0, 0, 0, 1]).bytes);
    final result = Uint8List.fromList(block);
    for (var i = 1; i < iterations; i++) {
      block = Uint8List.fromList(hmac.convert(block).bytes);
      for (var j = 0; j < result.length; j++) {
        result[j] ^= block[j];
      }
    }
    return result;
  }

  /// Compares every byte regardless of where the first difference is, so the
  /// time taken leaks nothing about how much of the PIN was correct.
  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
