import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../groups/groups_providers.dart';
import 'push_client.dart';

final pushClientProvider = Provider<PushClient>((ref) {
  final client = PushClient(ref.watch(groupsRepositoryProvider));
  ref.onDispose(client.dispose);
  return client;
});
