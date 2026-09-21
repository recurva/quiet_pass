import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'groups_providers.dart';

/// Shared by two call sites: the one-time onboarding prompt (first sign-in,
/// while the backend still has the display name defaulted to the phone
/// number — see get_current_user's first-sight provisioning) and the
/// profile/settings entry point for editing it later. [skippable] controls
/// whether onboarding's "not now" option is offered; the profile entry
/// point always requires either a save or a plain dismiss via the back
/// gesture, since there's nothing to "skip" once a name is already set.
Future<bool> showEditNameSheet(
  BuildContext context, {
  required String initialValue,
  bool skippable = false,
}) {
  return showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: !skippable,
        enableDrag: !skippable,
        builder: (_) => _EditNameSheet(initialValue: initialValue, skippable: skippable),
      ).then((saved) => saved ?? false);
}

class _EditNameSheet extends ConsumerStatefulWidget {
  const _EditNameSheet({required this.initialValue, required this.skippable});

  final String initialValue;
  final bool skippable;

  @override
  ConsumerState<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends ConsumerState<_EditNameSheet> {
  late final _controller = TextEditingController(text: widget.initialValue);
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return PopScope(
      canPop: widget.skippable,
      child: Padding(
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
              Text('What should housemates call you?', style: context.text.titleLarge),
              SizedBox(height: Space.sm.h),
              Text(
                'Shown instead of your phone number, everywhere in the house.',
                style: context.text.bodySmall,
              ),
              SizedBox(height: Space.lg.h),
              TextField(
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                style: context.text.bodyLarge?.copyWith(color: c.ink),
                decoration: InputDecoration(
                  hintText: 'Your name',
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
              Row(
                children: [
                  if (widget.skippable) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.ink2,
                          side: BorderSide(color: c.line2),
                          padding: EdgeInsets.symmetric(vertical: Space.md.h),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(Radii.sm.r),
                          ),
                        ),
                        child: const Text('Not now'),
                      ),
                    ),
                    SizedBox(width: Space.sm.w),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? SizedBox(
                              width: 20.r,
                              height: 20.r,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                            )
                          : const Text('Save'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name, or tap Not now.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(groupsRepositoryProvider).updateDisplayName(name);
      ref.invalidate(currentBackendUserProvider);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
