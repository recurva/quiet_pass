import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'otp_entry_page.dart';

/// India-only for now, matching the simpler Recurva flow: the field only
/// ever collects the national number, this prefix is fixed and prepended
/// on submit. If QuietPass ever needs other countries, this becomes a
/// picker instead of a constant — not a speculative abstraction worth
/// building before it's needed.
const _countryCode = '+91';

/// First screen of the sign-in flow: collect a phone number and ask Firebase
/// to send an SMS code. Reads only from `context.colors` / `Space` / `Radii`,
/// same as the rest of the app.
class PhoneEntryPage extends ConsumerStatefulWidget {
  const PhoneEntryPage({super.key});

  @override
  ConsumerState<PhoneEntryPage> createState() => _PhoneEntryPageState();
}

class _PhoneEntryPageState extends ConsumerState<PhoneEntryPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _navigatedForCurrentCodeSent = false;
  String? _validationError;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
                'Tell us your name and phone number to sign in.',
                style: context.text.bodySmall,
              ),
              SizedBox(height: Space.xl.h),
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                style: context.text.bodyLarge?.copyWith(color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Your name',
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
              SizedBox(height: Space.md.h),
              Container(
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.md.r),
                  border: Border.all(color: c.line2),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: Space.md.w),
                      child: Text(
                        _countryCode,
                        style: context.text.bodyLarge?.copyWith(
                          color: c.ink2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 24.r,
                      child: VerticalDivider(color: c.line2, width: 1, thickness: 1),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: context.text.bodyLarge?.copyWith(color: c.ink),
                        decoration: InputDecoration(
                          hintText: '98765 43210',
                          hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
                          filled: true,
                          fillColor: Colors.transparent,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: Space.md.w,
                            vertical: Space.md.h,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.md.r),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.md.r),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(Radii.md.r),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_validationError != null || flowState is OtpFlowError) ...[
                SizedBox(height: Space.sm.h),
                Text(
                  _validationError ?? (flowState as OtpFlowError).message,
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
    final name = _nameController.text.trim();
    final nationalNumber = _phoneController.text.trim();

    if (name.isEmpty || nationalNumber.isEmpty) {
      setState(() => _validationError = 'Enter your name and phone number to continue.');
      return;
    }
    setState(() => _validationError = null);

    ref.read(otpFlowControllerProvider.notifier).sendCode(
          '$_countryCode$nationalNumber',
          displayName: name,
        );
  }
}
