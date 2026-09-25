import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../core/app_navigation.dart';
import '../groups/group_detail_by_id_page.dart';
import '../groups/groups_repository.dart';

const _androidChannel = AndroidNotificationChannel(
  'nudges',
  'Housemate nudges',
  description: 'Quiet-pulse and preset nudges from your house.',
  importance: Importance.high,
);

/// Wraps firebase_messaging: registers this device's FCM token with the
/// backend, keeps it fresh on rotation, and routes a notification tap to
/// the relevant group.
///
/// Foreground messages ([FirebaseMessaging.onMessage]) are rendered as a
/// local notification here — Android's own foreground/background
/// determination (which drives whether the OS auto-shows a system
/// notification for us) isn't the same thing as "the WS banner is visibly
/// on screen right now": a locked phone can still count as foreground to
/// Android in that determination, in which case the OS never auto-shows
/// anything and, without this, nothing else would either — a real gap,
/// not a hypothetical one; it's what silently swallowed a nudge sent to a
/// locked test device that the WS in-app banner couldn't have shown
/// either way (nothing's visible on a locked screen).
class PushClient {
  PushClient(this._repository);

  final GroupsRepository _repository;
  final _messaging = FirebaseMessaging.instance;
  final _localNotifications = FlutterLocalNotificationsPlugin();

  bool _started = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _openedAppSubscription;
  StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;

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

    // flutter_local_notifications doesn't support web; on web there's
    // nothing to initialize and onMessage's default (silent, no system
    // notification) is already the right behavior for a browser tab.
    if (!kIsWeb) {
      _initLocalNotifications();
      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen(_showLocalNotification);
    }
  }

  Future<void> _initLocalNotifications() async {
    await _localNotifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final groupId = response.payload;
        if (groupId == null) return;
        rootNavigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => GroupDetailByIdPage(groupId: groupId)),
        );
      },
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // Same reasoning as _openGroupFrom: a member_removed tap must never
      // carry a group_id payload, or the tap handler below would try to
      // open a group the caller no longer belongs to.
      payload: message.data['event'] == 'member_removed' ? null : message.data['group_id'],
    );
  }

  void _openGroupFrom(RemoteMessage message) {
    // A member_removed tap must never open that group's detail page —
    // the caller isn't a member of it anymore by the time they tap this,
    // and every membership-gated fetch on that screen would just 403.
    // GroupsHomePage's own resume refresh (see its WidgetsBindingObserver)
    // is what actually reflects the removal; there's nowhere useful for
    // this tap to navigate to beyond the app's own default landing.
    if (message.data['event'] == 'member_removed') return;

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
    _foregroundMessageSubscription?.cancel();
  }
}
