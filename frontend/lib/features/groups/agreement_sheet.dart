import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';

/// Add/edit sheet for one agreements-board item. Returns (title, content)
/// trimmed, or null if dismissed without confirming — same pure
/// picker/input shape as [showCustomNudgeSheet]; the actual create/update
/// call happens in the caller, after this sheet has already closed.
Future<(String, String)?> showAgreementSheet(
  BuildContext context, {
  String? initialTitle,
  String? initialContent,
}) {
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AgreementSheet(initialTitle: initialTitle, initialContent: initialContent),
  );
}

class _AgreementSheet extends StatefulWidget {
  const _AgreementSheet({this.initialTitle, this.initialContent});

  final String? initialTitle;
  final String? initialContent;

  @override
  State<_AgreementSheet> createState() => _AgreementSheetState();
}

class _AgreementSheetState extends State<_AgreementSheet> {
  late final _titleController = TextEditingController(text: widget.initialTitle);
  late final _contentController = TextEditingController(text: widget.initialContent);
  String? _error;

  bool get _isEditing => widget.initialTitle != null;

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
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
            Text(_isEditing ? 'Edit agreement' : 'New agreement', style: context.text.titleLarge),
            SizedBox(height: Space.sm.h),
            Text(
              'Visible to the whole house. Plain text only.',
              style: context.text.bodySmall,
            ),
            SizedBox(height: Space.lg.h),
            TextField(
              controller: _titleController,
              autofocus: true,
              maxLength: 100,
              textCapitalization: TextCapitalization.sentences,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: _fieldDecoration(context, hint: 'e.g. Trash schedule'),
            ),
            SizedBox(height: Space.sm.h),
            TextField(
              controller: _contentController,
              maxLines: 5,
              minLines: 2,
              textCapitalization: TextCapitalization.sentences,
              style: context.text.bodyLarge?.copyWith(color: c.ink),
              decoration: _fieldDecoration(context, hint: 'e.g. Bins out every Tuesday night.'),
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
                child: Text(_isEditing ? 'Save' : 'Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(BuildContext context, {required String hint}) {
    final c = context.colors;
    return InputDecoration(
      counterText: '',
      hintText: hint,
      hintStyle: context.text.bodyLarge?.copyWith(color: c.ink3),
      filled: true,
      fillColor: c.surface2,
      contentPadding: EdgeInsets.symmetric(horizontal: Space.md.w, vertical: Space.md.h),
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
    );
  }

  void _submit() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title.');
      return;
    }
    if (content.isEmpty) {
      setState(() => _error = 'Enter the details.');
      return;
    }
    Navigator.of(context).pop((title, content));
  }
}
