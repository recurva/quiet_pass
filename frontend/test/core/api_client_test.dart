import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
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
}
