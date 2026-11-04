import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

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

/// Fixed, human copy for status codes that carry no reliable app-level
/// message of their own — a mismatched route (404/405, see the Add/Delete
/// Space bug this was written for), an authorization check that never
/// bothers to explain itself (403), or a 500 (an unhandled server
/// exception's `detail` is Starlette's generic "Internal Server Error",
/// never anything written for a user). Every one of these would otherwise
/// surface a raw HTTP reason phrase straight from the backend's routing
/// layer — "Method Not Allowed", "Not Found" — which is Starlette/FastAPI
/// internals, not something to show a user.
///
/// Deliberately excludes 400/409/422: see [friendlyErrorMessage].
const _statusFallbackMessages = <int, String>{
  403: "You don't have permission to do that.",
  404: "That wasn't found.",
  405: "That action isn't available.",
  500: "Something went wrong on our end.",
};

/// What every `error: (error, _) => ...` branch in this app should show,
/// instead of interpolating the raw error (`'$error'`) directly: an
/// [ApiException] already carries a message meant to be read by a user
/// (either the backend's own `detail`, or [ApiClient._guarded]'s
/// connection-failure text); anything else reaching this far is an
/// unexpected error a user was never meant to see the internals of.
///
/// 400/409/422 are trusted to already hold a real, hand-written message:
/// every `HTTPException(400/409, ...)` this backend's routers raise
/// passes a specific `str(exc)` from one of its own domain errors (e.g.
/// InvalidStatusDurationError, ReservationConflictError — see
/// spaces.py/status.py/urgent_access.py/users.py/recurring.py), never a
/// bare framework default; 422 is FastAPI's own request-validation
/// failure, whose `detail` [ApiClient._decode] already reduces to the
/// first validator's own `msg` (e.g. "String should have at least 1
/// character") rather than the raw list of error objects. Every *other*
/// status code gets the fixed fallback in [_statusFallbackMessages] (if
/// one exists for it) instead of ever trusting `detail` to be meant for a
/// user — a route that doesn't exist (404) or exists under a different
/// verb (405) has no app-level handler to have written one at all, and
/// what reaches here instead is Starlette's own routing-layer text.
String friendlyErrorMessage(Object error) {
  if (error is ApiException) {
    if (error.statusCode == 400 || error.statusCode == 409 || error.statusCode == 422) {
      return error.message;
    }
    return _statusFallbackMessages[error.statusCode] ?? error.message;
  }
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

  /// Both [_authHeaders] and [_authHeaderOnly] throw [ApiException] (never
  /// a bare [StateError]) when there's no signed-in user or Firebase
  /// returns no token — this used to throw [StateError] directly, which
  /// every call site's `on ApiException catch (e)` doesn't catch: the
  /// mutation would fail before ever reaching [_http] (so the network tab
  /// shows nothing), with no snackbar/error text either, since nothing
  /// downstream was listening for that type. [ApiException] is what every
  /// screen in this app already knows how to show, so routing this
  /// through the same type is the actual fix, not a one-off patch to
  /// whichever screen happened to hit it first.
  static final _noUser = ApiException(401, "You're signed out. Please sign in again.");

  Future<Map<String, String>> _authHeaders() async {
    final user = _auth.currentUser;
    if (user == null) throw _noUser;
    final token = await user.getIdToken();
    if (token == null) throw _noUser;
    await _tokenStore.save(token);
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Same token resolution as [_authHeaders], but without forcing
  /// `Content-Type: application/json` — [http.MultipartRequest] computes
  /// its own `Content-Type` (with the multipart boundary) when sent, and
  /// a manually-set JSON content type here would just be overwritten.
  Future<Map<String, String>> _authHeaderOnly() async {
    final user = _auth.currentUser;
    if (user == null) throw _noUser;
    final token = await user.getIdToken();
    if (token == null) throw _noUser;
    await _tokenStore.save(token);
    return {'Authorization': 'Bearer $token'};
  }

  /// Multipart file upload (e.g. PUT /users/me/avatar). [fieldName] must
  /// match the backend's `File(...)` parameter name exactly.
  Future<dynamic> putMultipartFile(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) {
    return _guarded(() async {
      final request = http.MultipartRequest('PUT', _uri(path))
        ..headers.addAll(await _authHeaderOnly())
        ..files.add(
          http.MultipartFile.fromBytes(
            fieldName,
            bytes,
            filename: filename,
            // Without this, http defaults the part's Content-Type to
            // application/octet-stream, which the backend's avatar upload
            // rejects outright before it ever tries to decode the image —
            // every upload failed with "That doesn't look like a valid
            // image" regardless of the file actually being a valid photo.
            contentType: contentType == null ? null : MediaType.parse(contentType),
          ),
        );
      final streamed = await _http.send(request);
      final response = await http.Response.fromStream(streamed);
      return _decode(response);
    });
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
  /// [ApiException] itself (including the auth-layer one `_authHeaders`/
  /// `_authHeaderOnly` throw when there's no signed-in user) passes
  /// through unchanged — it already carries a message meant to be shown.
  Future<T> _guarded<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on ApiException {
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
        final detail = decoded['detail'];
        if (detail is String) {
          message = detail;
        } else if (detail is List && detail.isNotEmpty) {
          // FastAPI's own request-validation shape (a 422 from a bad
          // request body/query, not anything an app route wrote itself):
          // a list of {"msg": "...", "loc": [...], ...} objects, one per
          // invalid field. `.toString()`-ing that whole list used to
          // surface as literal Dart/Python-ish map syntax ("[{type:
          // string_too_short, loc: [body, name], msg: String should have
          // at least 1 character, ...}]") — technically not empty, but
          // not something to show a user either. The first entry's own
          // `msg` is: FastAPI/Pydantic already phrases it in plain
          // English, and it's usually the only invalid field anyway.
          final first = detail.first;
          message = first is Map && first['msg'] is String
              ? first['msg'] as String
              : detail.toString();
        } else {
          message = detail.toString();
        }
      }
    } catch (_) {
      // Non-JSON error body; fall back to the raw text above.
    }
    throw ApiException(response.statusCode, message);
  }
}
