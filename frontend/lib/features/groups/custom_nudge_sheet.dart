import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'nudge_wire.dart';

/// Shows the custom-nudge sheet: type a short message, confirm. Returns the
/// trimmed message, or null if dismissed without confirming.
///
/// Same shape as showQuietPulseSheet — a pure picker/input that doesn't
/// call the backend itself, so a stray dismiss can never swallow a send or
/// its error (the actual send happens in the caller, after this sheet has
/// already closed).
Future<String?> showCustomNudgeSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _CustomNudgeSheet(),
  );
}

class _CustomNudgeSheet extends StatefulWidget {
  const _CustomNudgeSheet();

  @override
  State<_CustomNudgeSheet> createState() => _CustomNudgeSheetState();
}

class _CustomNudgeSheetState extends State<_CustomNudgeSheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.base.w,
        right: Space.base.w,
        top: Space.base.h,
        bottom: MediaQuery.of(context).viewInsets.bottom + Space.base.h,
      ),
      child: Container(
        padding: EdgeInsets.all(Space.base.w),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg.r),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Custom nudge', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Sent to the whole house. No name attached.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: customNudgeMessageMaxLength,
              maxLines: 3,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'e.g. Running the vacuum in 10 minutes',
                hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
                filled: true,
                fillColor: c.surface2,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
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
            if (_error != null) ...[
              SizedBox(height: Space.sm.h),
              Text(_error!, style: context.text.bodySmall?.copyWith(color: c.call.solid)),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submit,
                child: const Text('Send'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final message = _controller.text.trim();
    if (message.isEmpty) {
      setState(() => _error = 'Enter a message.');
      return;
    }
    if (message.length > customNudgeMessageMaxLength) {
      setState(
        () => _error = 'Keep it under $customNudgeMessageMaxLength characters.',
      );
      return;
    }
    Navigator.of(context).pop(message);
  }
}
