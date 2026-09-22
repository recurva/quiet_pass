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

final otpFlowControllerProvider =
    StateNotifierProvider<OtpFlowController, OtpFlowState>((ref) {
  return OtpFlowController(
    auth: ref.watch(firebaseAuthProvider),
    tokenStore: ref.watch(authTokenStoreProvider),
    repository: ref.watch(groupsRepositoryProvider),
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
  })  : _auth = auth,
        _tokenStore = tokenStore,
        _repository = repository,
        super(const OtpFlowIdle());

  final FirebaseAuth _auth;
  final AuthTokenStore _tokenStore;
  final GroupsRepository _repository;

  // Captured at signup (see PhoneEntryPage) and sent to the backend the
  // moment sign-in succeeds — the name is required at signup, never a
  // separate later step, so there's no persistent "onboarding" flag
  // anywhere: this is just carried across the two Firebase calls
  // (send code, then confirm) that make up one signup attempt.
  String? _pendingDisplayName;

  Future<void> sendCode(String phoneNumber, {required String displayName}) async {
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

    // The very first authenticated call for a brand-new phone number
    // provisions the backend User row (see get_current_user), defaulted
    // to the phone number as its name — this PATCH overwrites that with
    // the real captured name before anything else in the app ever runs,
    // so there's no window where a "no name set" state is visibly used.
    // A returning user signing in again just re-sends their existing
    // name; harmless, same value either way.
    final name = _pendingDisplayName;
    if (name != null && name.isNotEmpty) {
      try {
        await _repository.updateDisplayName(name);
      } catch (_) {
        // Never block sign-in on this — worst case the name falls back
        // to the phone number and the user can fix it from the profile
        // screen, the same recovery path as before this existed.
      }
      _pendingDisplayName = null;
    }

    state = const OtpFlowIdle();
  }

  void reset() => state = const OtpFlowIdle();
}
