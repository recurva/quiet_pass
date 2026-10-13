import 'package:flutter/material.dart';

import 'motion.dart';
import 'theme_x.dart';

/// A member's avatar: their uploaded photo if they have one, otherwise a
/// coloured-initial fallback built from their display name — the one
/// shared place this logic lives, so every screen that shows a person
/// (housemates list, profile, anywhere else one gets added later) renders
/// identically instead of each screen growing its own slightly-different
/// copy. [size] is a logical pixel value scaled via [Space]-style `.r`
/// scaling at the call site's discretion — this widget itself takes the
/// already-resolved size so it has no opinion on screen-size scaling.
class Avatar extends StatelessWidget {
  const Avatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.size = 40,
    this.statusDotColor,
  });

  final String name;
  final String? photoUrl;
  final double size;

  /// When set, a small coloured dot is drawn at the bottom-right corner —
  /// the same "presence dot" language status badges already use elsewhere,
  /// available here for a future housemates-list-with-live-dot use case
  /// without needing a second avatar variant.
  final Color? statusDotColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final initials = _initialsFrom(name);

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
      child: Text(
        initials,
        style: context.text.labelLarge?.copyWith(
          color: c.onAccent,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );

    final body = photoUrl == null
        ? fallback
        : ClipOval(
            child: SizedBox(
              width: size,
              height: size,
              child: Image.network(
                photoUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                // Fades the photo in once decoded rather than popping in
                // the instant bytes arrive — frameBuilder fires on every
                // frame including the very first, so this only animates
                // the transition from "nothing" to "first frame", not
                // every subsequent repaint.
                frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
                  if (wasSynchronouslyLoaded) return child;
                  final motionOff = reduceMotion(context);
                  return AnimatedOpacity(
                    opacity: frame == null ? 0 : 1,
                    duration: motionOff ? Duration.zero : Motion.state,
                    curve: Motion.curve,
                    child: child,
                  );
                },
                errorBuilder: (context, error, stackTrace) => fallback,
              ),
            ),
          );

    if (statusDotColor == null) return body;

    final dotSize = size * 0.32;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          body,
          Positioned(
            right: -dotSize * 0.08,
            bottom: -dotSize * 0.08,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: statusDotColor,
                shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: dotSize * 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _initialsFrom(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return '?';
  final parts = trimmed.split(RegExp(r'\s+'));
  if (parts.length == 1) {
    return parts[0].characters.take(2).toString().toUpperCase();
  }
  return (parts[0].characters.take(1).toString() + parts[1].characters.take(1).toString())
      .toUpperCase();
}
