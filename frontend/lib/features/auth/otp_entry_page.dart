import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// Second screen of the sign-in flow: confirm the 6-digit SMS code. On
/// success, FirebaseAuth's user stream fires and the app-level auth gate
/// swaps this whole flow out for the signed-in home screen.
class OtpEntryPage extends ConsumerStatefulWidget {
  const OtpEntryPage({super.key});

  @override
  ConsumerState<OtpEntryPage> createState() => _OtpEntryPageState();
}

class _OtpEntryPageState extends ConsumerState<OtpEntryPage> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flowState = ref.watch(otpFlowControllerProvider);
    final isVerifying = flowState is OtpFlowVerifying;

    // AuthGate swaps its root widget once FirebaseAuth's user stream fires,
    // but that root sits *underneath* this pushed route in the Navigator
    // stack — it won't become visible until this screen (and the phone
    // screen below it) are popped back off.
    ref.listen<AsyncValue<User?>>(authStateChangesProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user != null) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final phoneNumber = switch (flowState) {
      OtpFlowCodeSent(:final phoneNumber) => phoneNumber,
      OtpFlowVerifying(:final phoneNumber) => phoneNumber,
      _ => null,
    };

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Enter the code', style: context.text.titleLarge),
              SizedBox(height: Space.xs.h),
              Text(
                phoneNumber == null
                    ? 'We sent you a 6-digit code.'
                    : 'We sent a 6-digit code to $phoneNumber.',
                style: context.text.bodySmall,
              ),
              SizedBox(height: Space.xl.h),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 6,
                style: context.text.titleLarge?.copyWith(letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: c.surface2,
                  contentPadding: EdgeInsets.symmetric(vertical: Space.md.h),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md.r),
                    borderSide: BorderSide(color: c.line2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md.r),
                    borderSide: BorderSide(color: c.line2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(Radii.md.r),
                    borderSide: BorderSide(color: c.accent),
                  ),
                ),
              ),
              if (flowState is OtpFlowError) ...[
                SizedBox(height: Space.sm.h),
                Text(
                  flowState.message,
                  style: context.text.bodySmall?.copyWith(color: c.call.solid),
                ),
              ],
              SizedBox(height: Space.lg.h),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: isVerifying ? null : _submit,
                  child: isVerifying
                      ? SizedBox(
                          width: 20.r,
                          height: 20.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.onAccent,
                          ),
                        )
                      : const Text('Verify'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final code = _controller.text.trim();
    if (code.length != 6) return;
    ref.read(otpFlowControllerProvider.notifier).confirmCode(code);
  }
}
