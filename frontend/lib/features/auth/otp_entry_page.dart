import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'auth_controller.dart';
import 'auth_state.dart';

/// How long "Resend code" stays disabled after a code is sent (the initial
/// automatic send, or a manual resend) — no existing cooldown pattern
/// elsewhere in this app to match (the nudge flows don't throttle
/// themselves client-side), so this picks a plain, ordinary default for an
/// SMS resend.
const _resendCooldown = Duration(seconds: 30);

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
  final _focusNode = FocusNode();

  // The phone number a code was actually sent to — captured from whichever
  // OtpFlowState carries it (there's always one by the time this screen is
  // showing) so _resend has something to call sendCode with again without
  // needing its own copy threaded in from phone_entry_page.dart.
  String? _phoneNumber;

  Timer? _resendCooldownTimer;
  int _resendSecondsRemaining = _resendCooldown.inSeconds;

  @override
  void initState() {
    super.initState();
    // Repaints the 6 boxes below on every keystroke (digit typed, or
    // backspaced) — the actual value still lives in _controller/_submit,
    // unchanged; this just drives the box-by-box visual.
    _controller.addListener(() => setState(() {}));
    // A code was already sent (automatically) the instant this screen
    // became reachable — see phone_entry_page.dart's codeSent listener —
    // so resend starts on cooldown too, not immediately available.
    _startResendCooldown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _resendCooldownTimer?.cancel();
    super.dispose();
  }

  void _startResendCooldown() {
    _resendCooldownTimer?.cancel();
    setState(() => _resendSecondsRemaining = _resendCooldown.inSeconds);
    _resendCooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendSecondsRemaining -= 1;
        if (_resendSecondsRemaining <= 0) timer.cancel();
      });
    });
  }

  void _resend() {
    final phoneNumber = _phoneNumber;
    if (phoneNumber == null || _resendSecondsRemaining > 0) return;
    // A fresh code invalidates whatever's still typed from the last one —
    // left in place, re-tapping Verify would just resubmit that same
    // (now-expired-or-wrong-enough-to-ask-for-a-resend) code and fail
    // identically again.
    _controller.clear();
    ref.read(otpFlowControllerProvider.notifier).resendCode(phoneNumber);
    _startResendCooldown();
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
    // A wrong/expired code used to just sit there in the boxes next to the
    // error text — re-tapping Verify with nothing changed reproduced the
    // exact same failure, which is most of what made this "flaky, took
    // three attempts" in practice: nothing *visibly* reset between
    // attempts, so it wasn't obvious the previous one had even been
    // rejected rather than just not registering the tap. Clearing on every
    // transition into OtpFlowError makes the failure unmistakable — the
    // boxes empty out right as the message appears — and leaves the caller
    // free to type a corrected code immediately.
    ref.listen<OtpFlowState>(otpFlowControllerProvider, (previous, next) {
      if (next is OtpFlowError && _controller.text.isNotEmpty) {
        _controller.clear();
        _focusNode.requestFocus();
      }
    });
    final phoneNumber = switch (flowState) {
      OtpFlowCodeSent(:final phoneNumber) => phoneNumber,
      OtpFlowVerifying(:final phoneNumber) => phoneNumber,
      OtpFlowError(:final phoneNumber) when phoneNumber.isNotEmpty => phoneNumber,
      _ => null,
    };
    if (phoneNumber != null) _phoneNumber = phoneNumber;

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
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Stack(
                  children: [
                    // The real input: fully transparent but still focusable
                    // and IME-connected, positioned under the 6 visible
                    // boxes. Still the same _controller driving _submit -
                    // only how the value is *drawn* changed.
                    //
                    // Wrapped in its own AutofillGroup (a lone field still
                    // needs one to reliably trigger the platform's SMS
                    // autofill UI — iOS's QuickType bar / Android's
                    // autofill framework, not the Android-only
                    // SMS Retriever broadcast API, which would need a
                    // dedicated plugin this app doesn't otherwise depend
                    // on) with autofillHints: [AutofillHints.oneTimeCode]
                    // so the OS can recognize this field as the one to
                    // offer the just-received code for, same as any native
                    // OTP field.
                    Opacity(
                      opacity: 0,
                      child: AutofillGroup(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          maxLength: 6,
                          decoration: const InputDecoration(counterText: '', border: InputBorder.none),
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var i = 0; i < 6; i++)
                            _OtpDigitBox(
                              digit: i < _controller.text.length ? _controller.text[i] : null,
                              active: i == _controller.text.length,
                            ),
                        ],
                      ),
                    ),
                  ],
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
              SizedBox(height: Space.md.h),
              Center(
                child: TextButton(
                  onPressed: _resendSecondsRemaining > 0 || isVerifying ? null : _resend,
                  child: Text(
                    _resendSecondsRemaining > 0
                        ? 'Resend code in ${_resendSecondsRemaining}s'
                        : 'Resend code',
                    style: context.text.bodySmall?.copyWith(
                      color: _resendSecondsRemaining > 0 ? c.ink3 : c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
    if (code.length != 6) {
      // Used to just silently do nothing — tapping Verify with an
      // incomplete code looked identical to the tap not registering at
      // all, which was its own share of "nothing happened, try again"
      // confusion on top of the stale-code issue above.
      showAppSnackBar(context, 'Enter all 6 digits.');
      return;
    }
    ref.read(otpFlowControllerProvider.notifier).confirmCode(code);
  }
}

/// One of the 6 square digit boxes: shows its digit once filled, an accent
/// border + glow ring while it's the next one to be filled, and a plain
/// outline otherwise. Purely decorative - the real value lives in
/// _OtpEntryPageState's hidden TextField/_controller.
class _OtpDigitBox extends StatelessWidget {
  const _OtpDigitBox({required this.digit, required this.active});

  final String? digit;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      width: 44.r,
      height: 52.r,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.sm.r),
        border: Border.all(color: active ? c.accent : c.line2, width: active ? 2 : 1),
        boxShadow: active
            ? [BoxShadow(color: c.accentRing, blurRadius: 8.r, spreadRadius: 1.r)]
            : null,
      ),
      child: Text(digit ?? '', style: context.text.titleLarge),
    );
  }
}
