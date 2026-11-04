import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:quietpass/features/auth/auth_controller.dart';
import 'package:quietpass/features/auth/auth_state.dart';
import 'package:quietpass/features/auth/auth_token_store.dart';
import 'package:quietpass/features/auth/otp_entry_page.dart';
import 'package:quietpass/features/groups/groups_repository.dart';
import 'package:quietpass/theme/app_theme.dart';

class _MockFirebaseAuth extends Mock implements FirebaseAuth {}

class _MockAuthTokenStore extends Mock implements AuthTokenStore {}

class _MockGroupsRepository extends Mock implements GroupsRepository {}

/// Stands in for the real [OtpFlowController] for this screen's own tests:
/// [resendCode]/[confirmCode] never touch Firebase or the backend here —
/// that integration is OtpFlowController's own responsibility, already
/// covered by widget_test.dart's pure state-machine coverage. `state`
/// (inherited, public on StateNotifier) is driven directly from the test
/// to simulate whatever OtpFlowController would eventually land on.
class _FakeOtpFlowController extends OtpFlowController {
  _FakeOtpFlowController({
    required super.auth,
    required super.tokenStore,
    required super.repository,
    required super.ref,
  });

  int resendCalls = 0;

  @override
  Future<void> resendCode(String phoneNumber) async {
    resendCalls++;
    state = OtpFlowCodeSent(verificationId: 'resent-$resendCalls', phoneNumber: phoneNumber);
  }

  @override
  Future<void> confirmCode(String smsCode) async {}
}

/// Item 9 coverage for otp_entry_page.dart: the "Resend code" cooldown
/// state, and what a failed verification attempt now visibly does (shows
/// the error *and* clears the stale code) instead of leaving a wrong code
/// sitting in the boxes next to an easy-to-miss message. SMS
/// auto-retrieval/autofill itself isn't covered here — it can't be
/// meaningfully exercised outside a real device's SMS stack.
void main() {
  late _FakeOtpFlowController controller;

  Widget buildPage() {
    return ProviderScope(
      overrides: [
        authStateChangesProvider.overrideWith((ref) => const Stream<User?>.empty()),
        otpFlowControllerProvider.overrideWith((ref) {
          final fake = _FakeOtpFlowController(
            auth: _MockFirebaseAuth(),
            tokenStore: _MockAuthTokenStore(),
            repository: _MockGroupsRepository(),
            ref: ref,
          );
          fake.state = const OtpFlowCodeSent(verificationId: 'v1', phoneNumber: '+15551234567');
          controller = fake;
          return fake;
        }),
      ],
      child: ScreenUtilInit(
        designSize: const Size(375, 812),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.light,
          home: const OtpEntryPage(),
        ),
      ),
    );
  }

  testWidgets('Resend code starts disabled with a countdown, and resends once it elapses', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    // Disabled, counting down, right after a code was just sent — a fresh
    // code was already sent automatically the instant this screen became
    // reachable (see phone_entry_page.dart), so resend starts throttled
    // too, not immediately available.
    expect(find.text('Resend code in 30s'), findsOneWidget);
    var resendButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Resend code in 30s'));
    expect(resendButton.onPressed, isNull);

    // Fast-forward through the full cooldown.
    await tester.pump(const Duration(seconds: 30));

    expect(find.text('Resend code'), findsOneWidget);
    resendButton = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Resend code'));
    expect(resendButton.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(TextButton, 'Resend code'));
    await tester.pump();

    expect(controller.resendCalls, 1);
    // Tapping resend restarts the cooldown rather than leaving it tappable
    // again immediately.
    expect(find.text('Resend code in 30s'), findsOneWidget);
  });

  testWidgets(
    'a failed verification attempt shows the error message and clears the stale code',
    (tester) async {
      await tester.pumpWidget(buildPage());
      await tester.pump();

      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);

      controller.state = const OtpFlowError(
        'Please enter the right OTP and try again.',
        verificationId: 'v1',
        phoneNumber: '+15551234567',
      );
      await tester.pump();

      // The error is clearly visible...
      expect(find.text('Please enter the right OTP and try again.'), findsOneWidget);
      // ...and the wrong code no longer sits in the boxes pretending
      // nothing happened — re-tapping Verify with no changes used to just
      // resubmit the same rejected code and fail identically again.
      expect(find.text('1'), findsNothing);
      expect(find.text('6'), findsNothing);
    },
  );

  testWidgets('submitting fewer than 6 digits shows a message instead of doing nothing', (
    tester,
  ) async {
    await tester.pumpWidget(buildPage());
    await tester.pump();

    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
    await tester.pump();

    expect(find.text('Enter all 6 digits.'), findsOneWidget);
  });
}
