import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/validation.dart';
import '../../theme/app_snackbar.dart';
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

/// Number-only entry, for a phone that already has an account — checked
/// up front via GET /auth/phone-exists (see _PhoneAuthPageState._submit),
/// which rejects a number with no account before an OTP is even sent
/// ("No account found. Please sign up."). This screen never sends a
/// name, so an existing user's name can never be touched by using it. A
/// number that slips past that check regardless (a race with someone
/// signing up elsewhere in the same instant) still can't create a
/// nameless dead end: GroupsHomePage's one-time safety net prompts for a
/// name in that case — see its _maybePromptForName.
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

    // Only relevant use today: GroupsHomePage sets this right before an
    // automatic sign-out (a session whose token the backend rejected —
    // see its own comment) so the person lands here already knowing why,
    // rather than just silently finding themselves back at Sign In with
    // no explanation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notice = ref.read(authNoticeProvider);
      if (notice == null) return;
      ref.read(authNoticeProvider.notifier).state = null;
      if (mounted) showAppSnackBar(context, notice);
    });

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
                  maxLength: displayNameMaxLength,
                  style: context.text.bodyLarge?.copyWith(color: c.ink),
                  decoration: InputDecoration(
                    counterText: '',
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
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(10),
                        ],
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

  // Flips which screen AuthGate shows, in place — see showSignUpProvider's
  // doc comment for why this can't be a pushed route: that would replace
  // AuthGate itself in the Navigator stack, and popUntil(isFirst) after a
  // later OTP completion (see OtpEntryPage) would then reveal this
  // pushed-over route again instead of the signed-in app.
  void _switchMode() {
    ref.read(showSignUpProvider.notifier).state = !widget.isSignUp;
  }

  Future<void> _submit() async {
    final nationalNumber = _phoneController.text.trim();

    // Name checked first when both are present: a housemate seeing a
    // combined "enter your name and phone number" for a name-only mistake
    // (phone already valid) had no way to tell which field actually
    // needed fixing.
    if (widget.isSignUp) {
      final nameError = validateDisplayName(_nameController.text);
      if (nameError != null) {
        setState(() => _validationError = nameError);
        return;
      }
    }

    final phoneError = validateNationalPhoneNumber(nationalNumber);
    if (phoneError != null) {
      setState(() => _validationError = phoneError);
      return;
    }

    final name = widget.isSignUp ? _nameController.text.trim() : null;
    setState(() => _validationError = null);

    final phoneNumber = '$_countryCode$nationalNumber';

    // Reject the mismatched case up front, before an OTP is even sent,
    // rather than letting OTP verification silently paper over it: Sign
    // Up with a number that already has an account used to auto-sign the
    // person in, and Sign In with a number that has none used to
    // silently create one — both were surprising, and the user-facing
    // ask for both was a visible error at this exact step instead. Fails
    // open on a network error: OTP still gets sent, and POST
    // /auth/sign-in's own is_new logic is the real backstop either way —
    // see its docstring for why a genuinely new number that slips
    // through here still ends up handled correctly, just without this
    // up-front message.
    setState(() => _checkingPhone = true);
    try {
      final exists = await ref.read(groupsRepositoryProvider).checkPhoneExists(phoneNumber);
      if (widget.isSignUp && exists) {
        setState(() {
          _checkingPhone = false;
          _validationError = 'You already have an account. Sign in instead.';
        });
        return;
      }
      if (!widget.isSignUp && !exists) {
        setState(() {
          _checkingPhone = false;
          _validationError = 'No account found. Please sign up.';
        });
        return;
      }
    } on ApiException {
      // Fall through and let OTP + POST /auth/sign-in handle it.
    } finally {
      if (mounted) setState(() => _checkingPhone = false);
    }

    // Resets the guard even if this isn't the first attempt this screen has
    // made — going back from the code screen (state is still whatever it
    // was left at, not necessarily OtpFlowIdle) and resubmitting a
    // corrected number used to leave this stuck true, so the next codeSent
    // was silently ignored and the app just sat there instead of
    // navigating to the (new) code screen.
    _navigatedForCurrentCodeSent = false;
    ref.read(otpFlowControllerProvider.notifier).sendCode(phoneNumber, displayName: name);
  }
}
