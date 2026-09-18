import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/api_config.dart';
import 'group_models.dart';

/// Connects to a group's live event stream (`GET .../groups/{id}/ws`) and
/// splits it into two feeds: [statuses] (the `{userId: MemberStatus}` map,
/// updated on `status_update`) and [nudges] (one [AppNudge] per `nudge`
/// event). Reconnects on drop with a fresh ID token each time, so a
/// mid-session token refresh is picked up automatically.
///
/// [nudges] is deliberately just a `Stream<AppNudge>` — nothing in the UI
/// (see `groupNudgesProvider`) knows or cares that it currently arrives
/// over this WebSocket. Swapping the transport for real FCM push later
/// means pointing that provider at a different `Stream<AppNudge>` source;
/// the screen that displays them doesn't change.
class GroupStatusClient {
  GroupStatusClient({required this.groupId, FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final String groupId;
  final FirebaseAuth _auth;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final Map<String, MemberStatus> _current = {};
  final _statusesController = StreamController<Map<String, MemberStatus>>.broadcast();
  final _nudgesController = StreamController<AppNudge>.broadcast();
  final _reservationsController = StreamController<AppReservation>.broadcast();
  final _memberJoinedController = StreamController<void>.broadcast();

  /// Emits the full current `{userId: MemberStatus}` map on every change
  /// (including the initial snapshot).
  Stream<Map<String, MemberStatus>> get statuses => _statusesController.stream;

  /// Emits one event per nudge received, in real time.
  Stream<AppNudge> get nudges => _nudgesController.stream;

  /// Emits one event per new reservation, in real time. Unlike [statuses],
  /// this isn't a running merged view — the Spaces screen re-fetches the
  /// full reservation list on each event rather than maintaining one here,
  /// since "list of bookings" doesn't have the same natural
  /// latest-value-per-key shape [statuses] does.
  Stream<AppReservation> get reservations => _reservationsController.stream;

  /// Fires once per member who joins the group, in real time — no payload,
  /// just a signal to refetch the member list (same "refetch on event"
  /// approach as [reservations], for the same reason: membership doesn't
  /// have a natural latest-value-per-key shape either).
  Stream<void> get memberJoined => _memberJoinedController.stream;

  Future<void> connect() async {
    if (_disposed) return;

    final user = _auth.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    if (token == null || _disposed) return;

    final uri = Uri.parse('$apiWsBaseUrl/groups/$groupId/ws').replace(
      queryParameters: {'token': token},
    );

    final channel = WebSocketChannel.connect(uri);
    _channel = channel;
    _subscription = channel.stream.listen(
      _handleMessage,
      onError: (_) => _scheduleReconnect(),
      onDone: _scheduleReconnect,
      cancelOnError: true,
    );
  }

  void _handleMessage(dynamic raw) {
    final data = jsonDecode(raw as String) as Map<String, dynamic>;

    switch (data['event']) {
      case 'snapshot':
        _current.clear();
        for (final entry in data['statuses'] as List<dynamic>) {
          final status = MemberStatus.fromJson(entry as Map<String, dynamic>);
          _current[status.userId] = status;
        }
        if (!_statusesController.isClosed) {
          _statusesController.add(Map.of(_current));
        }
      case 'status_update':
        final status = MemberStatus.fromJson(data);
        _current[status.userId] = status;
        if (!_statusesController.isClosed) {
          _statusesController.add(Map.of(_current));
        }
      case 'nudge':
        if (!_nudgesController.isClosed) {
          _nudgesController.add(AppNudge.fromJson(data));
        }
      case 'reservation':
        if (!_reservationsController.isClosed) {
          _reservationsController.add(AppReservation.fromJson(data));
        }
      case 'member_joined':
        if (!_memberJoinedController.isClosed) {
          _memberJoinedController.add(null);
        }
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), connect);
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _statusesController.close();
    _nudgesController.close();
    _reservationsController.close();
    _memberJoinedController.close();
  }
}
