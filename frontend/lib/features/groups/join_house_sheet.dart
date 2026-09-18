import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'groups_providers.dart';

/// Shows the join-by-code sheet and returns once it's closed. Callers
/// should invalidate [myGroupsProvider] afterwards to pick up the new group.
Future<void> showJoinHouseSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _JoinHouseSheet(),
  );
}

class _JoinHouseSheet extends ConsumerStatefulWidget {
  const _JoinHouseSheet();

  @override
  ConsumerState<_JoinHouseSheet> createState() => _JoinHouseSheetState();
}

class _JoinHouseSheetState extends ConsumerState<_JoinHouseSheet> {
  final _controller = TextEditingController();
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
            Text('Join a house', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text('Enter the invite code someone shared with you.', style: context.text.bodySmall),
            SizedBox(height: Space.lg.h),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.none,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: InputDecoration(
                hintText: 'Invite code',
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
            if (_error != null) ...[
              SizedBox(height: Space.sm.h),
              Text(_error!, style: context.text.bodySmall?.copyWith(color: c.call.solid)),
            ],
            SizedBox(height: Space.lg.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                      )
                    : const Text('Join'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(groupsRepositoryProvider).joinGroup(code);
      ref.invalidate(myGroupsProvider);
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
