import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../core/local_time.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'group_models.dart';
import 'groups_providers.dart';

/// Shows the chore pass for a just-booked (or previously booked)
/// reservation, with a way to mark it done. "Due" here is purely a
/// client-side comparison against `now()` at render time — nothing on the
/// backend fires at the chore's due time; see AppChore's doc comment.
Future<void> showChorePassSheet(BuildContext context, {required String groupId, required AppChore chore}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ChorePassSheet(groupId: groupId, chore: chore),
  );
}

class _ChorePassSheet extends ConsumerStatefulWidget {
  const _ChorePassSheet({required this.groupId, required this.chore});

  final String groupId;
  final AppChore chore;

  @override
  ConsumerState<_ChorePassSheet> createState() => _ChorePassSheetState();
}

class _ChorePassSheetState extends ConsumerState<_ChorePassSheet> {
  late bool _done = widget.chore.done;
  bool _submitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDue = !_done && DateTime.now().toUtc().isAfter(widget.chore.dueAt);

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
            Text('Your chore pass', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(widget.chore.template, style: context.text.bodyLarge),
            SizedBox(height: Space.xs.h),
            Text(
              _done
                  ? 'Done'
                  : isDue
                      ? 'Due now'
                      : 'Due ${widget.chore.dueAt.toLocalDateTimeLabel()}',
              style: context.text.bodySmall?.copyWith(
                color: _done ? c.open.solid : (isDue ? c.call.solid : c.ink3),
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
                onPressed: _done || _submitting ? null : _markDone,
                child: _submitting
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.onAccent),
                      )
                    : Text(_done ? 'Marked done' : 'Mark done'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markDone() async {
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref.read(groupsRepositoryProvider).markChoreDone(widget.chore.id);
      ref.invalidate(groupChoresProvider(widget.groupId));
      if (mounted) setState(() => _done = true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
