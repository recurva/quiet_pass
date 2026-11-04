import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';

import 'package:quietpass/core/api_client.dart';
import 'package:quietpass/features/auth/auth_token_store.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockAuthTokenStore extends Mock implements AuthTokenStore {}

/// Item 2's root cause, pinned down: `ApiClient._authHeaders` (called by
/// every mutating request — `patch`, `post`, `put`, `delete`) used to
/// throw a bare [StateError] when there was no signed-in Firebase user.
/// `_guarded` explicitly rethrew that unchanged, and every call site in
/// the app only ever catches `on ApiException` — never `StateError` — so
/// that failure mode produced exactly the client's reported symptom: zero
/// HTTP request (it never got that far) and no visible error (nothing
/// downstream was listening for that type), e.g. tapping "Mark done" on
/// a chore (chore_pass_sheet.dart, spaces_page.dart) and nothing
/// happening at all. These tests pin the actual fix — the same no-user
/// condition now throws [ApiException], the one error type every screen
/// in this app already knows how to catch and show.
void main() {
  late _MockFirebaseAuth auth;
  late _MockAuthTokenStore tokenStore;
  late ApiClient client;

  setUp(() {
    auth = _MockFirebaseAuth();
    tokenStore = _MockAuthTokenStore();
    when(() => tokenStore.save(any())).thenAnswer((_) async {});
    client = ApiClient(
      baseUrl: 'https://example.invalid/api/v1',
      auth: auth,
      httpClient: http.Client(),
      tokenStore: tokenStore,
    );
  });

  test('patch throws ApiException, not StateError, when no user is signed in', () async {
    when(() => auth.currentUser).thenReturn(null);

    await expectLater(
      client.patch('/chores/abc/done'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  test('post throws ApiException, not StateError, when Firebase returns no token', () async {
    final user = _MockUser();
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.getIdToken()).thenAnswer((_) async => null);

    await expectLater(client.post('/groups/g1/spaces'), throwsA(isA<ApiException>()));
  });

  test('delete throws ApiException, not StateError, when no user is signed in', () async {
    when(() => auth.currentUser).thenReturn(null);

    await expectLater(
      client.delete('/groups/g1/spaces/s1'),
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'statusCode', 401)),
    );
  });

  group('friendlyErrorMessage', () {
    test('a non-ApiException error never leaks its own internals', () {
      expect(
        friendlyErrorMessage(StateError('boom')),
        'Something went wrong. Please try again.',
      );
    });

    test('404/405 never render the backend routing layer\'s raw reason phrase', () {
      // The exact shape a mismatched route (wrong path or wrong HTTP verb)
      // produces: FastAPI/Starlette's own default `detail`, not anything
      // any app route wrote itself — see the Add/Delete Space bug this
      // mapping was written for.
      expect(
        friendlyErrorMessage(ApiException(404, 'Not Found')),
        "That wasn't found.",
      );
      expect(
        friendlyErrorMessage(ApiException(405, 'Method Not Allowed')),
        "That action isn't available.",
      );
    });

    test('403 and 500 get their own fixed, friendly fallback too', () {
      expect(
        friendlyErrorMessage(ApiException(403, 'Forbidden')),
        "You don't have permission to do that.",
      );
      expect(
        friendlyErrorMessage(ApiException(500, 'Internal Server Error')),
        'Something went wrong on our end.',
      );
    });

    test('400/409/422 pass the backend\'s own message straight through', () {
      // These are this app's own HTTPException(...) calls with a real,
      // hand-written message (see spaces.py/status.py's
      // InvalidStatusDurationError, reservation_service's
      // ReservationConflictError, etc.) — never a bare framework default.
      expect(
        friendlyErrorMessage(ApiException(400, 'deep_focus accepts these durations only: 30m.')),
        'deep_focus accepts these durations only: 30m.',
      );
      expect(
        friendlyErrorMessage(ApiException(409, 'This space is already booked for that time.')),
        'This space is already booked for that time.',
      );
      expect(
        friendlyErrorMessage(ApiException(422, 'String should have at least 1 character')),
        'String should have at least 1 character',
      );
    });

    test('a status code with no fallback entry (e.g. 401) still falls back to the message', () {
      expect(
        friendlyErrorMessage(ApiException(401, "You're signed out. Please sign in again.")),
        "You're signed out. Please sign in again.",
      );
      // 0 is ApiClient._guarded's own "never reached the server" code —
      // no fallback entry either, same reasoning.
      expect(
        friendlyErrorMessage(ApiException(0, "Can't reach the server. Check your connection and try again.")),
        "Can't reach the server. Check your connection and try again.",
      );
    });
  });

  group('ApiClient._decode (via a fake HTTP transport)', () {
    ApiClient clientWithResponse(int statusCode, String body) {
      return ApiClient(
        baseUrl: 'https://example.invalid/api/v1',
        auth: auth,
        tokenStore: tokenStore,
        httpClient: MockClient((request) async {
          return http.Response(body, statusCode);
        }),
      );
    }

    setUp(() {
      final user = _MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.getIdToken()).thenAnswer((_) async => 'fake-token');
    });

    test('a plain string detail (this app\'s own HTTPException) passes through as-is', () async {
      final c = clientWithResponse(409, jsonEncode({'detail': 'Already booked.'}));
      await expectLater(
        c.get('/groups/g1/reservations'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', 'Already booked.')),
      );
    });

    test(
      'a FastAPI validation-error list detail reduces to the first error\'s own msg, '
      'not a dumped list',
      () async {
        final c = clientWithResponse(
          422,
          jsonEncode({
            'detail': [
              {
                'type': 'string_too_short',
                'loc': ['body', 'name'],
                'msg': 'String should have at least 1 character',
                'input': '',
              },
            ],
          }),
        );
        await expectLater(
          c.get('/groups/g1/spaces'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              'String should have at least 1 character',
            ),
          ),
        );
      },
    );

    test('a routing-layer 404/405 with no app-level detail surfaces the raw reason phrase '
        'as ApiException.message (friendlyErrorMessage, not this, is what hides it)', () async {
      final c = clientWithResponse(405, jsonEncode({'detail': 'Method Not Allowed'}));
      await expectLater(
        c.post('/groups/g1/spaces'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'statusCode', 405)
              .having((e) => e.message, 'message', 'Method Not Allowed'),
        ),
      );
    });
  });
}
