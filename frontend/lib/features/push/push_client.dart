import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/app_navigation.dart';
import '../groups/group_detail_by_id_page.dart';
import '../groups/groups_repository.dart';

/// Wraps firebase_messaging: registers this device's FCM token with the
/// backend, keeps it fresh on rotation, and routes a notification tap to
/// the relevant group.
///
/// Foreground messages are received (see [FirebaseMessaging.onMessage],
/// not wired here) but deliberately never rendered as a system
/// notification — while the app is foregrounded, the WebSocket-driven
/// in-app banner (group_detail_page.dart) already shows the same nudge, so
/// doing both would double-notify. That's a backend-side tradeoff too: see
/// the backend README's push section for why the server can't just skip
/// pushing to foregrounded members itself.
class PushClient {
  PushClient(this._repository);

  final GroupsRepository _repository;
  final _messaging = FirebaseMessaging.instance;

  bool _started = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;

  Future<NotificationSettings> requestPermission() {
    return _messaging.requestPermission(alert: true, badge: true, sound: true);
  }

  /// The platform's own record of this permission — persists across app
  /// restarts and sign-ins on its own, unlike any in-app flag. Callers use
  /// this to decide whether the rationale sheet still needs showing at
  /// all: [AuthorizationStatus.notDetermined] means it's never been
  /// asked; anything else (authorized, denied, ...) is already a settled,
  /// platform-remembered decision.
  Future<AuthorizationStatus> permissionStatus() async {
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus;
  }

  Future<void> registerCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _repository.registerDeviceToken(token, platform: _platformName);
    }
  }

  /// Wires token refresh and notification-tap navigation for the lifetime
  /// of the app. Safe to call more than once — only the first call does
  /// anything, so callers don't need to track whether it's already run.
  void start() {
    if (_started) return;
    _started = true;

    _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((token) {
      _repository.registerDeviceToken(token, platform: _platformName);
    });

    _openedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen(_openGroupFrom);

    _messaging.getInitialMessage().then((message) {
      if (message != null) _openGroupFrom(message);
    });
  }

  void _openGroupFrom(RemoteMessage message) {
    final groupId = message.data['group_id'];
    if (groupId == null) return;
    rootNavigatorKey.currentState?.push(
      MaterialPageRoute(builder: (_) => GroupDetailByIdPage(groupId: groupId)),
    );
  }

  String get _platformName {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
  }

  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _openedAppSubscription?.cancel();
  }
}
