import 'package:flutter/material.dart';

/// Lets code outside the widget tree (a notification tap arriving while
/// the app is backgrounded/terminated) push a route without needing a
/// [BuildContext] of its own.
final rootNavigatorKey = GlobalKey<NavigatorState>();
