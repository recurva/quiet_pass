import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../groups/groups_providers.dart';
import '../groups/groups_repository.dart';
import 'auth_state.dart';
import 'auth_token_store.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final authTokenStoreProvider = Provider<AuthTokenStore>((ref) => AuthTokenStore());

/// Source of truth for sign-in status: whoever wraps the app (the auth gate)
/// watches this instead of polling FirebaseAuth directly.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(firebaseAuthProvider).authStateChanges();
});

/// A one-shot message for the home screen to show right after landing —
/// currently just "You already have an account, signing you in." for
/// someone who went through Sign Up with a number that turned out to
/// already be registered. Read-and-cleared by whoever displays it, the
/// same "show once" shape as `_promptedThisSession` elsewhere in this app.
final authNoticeProvider = StateProvider<String?>((ref) => null);

final otpFlowControllerProvider =
    StateNotifierProvider<OtpFlowController, OtpFlowState>((ref) {
  return OtpFlowController(
    auth: ref.watch(firebaseAuthProvider),
    tokenStore: ref.watch(authTokenStoreProvider),
    repository: ref.watch(groupsRepositoryProvider),
    ref: ref,
  );
});

/// Drives Firebase phone verification: send an SMS code, then confirm it.
/// Sign-in itself surfaces through [authStateChangesProvider]; this only
/// tracks the send/confirm steps and their errors.
class OtpFlowController extends StateNotifier<OtpFlowState> {
  OtpFlowController({
    required FirebaseAuth auth,
    required AuthTokenStore tokenStore,
    required GroupsRepository repository,
    required Ref ref,
  })  : _auth = auth,
        _tokenStore = tokenStore,
        _repository = repository,
        _ref = ref,
        super(const OtpFlowIdle());

  final FirebaseAuth _auth;
  final AuthTokenStore _tokenStore;
  final GroupsRepository _repository;
  // Safe to hold onto: otpFlowControllerProvider isn't autoDispose, so this
  // controller (and the ref that created it) live for the app's lifetime.
  final Ref _ref;

  // Captured on the Sign Up screen only (the Sign In screen never sets
  // this — see SignInPage/SignUpPage) and sent along with the post-OTP
  // sign-in call. Whether it actually gets *used* is entirely a backend
  // decision (see authenticate_token): a genuinely new number gets
  // created with this name; an already-registered number ignores it and
  // keeps whatever name it already had.
  String? _pendingDisplayName;

  Future<void> sendCode(String phoneNumber, {String? displayName}) async {
    _pendingDisplayName = displayName;
    state = const OtpFlowSendingCode();
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        // Android instant/auto-retrieval verification; sign in right away.
        await _signInAndStoreToken(credential);
      },
      verificationFailed: (FirebaseAuthException e) {
        state = OtpFlowError(e.message ?? 'Could not send the code. Try again.');
      },
      codeSent: (verificationId, _) {
        state = OtpFlowCodeSent(verificationId: verificationId, phoneNumber: phoneNumber);
      },
      codeAutoRetrievalTimeout: (verificationId) {
        // No-op: user can still type the code manually while in
        // OtpFlowCodeSent.
      },
    );
  }

  Future<void> confirmCode(String smsCode) async {
    final current = state;
    if (current is! OtpFlowCodeSent) return;

    state = OtpFlowVerifying(
      verificationId: current.verificationId,
      phoneNumber: current.phoneNumber,
    );

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: current.verificationId,
        smsCode: smsCode,
      );
      await _signInAndStoreToken(credential);
    } on FirebaseAuthException catch (e) {
      state = OtpFlowError(e.message ?? 'That code did not match. Try again.');
    }
  }

  Future<void> _signInAndStoreToken(PhoneAuthCredential credential) async {
    final result = await _auth.signInWithCredential(credential);
    final idToken = await result.user?.getIdToken();
    if (idToken != null) {
      await _tokenStore.save(idToken);
    }

    // One call, for both Sign In and Sign Up: the backend is the one
    // place that actually knows whether this phone number is new or
    // returning (see POST /auth/sign-in and authenticate_token's
    // docstring) — never trust "which screen was used" for that, since
    // Firebase ties the account to the number regardless.
    final enteredName = _pendingDisplayName;
    _pendingDisplayName = null;
    try {
      final (_, isNew) = await _repository.signIn(displayName: enteredName);

      if (!isNew && enteredName != null) {
        // Came through Sign Up, but the number already had an account —
        // their real name was never touched server-side; just let them
        // know why they're not looking at a blank Sign Up form anymore.
        _ref.read(authNoticeProvider.notifier).state =
            'You already have an account, signing you in.';
      }

      // currentBackendUserProvider isn't autoDispose — it fetches once
      // and caches forever until told otherwise. GroupsHomePage can mount
      // and run its own GET /users/me the instant signInWithCredential
      // (above) fires authStateChangesProvider, likely *before* this
      // sign-in call has even finished — caching a stale value.
      // Invalidating here, after the call is known to have completed,
      // forces a fresh fetch regardless of which one actually won that
      // race.
      _ref.invalidate(currentBackendUserProvider);
    } catch (_) {
      // Never block sign-in on this — worst case the name falls back to
      // the phone number (new user) or is simply whatever it already was
      // (returning user), and the profile screen is always there to fix
      // it afterward.
    }

    state = const OtpFlowIdle();
  }

  void reset() => state = const OtpFlowIdle();
}
