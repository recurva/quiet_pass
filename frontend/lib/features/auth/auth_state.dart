import 'package:flutter/foundation.dart';

/// Where the phone-auth flow currently stands. [OtpFlowState] tracks the
/// verify-code screen specifically; sign-in status itself is read straight
/// from FirebaseAuth's user stream.
@immutable
sealed class OtpFlowState {
  const OtpFlowState();
}

class OtpFlowIdle extends OtpFlowState {
  const OtpFlowIdle();
}

class OtpFlowSendingCode extends OtpFlowState {
  const OtpFlowSendingCode();
}

/// SMS code has been sent; [verificationId] is what Firebase needs to pair
/// with the 6-digit code the user types in.
class OtpFlowCodeSent extends OtpFlowState {
  const OtpFlowCodeSent({required this.verificationId, required this.phoneNumber});

  final String verificationId;
  final String phoneNumber;
}

class OtpFlowVerifying extends OtpFlowState {
  const OtpFlowVerifying({required this.verificationId, required this.phoneNumber});

  final String verificationId;
  final String phoneNumber;
}

class OtpFlowError extends OtpFlowState {
  const OtpFlowError(this.message);

  final String message;
}
