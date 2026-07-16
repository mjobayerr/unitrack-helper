import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/gps_fix.dart';

/// The token was rejected, or this account may not post GPS. Retrying the same
/// batch cannot help — the caller must stop and get a fresh token.
class GpsAuthException implements Exception {
  const GpsAuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Any other non-202 response. Safe to retry.
class GpsRequestException implements Exception {
  const GpsRequestException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'HTTP $statusCode: $message';
}

/// Thin client for `POST /helper/gps`.
class GpsClient {
  GpsClient({required this.baseUrl, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  /// Returns the number of points the backend accepted.
  Future<int> sendBatch({
    required String token,
    required String busId,
    required List<GpsFix> fixes,
  }) async {
    final response = await _http
        .post(
          Uri.parse('$baseUrl/helper/gps'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'bus_id': busId,
            'points': [for (final fix in fixes) fix.toJson()],
          }),
        )
        .timeout(AppConfig.requestTimeout);

    switch (response.statusCode) {
      case 202:
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['accepted'] as int;
      case 401:
        throw GpsAuthException(_detail(response) ?? 'Token invalid or expired');
      case 403:
        throw GpsAuthException(_detail(response) ?? 'Helper account not approved');
      default:
        throw GpsRequestException(
          response.statusCode,
          _detail(response) ?? response.reasonPhrase ?? 'Request failed',
        );
    }
  }

  void close() => _http.close();

  /// FastAPI puts the human-readable reason in `detail`.
  static String? _detail(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map<String, dynamic> && body['detail'] != null) {
        return body['detail'].toString();
      }
    } on FormatException {
      // Not JSON (e.g. an Nginx error page) — fall through to the status line.
    }
    return null;
  }
}
