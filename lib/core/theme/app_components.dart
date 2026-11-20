import 'package:flutter/material.dart';

import '../ui/friendly_error.dart';
import 'app_theme.dart';

// Design system v2 components (UI_REDESIGN.md, section 5.4). New screens
// use these; existing screens move to them in Phase 3.

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

enum AppButtonKind { primary, secondary, tertiary, danger }

/// The one button: [AppButtonKind.primary] for the screen's main action
/// (one per screen), secondary for alternatives, tertiary for low-emphasis
/// links, danger for destructive actions. Always at least 48 px tall.
/// While [loading], it shows a spinner and can't be pressed.
class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AppButtonKind.primary,
    this.icon,
    this.loading = false,
    this.expand = false,
  });

  const AppButton.secondary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  }) : kind = AppButtonKind.secondary;

  const AppButton.tertiary({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  }) : kind = AppButtonKind.tertiary;

  const AppButton.danger({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  }) : kind = AppButtonKind.danger;

  final String label;
  final VoidCallback? onPressed;
  final AppButtonKind kind;
  final IconData? icon;
  final bool loading;

  /// Fill the available width (e.g. in a sticky action bar).
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final pressed = loading ? null : onPressed;
    final spinnerColor = switch (kind) {
      AppButtonKind.primary || AppButtonKind.danger => scheme.onPrimary,
      _ => scheme.primary,
    };
    final Widget content = loading
        ? SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: spinnerColor,
            ),
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20),
                const SizedBox(width: 8),
              ],
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          );

    final button = switch (kind) {
      AppButtonKind.primary => FilledButton(onPressed: pressed, child: content),
      AppButtonKind.secondary => OutlinedButton(
        onPressed: pressed,
        child: content,
      ),
      AppButtonKind.tertiary => TextButton(onPressed: pressed, child: content),
      AppButtonKind.danger => FilledButton(
        onPressed: pressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.danger,
          foregroundColor: Colors.white,
        ),
        child: content,
      ),
    };
    return Semantics(
      button: true,
      label: loading ? '$label, working' : null,
      excludeSemantics: loading,
      child: expand ? SizedBox(width: double.infinity, child: button) : button,
    );
  }
}

/// An icon button with a 48 px target and a required [tooltip] (also its
/// screen-reader label).
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    icon: Icon(icon),
    tooltip: tooltip,
    color: color,
    onPressed: onPressed,
    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
  );
}

// ---------------------------------------------------------------------------
// Tags and status
// ---------------------------------------------------------------------------

enum TagTone { neutral, brand, reward, onImage }

/// A small label ("Heritage", "+80 XP", "Open now"). Pick the tone for the
/// surface it sits on, so it's never white-on-white.
class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.icon, this.tone = TagTone.neutral});

  final String label;
  final IconData? icon;
  final TagTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      TagTone.neutral => (colors.surfaceMuted, colors.textSecondary),
      TagTone.brand => (scheme.primaryContainer, scheme.onPrimaryContainer),
      TagTone.reward => (
        colors.reward.withValues(alpha: 0.18),
        colors.rewardText,
      ),
      TagTone.onImage => (const Color(0x99000000), Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

enum StatusKind { info, success, warning, error, offline }

({IconData icon, Color fg, Color bg}) _statusStyle(
  StatusKind kind,
  AppColors c,
) => switch (kind) {
  StatusKind.info => (
    icon: Icons.info_outline,
    fg: c.info,
    bg: c.infoContainer,
  ),
  StatusKind.success => (
    icon: Icons.check_circle_outline,
    fg: c.success,
    bg: c.successContainer,
  ),
  StatusKind.warning => (
    icon: Icons.warning_amber_rounded,
    fg: c.warning,
    bg: c.warningContainer,
  ),
  StatusKind.error => (
    icon: Icons.error_outline,
    fg: c.danger,
    bg: c.dangerContainer,
  ),
  StatusKind.offline => (
    icon: Icons.cloud_off_outlined,
    fg: c.textSecondary,
    bg: c.surfaceMuted,
  ),
};

/// A full-width notice: icon, [title], optional [message] and action.
/// Status is always carried by the icon and words, not colour alone.
class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.kind,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final StatusKind kind;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(kind, AppColors.of(context));
    final text = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      liveRegion: kind == StatusKind.error,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: style.bg,
          borderRadius: AppRadius.card,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(style.icon, color: style.fg, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.titleSmall),
                  if (message != null) ...[
                    const SizedBox(height: 2),
                    Text(message!, style: text.bodyMedium),
                  ],
                ],
              ),
            ),
            if (actionLabel != null)
              TextButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ),
      ),
    );
  }
}

/// A compact status: icon plus words ("Safe", "Needs help").
class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.kind, required this.label});

  final StatusKind kind;
  final String label;

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(kind, AppColors.of(context));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: style.bg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 14, color: style.fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: style.fg),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lists
// ---------------------------------------------------------------------------

/// One row: optional [leading] (icon, avatar or 40–56 px thumbnail),
/// [title], optional [subtitle] and [trailing]. At least 56 px tall.
class AppListTile extends StatelessWidget {
  const AppListTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 14)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyLarge,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// A person: avatar, name, a subtitle, one trailing action (or a ⋮
/// menu), and optional [actions] under the text (e.g. Accept / Decline).
class PersonTile extends StatelessWidget {
  const PersonTile({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.trailing,
    this.actions,
    this.onTap,
  });

  final Widget avatar;
  final String name;
  final String? subtitle;
  final Widget? trailing;
  final Widget? actions;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleSmall,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    if (actions != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: actions,
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 4), trailing!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Rows grouped in one card with dividers between them, with an optional
/// small heading above ("ACCOUNT").
class AppListGroup extends StatelessWidget {
  const AppListGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
            child: Text(
              title!,
              style: Theme.of(context).textTheme.labelMedium
                  ?.copyWith(color: colors.textSecondary),
            ),
          ),
        Material(
          color: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.card,
            side: BorderSide(color: colors.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A settings row: icon, title, optional value or description, chevron.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  /// Replaces the chevron (e.g. a Switch).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => AppListTile(
    leading: Icon(icon, color: AppColors.of(context).textSecondary),
    title: title,
    subtitle: subtitle,
    onTap: onTap,
    trailing:
        trailing ??
        (onTap == null
            ? null
            : Icon(
                Icons.chevron_right_rounded,
                color: AppColors.of(context).textSecondary,
              )),
  );
}

// ---------------------------------------------------------------------------
// Sheets
// ---------------------------------------------------------------------------

/// The standard bottom sheet: drag handle, [title] with a close button,
/// scrollable [body], an optional sticky [action] (usually an [AppButton]),
/// and room for the keyboard.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  required Widget body,
  Widget? action,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(sheetContext).textTheme.titleLarge,
                    ),
                  ),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(sheetContext).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: body,
              ),
            ),
            if (action != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: action,
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Whole-screen states
// ---------------------------------------------------------------------------

/// A centred state: icon, [title], [message] and an optional action.
class _StateView extends StatelessWidget {
  const _StateView({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 40, color: colors.textSecondary),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center, style: text.titleMedium),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: colors.textSecondary),
              ),
              if (actionLabel != null) ...[
                const SizedBox(height: 16),
                AppButton(label: actionLabel!, onPressed: onAction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Something failed: a friendly message (never raw exception text) and
/// Try again.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => _StateView(
    icon: Icons.error_outline,
    title: "Couldn't load this",
    message: friendlyError(error),
    actionLabel: onRetry == null ? null : 'Try again',
    onAction: onRetry,
  );
}

/// A feature the user can't use yet (not available in this version, or a
/// permission is off), with the way to unlock it when there is one.
class GateCard extends StatelessWidget {
  const GateCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => _StateView(
    icon: icon,
    title: title,
    message: message,
    actionLabel: actionLabel,
    onAction: onAction,
  );
}

/// "Sign in to …" with a Sign in button: the standard signed-out state.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({super.key, required this.reason, required this.onSignIn});

  /// What signing in unlocks, e.g. "see your friends and groups".
  final String reason;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) => _StateView(
    icon: Icons.person_outline,
    title: 'Sign in to continue',
    message: 'Sign in to $reason.',
    actionLabel: 'Sign in',
    onAction: onSignIn,
  );
}
