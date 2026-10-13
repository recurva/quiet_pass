import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One shared motion language for the whole app — every animated
/// interaction uses these durations/curve, not a bespoke value picked per
/// screen. Keeps the feel consistent and calm rather than a patchwork of
/// slightly-different timings nobody would consciously notice but that add
/// up to feeling unpolished.
class Motion {
  const Motion._();

  /// Press feedback (scale/opacity on tap-down) — short enough to read as
  /// instant, not a delay.
  static const press = Duration(milliseconds: 120);

  /// A value changing in place (status badge, a count, a chip's selected
  /// state) — long enough to actually be perceived as a transition, short
  /// enough to never feel like you're waiting on it.
  static const state = Duration(milliseconds: 200);

  /// A sheet or page settling into view.
  static const sheet = Duration(milliseconds: 320);

  static const curve = Curves.easeOut;
}

/// True when the OS-level "reduce motion" accessibility setting is on.
/// Every animation in the app checks this and falls back to an instant
/// cross-fade (or no motion at all) instead of movement — motion is
/// always a nicety here, never load-bearing for understanding what
/// happened, so turning it off must never hide information, only the
/// movement itself.
bool reduceMotion(BuildContext context) => MediaQuery.of(context).disableAnimations;

/// Centralizes the two haptic "weights" used across the app, so every
/// call site reaches for the same two feelings instead of picking
/// different `HapticFeedback` calls ad hoc:
/// - [selection] — light, for picking/toggling something (a chip, a
///   status option) that hasn't committed yet.
/// - [commit] — medium, for an action that actually took effect (status
///   set, booking made, nudge sent, chore marked done).
class Haptics {
  const Haptics._();

  static void selection() => HapticFeedback.selectionClick();
  static void commit() => HapticFeedback.mediumImpact();
}

/// Wraps any tappable widget with a subtle scale-down-on-press, reversing
/// on release — the "every tap responds instantly" feel. Deliberately
/// restrained (a few percent scale, not a bounce): calm, not flashy.
/// Falls back to no visual change (but keeps functioning normally) when
/// [reduceMotion] is on, since the scale itself is motion with no
/// informational content to preserve.
class PressFeedback extends StatefulWidget {
  const PressFeedback({
    super.key,
    required this.onTap,
    required this.child,
    this.behavior = HitTestBehavior.opaque,
  });

  final VoidCallback? onTap;
  final Widget child;
  final HitTestBehavior behavior;

  @override
  State<PressFeedback> createState() => _PressFeedbackState();
}

class _PressFeedbackState extends State<PressFeedback> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final scale = _pressed && !reduceMotion(context) ? 0.96 : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTap: widget.onTap,
      onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
      onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
      onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
      child: AnimatedScale(
        scale: scale,
        duration: Motion.press,
        curve: Motion.curve,
        child: widget.child,
      ),
    );
  }
}

/// A value that cross-fades (and, unless reduce-motion is on, slightly
/// scales) between states — the shared building block behind the status
/// badge and the dinner count animating when they change, instead of
/// hard-jumping to the new value.
class AnimatedValueSwitcher extends StatelessWidget {
  const AnimatedValueSwitcher({super.key, required this.value, required this.builder});

  /// Anything that uniquely identifies the current displayed state (a
  /// string, an enum, a record) — AnimatedSwitcher keys its transition on
  /// this via a ValueKey, so it only animates when it actually changes.
  final Object value;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final motionOff = reduceMotion(context);
    return AnimatedSwitcher(
      duration: motionOff ? Duration.zero : Motion.state,
      switchInCurve: Motion.curve,
      switchOutCurve: Motion.curve,
      transitionBuilder: (child, animation) {
        if (motionOff) return child;
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(key: ValueKey(value), child: builder(context)),
    );
  }
}

/// A list item that fades and slides up into place the first time it's
/// built — covers "a nudge arriving, a housemate's status appearing"
/// animating in rather than jumping. Reduce-motion collapses this to an
/// instant cross-fade (opacity only, no slide).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child});

  final Widget child;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Motion.state)..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motionOff = reduceMotion(context);
    final curved = CurvedAnimation(parent: _controller, curve: Motion.curve);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offsetY = motionOff ? 0.0 : (1 - curved.value) * 8;
        return Opacity(
          opacity: motionOff ? 1.0 : curved.value,
          child: Transform.translate(offset: Offset(0, offsetY), child: child),
        );
      },
      child: widget.child,
    );
  }
}
