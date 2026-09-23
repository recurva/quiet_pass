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

/// True whenever it's safe for [AuthGate] to show the signed-in app.
/// Defaults to true so a cold start with an already-persisted Firebase
/// session (the normal "close and reopen the app" case) goes straight to
/// the home screen with no gating. Only flips to false for the brief
/// window between Firebase confirming an OTP credential and our own
/// POST /auth/sign-in finishing — see _signInAndStoreToken. Without this,
/// Firebase's authStateChanges fires the instant the credential is
/// confirmed, GroupsHomePage mounts immediately, and its own GET /users/me
/// races POST /auth/sign-in — whichever one provisions the user first
/// wins, and since /auth/sign-in always loses that race it arrives to find
/// the user already exists and (correctly, for a *returning* user) never
/// touches the name, silently discarding whatever name was just entered.
final backendSignInSettledProvider = StateProvider<bool>((ref) => true);

/// Which of the two signed-out screens [AuthGate] shows. Switching between
/// Sign In and Sign Up flips this rather than pushing a new route over
/// AuthGate: a pushed route would replace AuthGate itself in the
/// Navigator stack (see the old _switchMode, which used
/// Navigator.pushReplacement), and once AuthGate is gone from the stack
/// it can no longer react to sign-in completing — popping back after OTP
/// just reveals that same replaced route again instead of the home
/// screen, until a full app restart rebuilds AuthGate fresh. Keeping
/// AuthGate as the one screen that's always on the stack, and toggling
/// which child it shows, avoids that entirely.
final showSignUpProvider = StateProvider<bool>((ref) => false);

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
        try {
          await _signInAndStoreToken(credential);
          state = const OtpFlowIdle();
        } catch (_) {
          // See confirmCode's matching catch: signInWithCredential can
          // throw even after natively succeeding, and authStateChangesProvider
          // has already fired by this point regardless. There's no code
          // screen visible to retry from at this point (instant
          // verification skips it entirely), so this is unretryable by
          // construction — the empty verificationId reflects that rather
          // than pretending a retry is possible.
          state = OtpFlowError(
            'Something went wrong, but you may already be signed in.',
            verificationId: '',
            phoneNumber: phoneNumber,
          );
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        // Still on the phone-entry screen at this point (codeSent never
        // fired), not the code-entry screen — nothing to retry via
        // confirmCode either way.
        state = OtpFlowError(
          e.message ?? 'Could not send the code. Try again.',
          verificationId: '',
          phoneNumber: phoneNumber,
        );
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
    // Retryable from either OtpFlowCodeSent (first attempt) or
    // OtpFlowError (a previous attempt was a wrong or expired code) —
    // both carry the same verificationId/phoneNumber. Without accepting
    // OtpFlowError here too, a wrong code would leave the Verify button
    // looking enabled but silently doing nothing on every subsequent tap,
    // since this used to only recognize OtpFlowCodeSent.
    final (verificationId, phoneNumber) = switch (state) {
      OtpFlowCodeSent(:final verificationId, :final phoneNumber) => (
          verificationId,
          phoneNumber,
        ),
      OtpFlowError(:final verificationId, :final phoneNumber) when verificationId.isNotEmpty =>
        (verificationId, phoneNumber),
      _ => (null, null),
    };
    if (verificationId == null || phoneNumber == null) return;

    state = OtpFlowVerifying(verificationId: verificationId, phoneNumber: phoneNumber);

    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await _signInAndStoreToken(credential);
      state = const OtpFlowIdle();
    } on FirebaseAuthException catch (e) {
      state = OtpFlowError(
        e.message ?? 'That code did not match. Try again.',
        verificationId: verificationId,
        phoneNumber: phoneNumber,
      );
    } catch (_) {
      // Anything else — notably firebase_auth's own known type-cast bug,
      // which can throw here even though the native sign-in underneath
      // already succeeded (see _signInAndStoreToken's doc comment). Show
      // *something* rather than leaving the Verify button silently
      // spinning forever: authStateChangesProvider has already fired by
      // this point regardless, so AuthGate is on its way to the signed-in
      // app whether or not this line runs.
      state = OtpFlowError(
        'Something went wrong, but you may already be signed in.',
        verificationId: verificationId,
        phoneNumber: phoneNumber,
      );
    }
  }

  Future<void> _signInAndStoreToken(PhoneAuthCredential credential) async {
    // Closes the window between Firebase confirming the credential (which
    // fires authStateChangesProvider immediately) and our own
    // POST /auth/sign-in finishing — see backendSignInSettledProvider's
    // doc comment for exactly what race this prevents. Wraps the *whole*
    // function body, not just the backend call below: signInWithCredential
    // itself can throw (see the catch in confirmCode) after the native
    // sign-in has already gone through, and this must still flip back to
    // true when that happens — otherwise AuthGate is stuck on the splash
    // screen forever, signed in but unable to show it, until the app is
    // fully restarted and re-reads Firebase's already-persisted session.
    _ref.read(backendSignInSettledProvider.notifier).state = false;
    try {
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
        // and caches forever until told otherwise. GroupsHomePage can
        // mount and run its own GET /users/me the instant
        // signInWithCredential (above) fires authStateChangesProvider,
        // likely *before* this sign-in call has even finished — caching a
        // stale value. Invalidating here, after the call is known to have
        // completed, forces a fresh fetch regardless of which one
        // actually won that race.
        _ref.invalidate(currentBackendUserProvider);
      } catch (_) {
        // Never block sign-in on this — worst case the name falls back to
        // the phone number (new user) or is simply whatever it already
        // was (returning user), and the profile screen is always there to
        // fix it afterward.
      }
    } finally {
      _ref.read(backendSignInSettledProvider.notifier).state = true;
    }
  }

  void reset() => state = const OtpFlowIdle();
}
