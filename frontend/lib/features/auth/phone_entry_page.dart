import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import '../groups/groups_providers.dart';
import 'auth_controller.dart';
import 'auth_state.dart';
import 'otp_entry_page.dart';

/// India-only for now, matching the simpler Recurva flow: the field only
/// ever collects the national number, this prefix is fixed and prepended
/// on submit. If QuietPass ever needs other countries, this becomes a
/// picker instead of a constant — not a speculative abstraction worth
/// building before it's needed.
const _countryCode = '+91';

/// Number-only entry, for a phone that (presumably) already has an
/// account. Whether it actually does is a backend decision either way
/// (see OtpFlowController.sendCode / POST /auth/sign-in) — this screen
/// never sends a name, so an existing user's name can never be touched
/// by using it, and a genuinely new number that lands here just gets
/// prompted for a name once on the home screen instead of up front.
class SignInPage extends StatelessWidget {
  const SignInPage({super.key});

  @override
  Widget build(BuildContext context) => const _PhoneAuthPage(isSignUp: false);
}

/// Name-and-number entry, for a first-time signup. If the number turns
/// out to already have an account, the entered name is simply ignored
/// server-side and the existing one is kept — see
/// OtpFlowController._signInAndStoreToken for the "you already have an
/// account" notice shown in that case.
class SignUpPage extends StatelessWidget {
  const SignUpPage({super.key});

  @override
  Widget build(BuildContext context) => const _PhoneAuthPage(isSignUp: true);
}

class _PhoneAuthPage extends ConsumerStatefulWidget {
  const _PhoneAuthPage({required this.isSignUp});

  final bool isSignUp;

  @override
  ConsumerState<_PhoneAuthPage> createState() => _PhoneAuthPageState();
}

class _PhoneAuthPageState extends ConsumerState<_PhoneAuthPage> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _navigatedForCurrentCodeSent = false;
  bool _checkingPhone = false;
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
    final isSending = flowState is OtpFlowSendingCode || _checkingPhone;

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
                widget.isSignUp
                    ? 'Tell us your name and phone number to create an account.'
                    : 'Enter your phone number to sign in.',
                style: context.text.bodySmall,
              ),
              SizedBox(height: Space.xl.h),
              if (widget.isSignUp) ...[
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
              ],
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
              SizedBox(height: Space.md.h),
              Center(
                child: TextButton(
                  onPressed: isSending ? null : _switchMode,
                  child: Text(
                    widget.isSignUp
                        ? 'Already have an account? Sign in'
                        : 'New here? Create an account',
                    style: context.text.bodySmall?.copyWith(color: c.ink2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _switchMode() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => widget.isSignUp ? const SignInPage() : const SignUpPage(),
      ),
    );
  }

  Future<void> _submit() async {
    final name = widget.isSignUp ? _nameController.text.trim() : null;
    final nationalNumber = _phoneController.text.trim();

    if (nationalNumber.isEmpty || (widget.isSignUp && (name == null || name.isEmpty))) {
      setState(
        () => _validationError = widget.isSignUp
            ? 'Enter your name and phone number to continue.'
            : 'Enter your phone number to continue.',
      );
      return;
    }
    setState(() => _validationError = null);

    final phoneNumber = '$_countryCode$nationalNumber';

    // Sign Up specifically: reject an already-registered number here,
    // before an OTP is even sent, rather than silently signing the
    // person in only after they've gone through verification — that's
    // what used to happen, and the user-facing ask was for this to be a
    // visible error at this exact step instead. Fails open on a network
    // error: OTP still gets sent, and POST /auth/sign-in's own is_new
    // check is the real backstop either way.
    if (widget.isSignUp) {
      setState(() => _checkingPhone = true);
      try {
        final exists = await ref.read(groupsRepositoryProvider).checkPhoneExists(phoneNumber);
        if (exists) {
          setState(() {
            _checkingPhone = false;
            _validationError = 'You already have an account. Sign in instead.';
          });
          return;
        }
      } on ApiException {
        // Fall through and let OTP + POST /auth/sign-in handle it.
      } finally {
        if (mounted) setState(() => _checkingPhone = false);
      }
    }

    ref.read(otpFlowControllerProvider.notifier).sendCode(phoneNumber, displayName: name);
  }
}
