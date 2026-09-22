import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../features/auth/auth_token_store.dart';
import 'api_config.dart';

/// Thrown for any non-2xx backend response. [statusCode] lets callers branch
/// on 401 (re-auth), 403 (not authorized for this group), 404, etc.
/// [statusCode] is `0` for a request that never got a response at all (see
/// [ApiClient._guarded]) — no response, so no real HTTP status to report.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// What every `error: (error, _) => ...` branch in this app should show,
/// instead of interpolating the raw error (`'$error'`) directly: an
/// [ApiException] already carries a message meant to be read by a user
/// (either the backend's own `detail`, or [ApiClient._guarded]'s
/// connection-failure text); anything else reaching this far is an
/// unexpected error a user was never meant to see the internals of.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) return error.message;
  return 'Something went wrong. Please try again.';
}

/// Talks to the QuietPass backend. Every request is authorized with the
/// current Firebase user's ID token: `getIdToken()` returns the cached
/// token and transparently refreshes it once it's within Firebase's expiry
/// window, so callers never have to think about refresh themselves. The
/// freshly-read token is also mirrored into [AuthTokenStore] so it stays in
/// sync with whatever's cached on-device.
class ApiClient {
  ApiClient({
    String? baseUrl,
    FirebaseAuth? auth,
    http.Client? httpClient,
    AuthTokenStore? tokenStore,
  })  : _baseUrl = baseUrl ?? apiBaseUrl,
        _auth = auth ?? FirebaseAuth.instance,
        _http = httpClient ?? http.Client(),
        _tokenStore = tokenStore ?? AuthTokenStore();

  final String _baseUrl;
  final FirebaseAuth _auth;
  final http.Client _http;
  final AuthTokenStore _tokenStore;

  Future<Map<String, String>> _authHeaders() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('No signed-in user to authorize the request.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw StateError('Firebase returned no ID token for the signed-in user.');
    }
    await _tokenStore.save(token);
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  Future<dynamic> get(String path) {
    return _guarded(() async {
      final response = await _http.get(_uri(path), headers: await _authHeaders());
      return _decode(response);
    });
  }

  /// For the handful of endpoints that must be reachable before there's a
  /// signed-in Firebase user to authorize with — currently just
  /// GET /auth/phone-exists, called from the Sign Up screen before OTP
  /// verification has even started. [get] can't be reused here: it always
  /// calls [_authHeaders], which throws for exactly this case (no current
  /// user yet).
  Future<dynamic> getUnauthenticated(String path) {
    return _guarded(() async {
      final response = await _http.get(_uri(path));
      return _decode(response);
    });
  }

  Future<dynamic> post(String path, {Object? body}) {
    return _guarded(() async {
      final response = await _http.post(
        _uri(path),
        headers: await _authHeaders(),
        body: body == null ? null : jsonEncode(body),
      );
      return _decode(response);
    });
  }

  Future<dynamic> put(String path, {Object? body}) {
    return _guarded(() async {
      final response = await _http.put(
        _uri(path),
        headers: await _authHeaders(),
        body: body == null ? null : jsonEncode(body),
      );
      return _decode(response);
    });
  }

  Future<dynamic> patch(String path, {Object? body}) {
    return _guarded(() async {
      final response = await _http.patch(
        _uri(path),
        headers: await _authHeaders(),
        body: body == null ? null : jsonEncode(body),
      );
      return _decode(response);
    });
  }

  Future<void> delete(String path) {
    return _guarded(() async {
      final response = await _http.delete(_uri(path), headers: await _authHeaders());
      _decode(response);
    });
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  /// Every request routes through here so a DNS failure, a dropped
  /// connection, or a timeout — anything below the HTTP layer, before a
  /// response even exists to `_decode` — surfaces as the same clean
  /// [ApiException] a real error response would, instead of a raw
  /// `ClientException`/`SocketException` whose message ("Failed host
  /// lookup: '...'  (OS Error: No address associated with hostname,
  /// errno = 7)") is Dart/OS internals, not something to show a user.
  /// [ApiException] itself and the auth-layer [StateError]s from
  /// `_authHeaders` pass through unchanged — both already carry a message
  /// meant to be seen (or handled specifically) by the caller.
  Future<T> _guarded<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException {
      rethrow;
    } on StateError {
      rethrow;
    } catch (_) {
      throw ApiException(0, 'Can\'t reach the server. Check your connection and try again.');
    }
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      return jsonDecode(response.body);
    }

    var message = response.body;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {
      // Non-JSON error body; fall back to the raw text above.
    }
    throw ApiException(response.statusCode, message);
  }
}
