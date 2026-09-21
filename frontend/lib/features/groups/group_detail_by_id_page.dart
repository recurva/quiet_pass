import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../theme/theme_x.dart';
import 'group_detail_page.dart';
import 'groups_providers.dart';

/// Resolves a bare group id (all a push notification's data payload
/// carries) into the full [AppGroup] GroupDetailPage needs, then shows it.
/// Tapping a house in the list already has the AppGroup in hand and can
/// push GroupDetailPage directly; a notification tap can't.
class GroupDetailByIdPage extends ConsumerWidget {
  const GroupDetailByIdPage({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final groupsAsync = ref.watch(myGroupsProvider);

    return groupsAsync.when(
      loading: () => Scaffold(
        backgroundColor: c.bg,
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        backgroundColor: c.bg,
        body: Center(
          child: Text(friendlyErrorMessage(error), style: context.text.bodySmall?.copyWith(color: c.ink3)),
        ),
      ),
      data: (groups) {
        final matches = groups.where((group) => group.id == groupId);
        if (matches.isEmpty) {
          return Scaffold(
            backgroundColor: c.bg,
            body: Center(
              child: Text(
                "Couldn't find that house.",
                style: context.text.bodySmall?.copyWith(color: c.ink3),
              ),
            ),
          );
        }
        return GroupDetailPage(group: matches.first);
      },
    );
  }
}
