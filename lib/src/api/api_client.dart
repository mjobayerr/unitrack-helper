import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../data/session_store.dart';
import '../models/api_models.dart';

/// Thrown when the session is unrecoverable and the user must sign in again.
class SessionExpiredException implements Exception {
  const SessionExpiredException([this.message = 'Session expired']);
  final String message;
  @override
  String toString() => message;
}

/// Thrown for errors the user can act on — the message comes from the API's
/// `detail` field, which is written for humans.
class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => message;
}

/// The app's single door to the backend.
///
/// Every request carries the access token and transparently refreshes it once
/// on a 401. Access tokens live 15 minutes and a bus route runs longer than
/// that, so without this the app dies mid-trip — which is precisely what the
/// previous build did.
class ApiClient {
  ApiClient({SessionStore store = const SessionStore(), http.Client? httpClient})
    : _store = store,
      _http = httpClient ?? http.Client();

  final SessionStore _store;
  final http.Client _http;

  /// De-duplicates concurrent refreshes. Several requests can 401 at the same
  /// moment — the GPS flush and a dashboard poll, say — and each firing its own
  /// refresh would race, with the losers writing back a stale token pair.
  Future<String>? _refreshInFlight;

  void close() => _http.close();

  // --- auth ---

  /// Exchanges credentials for a token pair. The only call that needs a
  /// password, and the only one made while signed out.
  Future<TokenPair> login({
    required String email,
    required String password,
  }) async {
    final response = await _http
        .post(
          _uri('/auth/login'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'email': email, 'password': password}),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode == 200) {
      return TokenPair.fromJson(_decode(response));
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw ApiException(response.statusCode, _detail(response, 'Wrong email or password'));
    }
    throw ApiException(response.statusCode, _detail(response, 'Could not sign in'));
  }

  Future<HelperProfile> me() async =>
      HelperProfile.fromJson(await _get('/auth/me'));

  // --- fleet ---

  Future<List<Bus>> buses() async {
    final rows = await _getList('/fleet/buses');
    return rows.map(Bus.fromJson).toList();
  }

  Future<List<BusRoute>> routes() async {
    final rows = await _getList('/fleet/routes');
    return rows.map(BusRoute.fromJson).toList();
  }

  // --- trips ---

  Future<Trip> startTrip({required String busId, required String routeId}) async {
    final json = await _post('/helper/trips/start', {
      'bus_id': busId,
      'route_id': routeId,
    });
    return Trip.fromJson(json);
  }

  Future<Trip> endTrip() async => Trip.fromJson(await _post('/helper/trips/end', null));

  /// Null when the helper has no live trip — the app calls this on launch to
  /// recover after a crash or a force-stop.
  Future<ActiveTrip?> activeTrip() async {
    final json = await _getNullable('/helper/trips/active');
    return json == null ? null : ActiveTrip.fromJson(json);
  }

  // --- operations ---

  Future<SeatState> reportSeats(int occupied) async {
    final json = await _post('/helper/seats', {'occupied': occupied});
    return SeatState.fromJson(json);
  }

  Future<void> raiseAlert(
    AlertKind kind, {
    String? message,
    double? lat,
    double? lng,
  }) async {
    await _post('/helper/alerts', {
      'type': kind.wireName,
      'message': ?message,
      'lat': ?lat,
      'lng': ?lng,
    });
  }

  // --- plumbing ---

  Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  Future<Map<String, dynamic>> _get(String path) async =>
      _decode(await _send((h) => _http.get(_uri(path), headers: h)));

  Future<Map<String, dynamic>?> _getNullable(String path) async {
    final response = await _send((h) => _http.get(_uri(path), headers: h));
    final body = response.body.trim();
    if (body.isEmpty || body == 'null') return null;
    return _decode(response);
  }

  Future<List<Map<String, dynamic>>> _getList(String path) async {
    final response = await _send((h) => _http.get(_uri(path), headers: h));
    final decoded = jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> _post(String path, Object? body) async {
    final response = await _send(
      (h) => _http.post(
        _uri(path),
        headers: {...h, 'content-type': 'application/json'},
        body: jsonEncode(body ?? const <String, dynamic>{}),
      ),
    );
    return _decode(response);
  }

  /// Sends with the current access token, refreshing once on a 401.
  ///
  /// Exactly one retry: if the refreshed token is also rejected the problem is
  /// the session, not the token, and retrying again would spin.
  Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    var token = await _store.readAccessToken();
    var response = await request(_authHeader(token)).timeout(AppConfig.requestTimeout);

    if (response.statusCode == 401) {
      token = await _refreshAccessToken();
      response = await request(_authHeader(token)).timeout(AppConfig.requestTimeout);
    }

    if (response.statusCode == 401) throw const SessionExpiredException();
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, _detail(response, 'Request failed'));
    }
    return response;
  }

  Map<String, String> _authHeader(String? token) =>
      token == null ? const {} : {'authorization': 'Bearer $token'};

  Future<String> _refreshAccessToken() {
    // Join the in-flight refresh rather than starting a second one.
    return _refreshInFlight ??= _doRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
  }

  Future<String> _doRefresh() async {
    final refreshToken = await _store.readRefreshToken();
    if (refreshToken == null) throw const SessionExpiredException();

    final response = await _http
        .post(
          _uri('/auth/refresh'),
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'refresh_token': refreshToken}),
        )
        .timeout(AppConfig.requestTimeout);

    if (response.statusCode != 200) {
      // The refresh token is dead: expired, revoked, or the account was
      // suspended. Clear the device so the app returns to the login screen
      // instead of retrying forever against a session that cannot come back.
      await _store.clear();
      throw const SessionExpiredException();
    }

    final pair = TokenPair.fromJson(_decode(response));
    await _store.writeTokens(
      accessToken: pair.accessToken,
      refreshToken: pair.refreshToken,
    );
    return pair.accessToken;
  }

  static Map<String, dynamic> _decode(http.Response response) =>
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

  /// FastAPI puts a human-readable reason in `detail`; fall back when the body
  /// is a validation array or an upstream HTML error page.
  static String _detail(http.Response response, String fallback) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] is String) return body['detail'] as String;
    } catch (_) {
      // Not JSON — fall through.
    }
    return fallback;
  }
}
