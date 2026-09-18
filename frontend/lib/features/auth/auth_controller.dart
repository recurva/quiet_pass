import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  );
});

/// Drives Firebase phone verification: send an SMS code, then confirm it.
/// Sign-in itself surfaces through [authStateChangesProvider]; this only
/// tracks the send/confirm steps and their errors.
class OtpFlowController extends StateNotifier<OtpFlowState> {
  OtpFlowController({required FirebaseAuth auth, required AuthTokenStore tokenStore})
      : _auth = auth,
        _tokenStore = tokenStore,
        super(const OtpFlowIdle());

  final FirebaseAuth _auth;
  final AuthTokenStore _tokenStore;

  Future<void> sendCode(String phoneNumber) async {
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
    state = const OtpFlowIdle();
  }

  void reset() => state = const OtpFlowIdle();
}
