import 'package:flutter_test/flutter_test.dart';

import 'package:quietpass/features/auth/auth_state.dart';

// A full widget pump of QuietPassApp now requires Firebase to be
// initialized (AuthGate reads FirebaseAuth.instance), which needs platform
// channel mocking flutter_test doesn't set up by default. Until that mocking
// is added, this covers the OTP flow's state machine instead of the widget
// tree.
void main() {
  test('OtpFlowState starts idle and carries the right fields through the flow', () {
    const idle = OtpFlowIdle();
    expect(idle, isA<OtpFlowState>());

    const codeSent = OtpFlowCodeSent(verificationId: 'abc123', phoneNumber: '+15551234567');
    expect(codeSent.verificationId, 'abc123');
    expect(codeSent.phoneNumber, '+15551234567');

    const error = OtpFlowError(
      'That code did not match. Try again.',
      verificationId: 'abc123',
      phoneNumber: '+15551234567',
    );
    expect(error.message, 'That code did not match. Try again.');
    expect(error.verificationId, 'abc123');
    expect(error.phoneNumber, '+15551234567');
  });
}
