import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:unitrack_helper/src/api/api_client.dart';
import 'package:unitrack_helper/src/data/session_store.dart';
import 'package:unitrack_helper/src/models/gps_fix.dart';

/// In-memory stand-in for the Keystore-backed store.
///
/// Overrides only what [ApiClient] touches, so it never reaches a platform
/// channel — these tests run on the Dart VM with no device attached.
class _FakeStore extends SessionStore {
  _FakeStore({this.accessToken = 'access-1'});

  String? accessToken;
  String? refreshToken = 'refresh-1';
  bool cleared = false;

  @override
  Future<String?> readAccessToken() async => accessToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    this.accessToken = accessToken;
    this.refreshToken = refreshToken;
  }

  @override
  Future<void> clear() async {
    cleared = true;
    accessToken = null;
    refreshToken = null;
  }
}

final _fix = GpsFix(
  lat: 23.78,
  lng: 90.40,
  ts: DateTime.utc(2026, 7, 23, 10),
  speed: 8.5,
);

void main() {
  test('posts a batch in the shape the backend schema accepts', () async {
    late Map<String, dynamic> sent;
    final client = ApiClient(
      store: _FakeStore(),
      httpClient: MockClient((request) async {
        expect(request.url.path, '/helper/gps');
        expect(request.headers['authorization'], 'Bearer access-1');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'accepted': 1, 'bus_id': 'bus-1', 'trip_id': null}),
          202,
        );
      }),
    );

    final accepted = await client.postGps(busId: 'bus-1', fixes: [_fix]);

    expect(accepted, 1);
    expect(sent['bus_id'], 'bus-1');
    final points = sent['points'] as List<dynamic>;
    expect(points, hasLength(1));
    final point = points.single as Map<String, dynamic>;
    expect(point['lat'], 23.78);
    expect(point['lng'], 90.40);
    expect(point['speed'], 8.5);
  });

  test('timestamps are sent as UTC even when the device clock is not', () async {
    late Map<String, dynamic> sent;
    final client = ApiClient(
      store: _FakeStore(),
      httpClient: MockClient((request) async {
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'accepted': 1, 'bus_id': 'b'}), 202);
      }),
    );

    // A device in Dhaka (UTC+6) reporting 16:00 local means 10:00 UTC.
    final local = DateTime.utc(2026, 7, 23, 10).toLocal();
    await client.postGps(
      busId: 'b',
      fixes: [GpsFix(lat: 1, lng: 2, ts: local)],
    );

    final ts = (sent['points'] as List<dynamic>).single as Map<String, dynamic>;
    expect(ts['ts'], endsWith('Z'), reason: 'must be serialised as UTC');
    expect(DateTime.parse(ts['ts'] as String), DateTime.utc(2026, 7, 23, 10));
  });

  test('a 401 is retried once with a refreshed token', () async {
    // The regression that mattered: an access token expires 15 minutes into a
    // route, and tracking used to stop dead rather than renew it.
    final store = _FakeStore(accessToken: 'stale');
    final seenAuth = <String>[];
    var refreshCalls = 0;

    final client = ApiClient(
      store: store,
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          refreshCalls++;
          return http.Response(
            jsonEncode({'access_token': 'fresh', 'refresh_token': 'refresh-2'}),
            200,
          );
        }
        seenAuth.add(request.headers['authorization'] ?? '');
        if (request.headers['authorization'] == 'Bearer stale') {
          return http.Response(jsonEncode({'detail': 'expired'}), 401);
        }
        return http.Response(jsonEncode({'accepted': 2, 'bus_id': 'b'}), 202);
      }),
    );

    final accepted = await client.postGps(busId: 'b', fixes: [_fix, _fix]);

    expect(accepted, 2);
    expect(refreshCalls, 1);
    expect(seenAuth, ['Bearer stale', 'Bearer fresh']);
    expect(store.accessToken, 'fresh');
    expect(store.refreshToken, 'refresh-2', reason: 'rotated pair is stored');
  });

  test('a dead refresh token wipes the session and surfaces as expired', () async {
    final store = _FakeStore();
    final client = ApiClient(
      store: store,
      httpClient: MockClient((request) async {
        if (request.url.path == '/auth/refresh') {
          return http.Response(jsonEncode({'detail': 'revoked'}), 401);
        }
        return http.Response(jsonEncode({'detail': 'expired'}), 401);
      }),
    );

    await expectLater(
      client.postGps(busId: 'b', fixes: [_fix]),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(store.cleared, isTrue, reason: 'app must fall back to the login screen');
  });

  test('an unapproved helper (403) is not retried away as a network blip', () async {
    final client = ApiClient(
      store: _FakeStore(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Helper account not approved'}),
          403,
        ),
      ),
    );

    await expectLater(
      client.postGps(busId: 'b', fixes: [_fix]),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', 'Helper account not approved'),
      ),
    );
  });

  test('an unknown bus (404) keeps the detail the backend sent', () async {
    final client = ApiClient(
      store: _FakeStore(),
      httpClient: MockClient(
        (_) async => http.Response(jsonEncode({'detail': 'Unknown bus'}), 404),
      ),
    );

    await expectLater(
      client.postGps(busId: 'nope', fixes: [_fix]),
      throwsA(
        isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Unknown bus'),
      ),
    );
  });

  test('a non-JSON error body does not crash the parser', () async {
    // Nginx returns HTML when the API container is down.
    final client = ApiClient(
      store: _FakeStore(),
      httpClient: MockClient(
        (_) async => http.Response('<html>502 Bad Gateway</html>', 502),
      ),
    );

    await expectLater(
      client.postGps(busId: 'b', fixes: [_fix]),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 502)),
    );
  });
}
