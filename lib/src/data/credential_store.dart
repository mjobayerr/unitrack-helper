import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers what the helper typed, so they don't retype it every launch.
///
/// The access token goes to the Keystore-backed secure store; the bus id is not
/// a secret and lives in plain preferences.
class CredentialStore {
  const CredentialStore();

  static const _tokenKey = 'unitrack.access_token';
  static const _busIdKey = 'unitrack.bus_id';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<String?> readToken() => _secure.read(key: _tokenKey);

  Future<void> writeToken(String token) =>
      _secure.write(key: _tokenKey, value: token);

  Future<String?> readBusId() async =>
      (await SharedPreferences.getInstance()).getString(_busIdKey);

  Future<void> writeBusId(String busId) async =>
      (await SharedPreferences.getInstance()).setString(_busIdKey, busId);
}
