import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Widest the app content grows; on tablets/desktop the gradient still fills
/// the window while the content stays in a comfortable centred column.
const double kMaxContentWidth = 960;

/// Layered, softly lit app background:
///  1. the right-to-left base gradient,
///  2. a warm glow in the top-right corner,
///  3. a teal bloom in the bottom-right corner,
///  4. a pale highlight in the top-left corner.
/// The lighting layers are static, so they're isolated in a RepaintBoundary.
class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  static const _warmGlow = RadialGradient(
    center: Alignment(1.05, -0.95),
    radius: 0.95,
    colors: [Color(0x40F4F7B4), Color(0x00F4F7B4)],
  );

  static const _tealBloom = RadialGradient(
    center: Alignment(1.1, 0.95),
    radius: 0.85,
    colors: [Color(0x262BA6A0), Color(0x002BA6A0)],
  );

  static const _highlight = RadialGradient(
    center: Alignment(-0.95, -1.0),
    radius: 0.9,
    colors: [Color(0x80FFFFFF), Color(0x00FFFFFF)],
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppTheme.backgroundGradient,
                ),
              ),
              DecoratedBox(decoration: BoxDecoration(gradient: _warmGlow)),
              DecoratedBox(decoration: BoxDecoration(gradient: _tealBloom)),
              DecoratedBox(decoration: BoxDecoration(gradient: _highlight)),
            ],
          ),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kMaxContentWidth),
            child: child,
          ),
        ),
      ],
    );
  }
}

/// Frosted-glass surface: blurred backdrop, translucent diagonal tint
/// (top-right to bottom-left, matching the page gradient), a thin light
/// border and a soft green shadow.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.radius = 22,
    this.tint,
    this.blur = 14,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double radius;

  /// Optional accent colour mixed into the glass.
  final Color? tint;
  final double blur;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);
    final accent = tint;

    Widget content = Padding(padding: padding, child: child);
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: borderRadius,
        splashColor: AppTheme.primaryGreen.withValues(alpha: 0.12),
        highlightColor: AppTheme.primaryGreen.withValues(alpha: 0.06),
        child: content,
      );
    }

    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: AppTheme.deepGreen.withValues(alpha: 0.14),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    Colors.white.withValues(alpha: 0.80),
                    accent == null
                        ? Colors.white.withValues(alpha: 0.52)
                        : Color.alphaBlend(
                            accent.withValues(alpha: 0.16),
                            Colors.white.withValues(alpha: 0.55),
                          ),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.75),
                  width: 1.2,
                ),
              ),
              child: Material(type: MaterialType.transparency, child: content),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gentle scale feedback on hover (desktop/web) and press. It doesn't consume
/// taps, so the tappable child (InkWell, button, ...) keeps working.
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child});

  final Widget child;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.97 : (_hovered ? 1.02 : 1.0);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: widget.child,
        ),
      ),
    );
  }
}

/// Fades and lifts its child into place once, optionally after [delay].
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });

  final Widget child;
  final Duration delay;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );
  late final Animation<Offset> _offset = Tween(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(_curve);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _controller.forward();
    } else {
      _timer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: show the content straight away.
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _timer?.cancel();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _curve,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Primary call-to-action: emerald gradient with a soft glow.
class GlowButton extends StatelessWidget {
  const GlowButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });

  final VoidCallback onPressed;
  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    const radius = 18.0;
    return PressableScale(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          gradient: const LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            colors: [
              AppTheme.emerald,
              AppTheme.primaryGreen,
              AppTheme.deepGreen,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.emerald.withValues(alpha: 0.45),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(radius),
            splashColor: Colors.white.withValues(alpha: 0.2),
            highlightColor: Colors.white.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: Colors.white),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
