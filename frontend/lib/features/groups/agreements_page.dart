import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../core/api_client.dart';
import '../../theme/app_snackbar.dart';
import '../../theme/dimens.dart';
import '../../theme/theme_x.dart';
import 'agreement_sheet.dart';
import 'group_models.dart';
import 'groups_providers.dart';

/// The house agreements pinboard: a flat list of plain-text pinned items
/// (rules, trash schedule, landlord contact, notes). Any member can view;
/// add/edit/remove are admin-only, enforced server-side — [isAdmin] here
/// only controls whether this screen *offers* those actions, same split
/// GroupDetailPage already uses for member management.
class AgreementsPage extends ConsumerWidget {
  const AgreementsPage({super.key, required this.groupId, required this.groupName, required this.isAdmin});

  final String groupId;
  final String groupName;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    ref.watch(groupAgreementsLiveRefreshProvider(groupId));
    final agreementsAsync = ref.watch(groupAgreementsProvider(groupId));

    return Scaffold(
      backgroundColor: c.bg,
      floatingActionButton: isAdmin
          ? FloatingActionButton(
              onPressed: () => _addAgreement(context, ref),
              child: const Icon(Icons.add),
            )
          : null,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(Space.base.w),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(context),
              SizedBox(height: Space.lg.h),
              agreementsAsync.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (error, _) => Padding(
                  padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                  child: Text(
                    friendlyErrorMessage(error),
                    style: context.text.bodySmall?.copyWith(color: c.ink3),
                  ),
                ),
                data: (agreements) {
                  if (agreements.isEmpty) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: Space.lg.h),
                      child: Text(
                        isAdmin
                            ? 'Nothing pinned yet. Add a house rule, the trash schedule, or the landlord\'s contact.'
                            : 'Nothing pinned yet.',
                        style: context.text.bodySmall?.copyWith(color: c.ink3),
                      ),
                    );
                  }
                  return Column(
                    children: [
                      for (final agreement in agreements)
                        Padding(
                          padding: EdgeInsets.only(bottom: Space.sm.h),
                          child: _AgreementCard(
                            groupId: groupId,
                            agreement: agreement,
                            isAdmin: isAdmin,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          style: IconButton.styleFrom(
            backgroundColor: c.surface2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm.r)),
          ),
          icon: Icon(Icons.arrow_back, color: c.ink2, size: 20.r),
        ),
        SizedBox(width: Space.md.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('House agreements', style: context.text.titleLarge),
              SizedBox(height: 2.h),
              Text(groupName, style: context.text.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addAgreement(BuildContext context, WidgetRef ref) async {
    final result = await showAgreementSheet(context);
    if (result == null || !context.mounted) return;
    final (title, content) = result;

    try {
      await ref.read(groupsRepositoryProvider).createAgreement(groupId, title, content);
      ref.invalidate(groupAgreementsProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}

class _AgreementCard extends ConsumerWidget {
  const _AgreementCard({required this.groupId, required this.agreement, required this.isAdmin});

  final String groupId;
  final AppAgreement agreement;
  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(Space.base.w),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.md.r),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  agreement.title,
                  style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (isAdmin)
                PopupMenuButton<_AgreementAction>(
                  icon: Icon(Icons.more_vert, color: c.ink2, size: 20.r),
                  onSelected: (action) => switch (action) {
                    _AgreementAction.edit => _edit(context, ref),
                    _AgreementAction.remove => _remove(context, ref),
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: _AgreementAction.edit, child: Text('Edit')),
                    PopupMenuItem(value: _AgreementAction.remove, child: Text('Remove')),
                  ],
                ),
            ],
          ),
          SizedBox(height: Space.xs.h),
          Text(agreement.content, style: context.text.bodyMedium),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final result = await showAgreementSheet(
      context,
      initialTitle: agreement.title,
      initialContent: agreement.content,
    );
    if (result == null || !context.mounted) return;
    final (title, content) = result;

    try {
      await ref.read(groupsRepositoryProvider).updateAgreement(groupId, agreement.id, title, content);
      ref.invalidate(groupAgreementsProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupsRepositoryProvider).deleteAgreement(groupId, agreement.id);
      ref.invalidate(groupAgreementsProvider(groupId));
    } on ApiException catch (e) {
      if (context.mounted) showAppSnackBar(context, e.message);
    }
  }
}

enum _AgreementAction { edit, remove }
