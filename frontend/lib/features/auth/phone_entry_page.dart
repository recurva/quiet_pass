import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'otp_entry_page.dart';

/// First screen of the sign-in flow: collect a phone number and ask Firebase
/// to send an SMS code. Reads only from `context.colors` / `Space` / `Radii`,
/// same as the rest of the app.
class PhoneEntryPage extends ConsumerStatefulWidget {
  const PhoneEntryPage({super.key});

  @override
  ConsumerState<PhoneEntryPage> createState() => _PhoneEntryPageState();
}

class _PhoneEntryPageState extends ConsumerState<PhoneEntryPage> {
  final _controller = TextEditingController();
  bool _navigatedForCurrentCodeSent = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final flowState = ref.watch(otpFlowControllerProvider);
    final isSending = flowState is OtpFlowSendingCode;

    ref.listen<OtpFlowState>(otpFlowControllerProvider, (previous, next) {
      if (next is OtpFlowCodeSent && !_navigatedForCurrentCodeSent) {
        _navigatedForCurrentCodeSent = true;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const OtpEntryPage()),
        );
      }
      if (next is OtpFlowIdle) {
        _navigatedForCurrentCodeSent = false;
      }
    });

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('QuietPass', style: context.text.titleLarge),
              SizedBox(height: Space.xs.h),
              Text(
                'Enter your phone number to sign in.',
                style: context.text.bodySmall,
              ),
              SizedBox(height: Space.xl.h),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.phone,
                style: context.text.bodyLarge?.copyWith(color: c.ink),
                decoration: InputDecoration(
                  hintText: '+1 555 555 1234',
                  hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
                  filled: true,
                  fillColor: c.surface2,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: Space.md.w,
                    vertical: Space.md.h,
                  ),
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
                  onPressed: isSending ? null : _submit,
                  child: isSending
                      ? SizedBox(
                          width: 20.r,
                          height: 20.r,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.onAccent,
                          ),
                        )
                      : const Text('Send code'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    final phoneNumber = _controller.text.trim();
    if (phoneNumber.isEmpty) return;
    ref.read(otpFlowControllerProvider.notifier).sendCode(phoneNumber);
  }
}
