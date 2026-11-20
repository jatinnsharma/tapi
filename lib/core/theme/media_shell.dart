import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

/// Text and icons on the black media screens.
const Color mediaOnColor = Colors.white;
const Color mediaOnColorMuted = Colors.white70;

/// A dark, see-through pill or scrim behind white text on photos.
const Color mediaScrim = Color(0x99000000);
const Color mediaScrimClear = Color(0x00000000);

/// Dark ink on the white media controls (spinners on the shutter).
const Color mediaOnLight = Colors.black;

/// The idle ring around a recording button.
const Color mediaRingDim = Color(0x66FFFFFF);

/// Recording red (ring, dot, timer).
const Color mediaRecordRed = Color(0xFFFF3B30);

/// A light veil over unselected photos in pickers.
const Color mediaUnselectedVeil = Color(0x66FFFFFF);

/// The dark theme for photos and video: black surfaces, white controls, and
/// a white primary button (the brand green is too dark on black).
ThemeData mediaTheme() {
  final base = AppTheme.dark;
  const onMedia = Colors.white;
  return base.copyWith(
    scaffoldBackgroundColor: Colors.black,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      foregroundColor: onMedia,
      elevation: 0,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: onMedia),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: onMedia,
        foregroundColor: Colors.black,
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: onMedia,
        side: const BorderSide(color: Colors.white54),
        minimumSize: const Size(64, 52),
        shape: const StadiumBorder(),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: onMedia),
    ),
  );
}

/// Black, edge-to-edge chrome for the camera, review, viewers and voice
/// notes: [body] fills the screen, with a top bar and an optional [bottom]
/// bar on soft scrims so white controls read over any photo. Hide the
/// chrome with [chromeVisible] (e.g. tap to view a photo alone).
class MediaShell extends StatelessWidget {
  const MediaShell({
    super.key,
    required this.body,
    this.title,
    this.leading,
    this.actions = const [],
    this.bottom,
    this.chromeVisible = true,
    this.onClose,
  });

  final Widget body;
  final String? title;

  /// Replaces the close button.
  final Widget? leading;
  final List<Widget> actions;
  final Widget? bottom;
  final bool chromeVisible;

  /// What the close button does; pops by default.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = mediaTheme();
    return Theme(
      data: theme,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: [
              body,
              _Chrome(
                visible: chromeVisible,
                top: true,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 16),
                  child: Row(
                    children: [
                      leading ??
                          IconButton(
                            icon: const Icon(Icons.close_rounded),
                            tooltip: 'Close',
                            onPressed:
                                onClose ??
                                () => Navigator.of(context).maybePop(),
                          ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: title == null
                            ? const SizedBox.shrink()
                            : Text(
                                title!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
              ),
              if (bottom != null)
                _Chrome(
                  visible: chromeVisible,
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                    child: bottom,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A top or bottom bar on a black-to-clear scrim that fades away when
/// hidden.
class _Chrome extends StatelessWidget {
  const _Chrome({
    required this.visible,
    required this.top,
    required this.child,
  });

  final bool visible;
  final bool top;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: top ? Alignment.topCenter : Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : AppMotion.base,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: top ? Alignment.topCenter : Alignment.bottomCenter,
                end: top ? Alignment.bottomCenter : Alignment.topCenter,
                colors: const [Color(0x99000000), Color(0x00000000)],
              ),
            ),
            child: SafeArea(top: top, bottom: !top, child: child),
          ),
        ),
      ),
    );
  }
}

/// The round camera shutter: a white ring around a white disc that dips
/// when pressed. Shows a spinner while [busy].
class ShutterButton extends StatefulWidget {
  const ShutterButton({
    super.key,
    required this.onPressed,
    this.busy = false,
    this.label = 'Take photo',
  });

  final VoidCallback? onPressed;
  final bool busy;
  final String label;

  static const double size = 76;

  @override
  State<ShutterButton> createState() => _ShutterButtonState();
}

class _ShutterButtonState extends State<ShutterButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.busy ? '${widget.label}, saving' : widget.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapCancel: () => setState(() => _down = false),
        onTapUp: enabled
            ? (_) {
                setState(() => _down = false);
                widget.onPressed!();
              }
            : null,
        child: Container(
          width: ShutterButton.size,
          height: ShutterButton.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          alignment: Alignment.center,
          child: AnimatedScale(
            scale: _down ? 0.85 : 1,
            duration: AppMotion.fast,
            child: Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled || widget.busy ? Colors.white : Colors.white38,
              ),
              alignment: Alignment.center,
              child: widget.busy
                  ? const SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.black,
                      ),
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
