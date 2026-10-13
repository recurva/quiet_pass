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
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Repaints the 6 boxes below on every keystroke (digit typed, or
    // backspaced) — the actual value still lives in _controller/_submit,
    // unchanged; this just drives the box-by-box visual.
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
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
      OtpFlowError(:final phoneNumber) when phoneNumber.isNotEmpty => phoneNumber,
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
              GestureDetector(
                onTap: () => _focusNode.requestFocus(),
                child: Stack(
                  children: [
                    // The real input: fully transparent but still focusable
                    // and IME-connected, positioned under the 6 visible
                    // boxes. Still the same _controller driving _submit -
                    // only how the value is *drawn* changed.
                    Opacity(
                      opacity: 0,
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(counterText: '', border: InputBorder.none),
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
